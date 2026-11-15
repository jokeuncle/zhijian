import Foundation

public final class DictionaryStore: @unchecked Sendable {
    public let path: String
    private let db: SQLiteConnection
    private let lock = NSRecursiveLock()

    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["ZHIJIAN_DATABASE"], !override.isEmpty { return NSString(string: override).expandingTildeInPath }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zhijian/library.sqlite").path
    }

    public init(path: String = DictionaryStore.defaultPath, seed: Bool = true) throws {
        self.path = path; db = try SQLiteConnection(path: path)
        try migrate()
        if try db.scalar("SELECT COUNT(*) FROM metadata WHERE key='initialized'") > 0 { return }
        try locked {
            try db.transaction {
                if try db.scalar("SELECT COUNT(*) FROM metadata WHERE key='initialized'") == 0 {
                    if seed {
                        let document = try SeedContent.load()
                        _ = try importLocked(ImportBatch(entries: document.entries), actor: "initial-notes")
                        try saveCollection(document.collection)
                    }
                    try db.execute("INSERT INTO metadata(key,value) VALUES('initialized','1')")
                }
            }
        }
    }

    private func migrate() throws {
        let schema=try db.scalar("PRAGMA user_version")
        guard schema <= 1 else { throw LibraryError.invalid("这个词库由更新版本的知间创建，请升级应用后再打开。") }
        if schema == 1 { return }
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try db.execute("""
                CREATE TABLE IF NOT EXISTS entries(
                  id TEXT PRIMARY KEY, title TEXT NOT NULL, title_key TEXT NOT NULL, english TEXT NOT NULL,
                  summary TEXT NOT NULL, category TEXT NOT NULL, kind TEXT NOT NULL, mastery TEXT NOT NULL,
                  favorite INTEGER NOT NULL, due_at REAL NOT NULL, updated_at REAL NOT NULL, opened_at REAL,
                  deleted_at REAL, revision INTEGER NOT NULL, payload TEXT NOT NULL)
                """)
            try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS entries_title ON entries(title_key) WHERE deleted_at IS NULL")
            try db.execute("CREATE INDEX IF NOT EXISTS entries_category ON entries(deleted_at,category,title_key)")
            try db.execute("CREATE INDEX IF NOT EXISTS entries_due ON entries(deleted_at,due_at)")
            try db.execute("CREATE INDEX IF NOT EXISTS entries_mastery ON entries(deleted_at,mastery)")
            try db.execute("CREATE INDEX IF NOT EXISTS entries_favorite ON entries(deleted_at,favorite)")
            try db.execute("CREATE INDEX IF NOT EXISTS entries_recent ON entries(deleted_at,opened_at DESC)")
            try db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(id UNINDEXED, body, tokenize='trigram')")
            try db.execute("CREATE TABLE IF NOT EXISTS collections(id TEXT PRIMARY KEY, title TEXT NOT NULL, payload TEXT NOT NULL)")
            try db.execute("""
                CREATE TABLE IF NOT EXISTS collection_entries(
                  collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                  entry_id TEXT NOT NULL REFERENCES entries(id), position INTEGER NOT NULL,
                  PRIMARY KEY(collection_id,entry_id))
                """)
            try db.execute("CREATE INDEX IF NOT EXISTS collection_order ON collection_entries(collection_id,position)")
            try db.execute("CREATE TABLE IF NOT EXISTS history(id INTEGER PRIMARY KEY,entry_id TEXT NOT NULL,action TEXT NOT NULL,actor TEXT NOT NULL, timestamp REAL NOT NULL,snapshot TEXT NOT NULL)")
            try db.execute("CREATE INDEX IF NOT EXISTS history_entry ON history(entry_id,id DESC)")
            try db.execute("PRAGMA user_version=1")
        }
    }

    /// A portable identity stored with the library, independent of its filesystem location.
    public func libraryIdentifier() throws -> String {
        try locked { try db.transaction {
            if let id=try db.rows("SELECT value FROM metadata WHERE key='library-id'").first?["value"] { return id }
            let id=UUID().uuidString.lowercased()
            try db.execute("INSERT INTO metadata(key,value) VALUES('library-id',?)",[.text(id)])
            return id
        } }
    }

    public func dataVersion() throws -> Int { try locked { try db.scalar("PRAGMA data_version") } }

    public func list(_ query: LibraryQuery = LibraryQuery()) throws -> EntryPage {
        try locked {
            guard (1...200).contains(query.limit), query.offset >= 0 else { throw LibraryError.invalid("每页应为 1–200 条，偏移不能为负数。") }
            let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 256 else { throw LibraryError.invalid("搜索内容不能超过 256 个字符。") }
            var join = "", conditions = [query.trashOnly ? "e.deleted_at IS NOT NULL" : "e.deleted_at IS NULL"]
            var values: [SQLValue] = []
            if let entryID = query.entryID { conditions.append("e.id=?"); values.append(.text(entryID)) }
            if let collectionID = query.collectionID {
                join += " JOIN collection_entries ce ON ce.entry_id=e.id"
                conditions.append("ce.collection_id=?"); values.append(.text(collectionID))
            }
            if !text.isEmpty {
                join += " JOIN entries_fts ON entries_fts.id=e.id"
                if text.count >= 3 {
                    conditions.append("entries_fts MATCH ?")
                    values.append(.text("\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""))
                } else {
                    conditions.append("instr(lower(entries_fts.body),lower(?))>0"); values.append(.text(text))
                }
            }
            if let category = query.category { conditions.append("e.category=?"); values.append(.text(category)) }
            if let mastery = query.mastery { conditions.append("e.mastery=?"); values.append(.text(mastery.rawValue)) }
            if query.favoritesOnly { conditions.append("e.favorite=1") }
            if query.dueOnly { conditions.append("e.due_at<=?"); values.append(.double(Date().timeIntervalSince1970)) }
            if query.recentOnly { conditions.append("e.opened_at IS NOT NULL") }
            let from = " FROM entries e" + join + " WHERE " + conditions.joined(separator: " AND ")
            let count = try db.scalar("SELECT COUNT(*)" + from, values)
            let position = query.collectionID == nil ? "NULL AS position" : "ce.position AS position"
            let sort = query.collectionID != nil ? "ce.position ASC" : (query.recentOnly ? "e.opened_at DESC,e.id" : (query.dueOnly ? "e.due_at ASC,e.title_key" : "e.title_key ASC,e.id"))
            var offset=query.offset
            if let anchor=query.anchorEntryID,
               let ordinal=try db.rows("SELECT ordinal FROM (SELECT e.id,ROW_NUMBER() OVER (ORDER BY \(sort)) AS ordinal" + from + ") WHERE id=?",values + [.text(anchor)]).first?["ordinal"].flatMap(Int.init) {
                offset=((ordinal-1)/query.limit)*query.limit
            }
            let rows = try db.rows("SELECT e.id,e.title,e.english,e.summary,e.category,e.kind,e.mastery,e.favorite,\(position)" + from + " ORDER BY \(sort) LIMIT ? OFFSET ?", values + [.int(query.limit), .int(offset)])
            let summaries = rows.map { row in
                EntrySummary(id: row["id"]!, title: row["title"]!, english: row["english"]!, summary: row["summary"]!,
                             category: row["category"]!, kind: EntryKind(rawValue: row["kind"]!) ?? .concept,
                             mastery: Mastery(rawValue: row["mastery"]!) ?? .new, favorite: row["favorite"] == "1", position: row["position"].flatMap(Int.init))
            }
            return EntryPage(entries: summaries, total: count, offset: offset)
        }
    }

    public func entry(id: String) throws -> Entry {
        try locked {
            guard let payload = try db.rows("SELECT payload FROM entries WHERE id=?", [.text(id)]).first?["payload"] else { throw LibraryError.notFound(id) }
            return try LibraryJSON.decoder().decode(Entry.self, from: Data(payload.utf8))
        }
    }

    public func create(_ draft: EntryDraft, actor: String = "desktop", collectionID: String? = nil) throws -> Entry {
        try locked { try db.transaction {
            let entry = try createLocked(draft, actor: actor)
            if let collectionID {
                guard var collection = try collections(includeTrash:true).first(where: { $0.id == collectionID }) else { throw LibraryError.invalid("找不到指定阅读集。") }
                collection.entryIDs.append(entry.id); try saveCollection(collection)
            }
            return entry
        } }
    }

    private func createLocked(_ draft: EntryDraft, actor: String) throws -> Entry {
        var content = try draft.validated()
        let id = content.id ?? UUID().uuidString.lowercased(); content.id = id
        guard try db.scalar("SELECT COUNT(*) FROM entries WHERE id=?", [.text(id)]) == 0 else { throw LibraryError.invalid("词条 ID 已存在：\(id)") }
        try validateTitle(content.title, excluding: id)
        try validateRelations(content.relatedIDs, selfID: id)
        let now = Date()
        let entry = Entry(id: id, revision: 1, content: content, mastery: .new, favorite: false, createdAt: now,
                          updatedAt: now, lastOpenedAt: nil, deletedAt: nil, nextReviewAt: now, reviewCount: 0)
        try save(entry, action: "create", actor: actor)
        return entry
    }

    public func update(id: String, patch: EntryPatch, expectedRevision: Int, actor: String = "desktop") throws -> Entry {
        try mutate(id: id, expectedRevision: expectedRevision, action: "update", actor: actor) { current in
            guard current.deletedAt == nil else { throw LibraryError.invalid("请先从废纸篓恢复词条，再进行编辑。") }
            return patch.applying(to: current)
        }
    }

    public func trash(id: String, expectedRevision: Int, actor: String = "desktop") throws -> Entry {
        try mutate(id: id, expectedRevision: expectedRevision, action: "trash", actor: actor) { entry in
            var entry = entry; entry.deletedAt = Date(); return entry
        }
    }

    public func restore(id: String, expectedRevision: Int, actor: String = "desktop") throws -> Entry {
        try mutate(id: id, expectedRevision: expectedRevision, action: "restore", actor: actor) { entry in
            var entry = entry; entry.deletedAt = nil; return entry
        }
    }

    /// Permanently removes only entries currently in the trash, in one transaction.
    public func emptyTrash(actor: String = "desktop") throws -> Int {
        try locked { try db.transaction {
            let ids = Set(try db.rows("SELECT id FROM entries WHERE deleted_at IS NOT NULL").compactMap { $0["id"] })
            guard !ids.isEmpty else { return 0 }
            var cursor = 0
            while true {
                let rows = try db.rows("SELECT rowid AS cursor,payload FROM entries WHERE deleted_at IS NULL AND rowid>? ORDER BY rowid LIMIT 200", [.int(cursor)])
                guard !rows.isEmpty else { break }
                for row in rows {
                    cursor = Int(row["cursor"]!)!
                    var entry = try LibraryJSON.decoder().decode(Entry.self, from: Data(row["payload"]!.utf8))
                    let retained = entry.content.relatedIDs.filter { !ids.contains($0) }
                    if retained != entry.content.relatedIDs {
                        entry.content.relatedIDs = retained
                        entry.revision += 1; entry.updatedAt = Date()
                        try save(entry, action: "purge-relations", actor: actor)
                    }
                }
            }
            for var collection in try collections(includeTrash: true) {
                let retained = collection.entryIDs.filter { !ids.contains($0) }
                if retained != collection.entryIDs {
                    collection.entryIDs = retained; try saveCollection(collection)
                }
            }
            try db.execute("DELETE FROM history WHERE entry_id IN (SELECT id FROM entries WHERE deleted_at IS NOT NULL)")
            // Old snapshots must remain usable without restoring dangling relations.
            cursor = 0
            while true {
                let rows = try db.rows("SELECT id,snapshot FROM history WHERE id>? ORDER BY id LIMIT 200", [.int(cursor)])
                guard !rows.isEmpty else { break }
                for row in rows {
                    cursor = Int(row["id"]!)!
                    var snapshot = try LibraryJSON.decoder().decode(Entry.self, from: Data(row["snapshot"]!.utf8))
                    let retained = snapshot.content.relatedIDs.filter { !ids.contains($0) }
                    if retained != snapshot.content.relatedIDs {
                        snapshot.content.relatedIDs = retained
                        try db.execute("UPDATE history SET snapshot=? WHERE id=?", [.text(try LibraryJSON.string(snapshot)), .int(cursor)])
                    }
                }
            }
            try db.execute("DELETE FROM entries_fts WHERE id IN (SELECT id FROM entries WHERE deleted_at IS NOT NULL)")
            try db.execute("DELETE FROM collection_entries WHERE entry_id IN (SELECT id FROM entries WHERE deleted_at IS NOT NULL)")
            try db.execute("DELETE FROM entries WHERE deleted_at IS NOT NULL")
            return ids.count
        } }
    }

    public func recordReview(id: String, rating: Int, expectedRevision: Int, actor: String = "desktop") throws -> Entry {
        guard (0...2).contains(rating) else { throw LibraryError.invalid("复习评分只能是 0、1、2。") }
        return try mutate(id: id, expectedRevision: expectedRevision, action: "review", actor: actor) { entry in
            guard entry.deletedAt == nil else { throw LibraryError.invalid("废纸篓中的词条不能复习。") }
            var entry = entry
            entry.mastery = rating == 2 ? .understood : .learning
            let seconds: Double = rating == 0 ? 600 : (rating == 1 ? 2 * 86400 : Double(min(60, 7 * (entry.reviewCount + 1))) * 86400)
            entry.reviewCount += 1; entry.nextReviewAt = Date().addingTimeInterval(seconds)
            return entry
        }
    }

    public func markOpened(id: String) throws {
        try locked {
            // Recency is intentionally separate from the versioned content to avoid edit conflicts and FTS rewrites on every read.
            try db.execute("UPDATE entries SET opened_at=? WHERE id=?", [.double(Date().timeIntervalSince1970), .text(id)])
        }
    }

    public func history(id: String, limit: Int = 50) throws -> [ChangeRecord] {
        try locked {
            let rows = try db.rows("SELECT id,entry_id,action,actor,timestamp,snapshot FROM history WHERE entry_id=? ORDER BY id DESC LIMIT ?", [.text(id), .int(max(1, min(200, limit)))])
            return try rows.map { row in
                ChangeRecord(id: Int(row["id"]!)!, entryID: row["entry_id"]!, action: row["action"]!, actor: row["actor"]!,
                             timestamp: Date(timeIntervalSince1970: Double(row["timestamp"]!)!),
                             snapshot: try LibraryJSON.decoder().decode(Entry.self, from: Data(row["snapshot"]!.utf8)))
            }
        }
    }

    public func revert(id: String, historyID: Int, expectedRevision: Int, actor: String = "desktop") throws -> Entry {
        try mutate(id: id, expectedRevision: expectedRevision, action: "revert", actor: actor) { current in
            guard let payload = try self.db.rows("SELECT snapshot FROM history WHERE id=? AND entry_id=?", [.int(historyID), .text(id)]).first?["snapshot"] else { throw LibraryError.invalid("找不到这个历史版本。") }
            let snapshot = try LibraryJSON.decoder().decode(Entry.self, from: Data(payload.utf8))
            var entry = current; entry.content = snapshot.content; entry.favorite = snapshot.favorite
            return entry
        }
    }

    private func mutate(id: String, expectedRevision: Int, action: String, actor: String, body: (Entry) throws -> Entry) throws -> Entry {
        try locked {
            try db.transaction {
                let current = try entry(id: id)
                guard current.revision == expectedRevision else { throw LibraryError.conflict }
                var changed = try body(current)
                changed.content = try changed.content.validated(); changed.content.id = id
                if changed.deletedAt == nil { try validateTitle(changed.title, excluding: id) }
                try validateRelations(changed.content.relatedIDs, selfID: id)
                changed.revision = current.revision + 1; changed.updatedAt = Date()
                try save(changed, action: action, actor: actor); return changed
            }
        }
    }

    public func collections(includeTrash:Bool = false) throws -> [ReadingCollection] {
        try locked {
            let all=try db.rows("SELECT payload FROM collections ORDER BY rowid").map {
                try LibraryJSON.decoder().decode(ReadingCollection.self, from: Data($0["payload"]!.utf8))
            }
            if includeTrash { return all }
            let members=try db.rows("SELECT ce.collection_id,ce.entry_id FROM collection_entries ce JOIN entries e ON e.id=ce.entry_id WHERE e.deleted_at IS NULL ORDER BY ce.position")
            let grouped=Dictionary(grouping:members,by: { $0["collection_id"]! }).mapValues { Set($0.compactMap { $0["entry_id"] }) }
            return all.map { original in var c=original; let ids=grouped[c.id] ?? []; c.entryIDs=c.entryIDs.filter { ids.contains($0) }; return c }
        }
    }

    public func stats() throws -> LibraryStats {
        try locked {
            let now = Date().timeIntervalSince1970
            let row = try db.rows("""
                SELECT COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) AS entries,
                  COUNT(CASE WHEN deleted_at IS NULL AND favorite=1 THEN 1 END) AS favorites,
                  COUNT(CASE WHEN deleted_at IS NULL AND due_at<=? THEN 1 END) AS due,
                  COUNT(CASE WHEN deleted_at IS NULL AND mastery='understood' THEN 1 END) AS understood,
                  COUNT(deleted_at) AS trash FROM entries
                """, [.double(now)]).first!
            let categories = try db.rows("SELECT DISTINCT category FROM entries WHERE deleted_at IS NULL ORDER BY category").compactMap { $0["category"] }
            return LibraryStats(entries: Int(row["entries"]!)!, favorites: Int(row["favorites"]!)!, due: Int(row["due"]!)!,
                                understood: Int(row["understood"]!)!, trash: Int(row["trash"]!)!, categories: categories)
        }
    }

    public func importBatch(_ batch: ImportBatch, actor: String = "import") throws -> ImportResult {
        try locked { try db.transaction { try importLocked(batch, actor: actor) } }
    }

    private func importLocked(_ batch: ImportBatch, actor: String) throws -> ImportResult {
        guard batch.entries.count <= 100_000 else { throw LibraryError.invalid("单次最多导入 100,000 个词条。") }
        let drafts = try batch.entries.map { try $0.validated() }
        var existingIDs = Set(try db.rows("SELECT id FROM entries").compactMap { $0["id"] })
        var titles = Dictionary(try db.rows("SELECT title_key,id FROM entries WHERE deleted_at IS NULL").map { ($0["title_key"]!, $0["id"]!) }, uniquingKeysWith: { first, _ in first })
        var planned: [EntryDraft] = [], memberIDs: [String] = [], idMapping: [String: String] = [:], skipped = 0
        for var draft in drafts {
            let key = titleKey(draft.title)
            if let same = titles[key] {
                memberIDs.append(same); if let id = draft.id { idMapping[id] = same }; skipped += 1; continue
            }
            if let id = draft.id, existingIDs.contains(id) { memberIDs.append(id); skipped += 1; continue }
            let id = draft.id ?? UUID().uuidString.lowercased(); draft.id = id
            existingIDs.insert(id); titles[key] = id; memberIDs.append(id); planned.append(draft)
        }
        // Validate the entire relation set before inserting anything; forward references inside a batch are allowed.
        for draft in planned {
            for related in draft.relatedIDs {
                let mapped = idMapping[related] ?? related
                guard existingIDs.contains(mapped), mapped != draft.id else { throw LibraryError.invalid("无效的关联词条：\(related)") }
            }
        }
        let now = Date()
        for var draft in planned {
            draft.relatedIDs = draft.relatedIDs.map { idMapping[$0] ?? $0 }
            let entry = Entry(id: draft.id!, revision: 1, content: draft, mastery: .new, favorite: false, createdAt: now, updatedAt: now,
                              lastOpenedAt: nil, deletedAt: nil, nextReviewAt: now, reviewCount: 0)
            try save(entry, action: "create", actor: actor)
        }
        var collectionID: String?
        if let title = batch.collectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let collection = ReadingCollection(title: title, subtitle: batch.collectionSubtitle ?? "", entryIDs: unique(memberIDs))
            try saveCollection(collection); collectionID = collection.id
        }
        return ImportResult(created: planned.count, skipped: skipped, collectionID: collectionID)
    }

    public func exportArchive(includeTrash: Bool = true) throws -> LibraryArchive {
        try locked { try db.readTransaction {
            // The explicit backup/export operation may stream the whole library; normal UI operations never do.
            var entries = try db.rows("SELECT payload FROM entries" + (includeTrash ? "" : " WHERE deleted_at IS NULL") + " ORDER BY rowid").map {
                try LibraryJSON.decoder().decode(Entry.self, from: Data($0["payload"]!.utf8))
            }
            let ids = Set(entries.map(\.id))
            if !includeTrash { entries=entries.map { original in var e=original; e.content.relatedIDs=e.content.relatedIDs.filter { ids.contains($0) }; return e } }
            let collections = try self.collections(includeTrash:includeTrash).map { original -> ReadingCollection in
                var c = original; c.entryIDs = c.entryIDs.filter { ids.contains($0) }; return c
            }
            return LibraryArchive(entries: entries, collections: collections)
        } }
    }

    public func importArchive(_ archive: LibraryArchive, actor: String = "restore-backup") throws -> ImportResult {
        guard archive.schemaVersion == 1 else { throw LibraryError.invalid("不支持这个备份版本。") }
        return try locked {
            try db.transaction {
                // Backups preserve schedule and notes. Existing IDs or titles are never overwritten implicitly.
                var created = 0, skipped = 0
                let existing = Set(try db.rows("SELECT id FROM entries").compactMap { $0["id"] })
                let importedIDs=archive.entries.map(\.id)
                guard Set(importedIDs).count == importedIDs.count, importedIDs.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { throw LibraryError.invalid("备份包含重复或无效的词条 ID。") }
                let allIDs = existing.union(importedIDs)
                for var e in archive.entries {
                    e.content = try e.content.validated(); e.content.id = e.id
                    if existing.contains(e.id) { skipped += 1; continue }
                    if e.deletedAt == nil, try db.scalar("SELECT COUNT(*) FROM entries WHERE title_key=? AND deleted_at IS NULL", [.text(titleKey(e.title))]) > 0 {
                        throw LibraryError.invalid("备份中的“\(e.title)”与现有词名冲突，导入已取消。请导入到空词库，或使用普通导入合并。")
                    }
                    guard e.revision > 0, e.content.relatedIDs.allSatisfy({ allIDs.contains($0) && $0 != e.id }) else { throw LibraryError.invalid("备份中的版本或关联关系无效。") }
                    try save(e, action: "import-backup", actor: actor); created += 1
                }
                for collection in archive.collections {
                    guard collection.entryIDs.allSatisfy({ allIDs.contains($0) }) else { throw LibraryError.invalid("阅读集包含不存在的词条。") }
                    if try db.scalar("SELECT COUNT(*) FROM collections WHERE id=?", [.text(collection.id)]) == 0 { try saveCollection(collection) }
                }
                return ImportResult(created: created, skipped: skipped, collectionID: archive.collections.first?.id)
            }
        }
    }

    private func save(_ e: Entry, action: String, actor: String) throws {
        let payload = try LibraryJSON.string(e)
        try db.execute("""
            INSERT INTO entries(id,title,title_key,english,summary,category,kind,mastery,favorite,due_at,updated_at,opened_at,deleted_at,revision,payload)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
            title=excluded.title,title_key=excluded.title_key,english=excluded.english,summary=excluded.summary,
            category=excluded.category,kind=excluded.kind,mastery=excluded.mastery,favorite=excluded.favorite,
            due_at=excluded.due_at,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at,revision=excluded.revision,payload=excluded.payload
            """, [.text(e.id), .text(e.title), .text(titleKey(e.title)), .text(e.content.english), .text(e.summary), .text(e.content.category),
                   .text(e.content.kind.rawValue), .text(e.mastery.rawValue), .int(e.favorite ? 1 : 0), .double(e.nextReviewAt.timeIntervalSince1970),
                   .double(e.updatedAt.timeIntervalSince1970), e.lastOpenedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                   e.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null, .int(e.revision), .text(payload)])
        let rowID = try db.scalar("SELECT rowid FROM entries WHERE id=?", [.text(e.id)])
        try db.execute("DELETE FROM entries_fts WHERE rowid=?", [.int(rowID)])
        try db.execute("INSERT INTO entries_fts(rowid,id,body) VALUES(?,?,?)", [.int(rowID), .text(e.id), .text(e.content.searchText)])
        try db.execute("INSERT INTO history(entry_id,action,actor,timestamp,snapshot) VALUES(?,?,?,?,?)",
                       [.text(e.id), .text(action), .text(actor), .double(Date().timeIntervalSince1970), .text(payload)])
    }

    private func saveCollection(_ c: ReadingCollection) throws {
        try db.execute("INSERT INTO collections(id,title,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,payload=excluded.payload",
                       [.text(c.id), .text(c.title), .text(try LibraryJSON.string(c))])
        try db.execute("DELETE FROM collection_entries WHERE collection_id=?", [.text(c.id)])
        for (offset, id) in unique(c.entryIDs).enumerated() {
            try db.execute("INSERT INTO collection_entries(collection_id,entry_id,position) VALUES(?,?,?)", [.text(c.id), .text(id), .int(offset)])
        }
    }

    private func validateTitle(_ title: String, excluding id: String) throws {
        if try db.scalar("SELECT COUNT(*) FROM entries WHERE title_key=? AND id!=? AND deleted_at IS NULL", [.text(titleKey(title)), .text(id)]) > 0 {
            throw LibraryError.invalid("“\(title)”已经在词库里了，可以给原词条补充解释。")
        }
    }
    private func validateRelations(_ ids: [String], selfID: String) throws {
        for id in ids {
            guard id != selfID, try db.scalar("SELECT COUNT(*) FROM entries WHERE id=?", [.text(id)]) > 0 else { throw LibraryError.invalid("无效的关联词条：\(id)") }
        }
    }
    private func titleKey(_ title: String) -> String { title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func unique(_ ids: [String]) -> [String] { var seen = Set<String>(); return ids.filter { seen.insert($0).inserted } }
    private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}
