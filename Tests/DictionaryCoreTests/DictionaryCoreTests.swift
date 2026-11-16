import Foundation
import DictionaryCore

// Self-contained behavioral checks run on CLT-only Macs, where XCTest is not shipped.
private var failures = 0
private func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL \(file):\(line): \(message)")
}
private func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try left(), b = try right(); if a != b { fail("\(a) != \(b)", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected error", file: file, line: line) } catch { }
}
private func XCTAssertGreaterThan<T: Comparable>(_ left: T, _ right: T, file: StaticString = #filePath, line: UInt = #line) { if left <= right { fail("Expected \(left) > \(right)", file: file, line: line) } }
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { fail("Expected nil", file: file, line: line) } }
private class XCTestCase {
    private var cleanup: [() -> Void] = []
    func addTeardownBlock(_ block: @escaping () -> Void) { cleanup.append(block) }
    deinit { cleanup.forEach { $0() } }
}

private final class DictionaryCoreTests: XCTestCase {
    func testStreamingArchiveFiles() throws {
        let path=location(), store=try DictionaryStore(path:path,seed:false)
        let text=String(repeating:"中文 🧠 \\\" { } [ ] \\n\n",count:8000)
        _ = try store.importBatch(ImportBatch(entries:[
            EntryDraft(id:"stream-a",title:"流式甲",summary:"解释",details:text,relatedIDs:["stream-b"]),
            EntryDraft(id:"stream-b",title:"流式乙",summary:"解释",personalNote:"保留笔记")],collectionTitle:"原始顺序"))
        let folder=URL(fileURLWithPath:path).deletingLastPathComponent()
        let file=folder.appendingPathComponent("backup.json")
        try Data("旧备份".utf8).write(to:file)
        XCTAssertEqual(try store.exportArchive(to:file),2)
        let before=try store.exportArchive()
        let decoded=try LibraryJSON.decoder().decode(LibraryArchive.self,from:Data(contentsOf:file))
        XCTAssertEqual(decoded.entries,before.entries)
        let preview=try LibraryImport.previewArchive(at:file)
        XCTAssertEqual(preview?.count,2); XCTAssertEqual(preview?.titles,["流式甲","流式乙"])
        let target=try DictionaryStore(path:location(),seed:false)
        XCTAssertEqual(try target.importArchive(from:file)?.created,2)
        XCTAssertEqual(try target.exportArchive().entries,before.entries)
        XCTAssertEqual(try target.collections()[0].entryIDs,["stream-a","stream-b"])
        // Legacy sorted/pretty JSON puts collections before entries and crosses read buffers.
        try LibraryJSON.encoder(pretty:true).encode(before).write(to:file)
        XCTAssertEqual(try LibraryImport.previewArchive(at:file)?.count,2)
        let legacy=try DictionaryStore(path:location(),seed:false)
        XCTAssertEqual(try legacy.importArchive(from:file)?.created,2)
        XCTAssertEqual(try legacy.exportArchive().entries,before.entries)
        // Reject trailing junk even after all records have been processed; roll back writes.
        var damaged=try Data(contentsOf:file); damaged.append(Data(" garbage".utf8)); try damaged.write(to:file)
        let empty=try DictionaryStore(path:location(),seed:false)
        XCTAssertThrowsError(try empty.importArchive(from:file))
        XCTAssertEqual(try empty.stats().entries,0)
        XCTAssertThrowsError(try LibraryImport.previewArchive(at:file))
        XCTAssertThrowsError(try store.exportArchive(to:URL(fileURLWithPath:path)))
        XCTAssertEqual(try store.stats().entries,2)
        // Ordinary notes continue through the existing import path.
        try Data("{\"entries\":[{\"title\":\"普通笔记\",\"summary\":\"解释\"}]}".utf8).write(to:file)
        XCTAssertNil(try LibraryImport.previewArchive(at:file))
        XCTAssertNil(try empty.importArchive(from:file))
        XCTAssertEqual(try empty.stats().entries,0)
        // An archive's optional metadata may contain nested values without changing parsing.
        let encoded=try LibraryJSON.encoder().encode(before)
        var object=try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
        object["futureMetadata"]=["quoted":"\\\"}],[", "nested":[true,false]] as [String:Any]
        try JSONSerialization.data(withJSONObject:object).write(to:file)
        XCTAssertEqual(try LibraryImport.previewArchive(at:file)?.count,2)
        // Repeated root keys must not permit a partial/ambiguous restore.
        try Data("{\"entries\":[],\"entries\":[],\"schemaVersion\":1,\"collections\":[],\"exportedAt\":\"2026-01-01T00:00:00Z\"}".utf8).write(to:file)
        XCTAssertThrowsError(try empty.importArchive(from:file))
    }
    private func location() -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zhijian-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("library.sqlite").path
    }

    func testReadingStateIsolationSortingAndRestart() throws {
        let suiteName="zhijian-reading-check-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suiteName)!
        defer { defaults.removePersistentDomain(forName:suiteName) }
        let path=location(), store=try DictionaryStore(path:path,seed:false)
        let libraryID=try store.libraryIdentifier()
        XCTAssertEqual(try DictionaryStore(path:path,seed:false).libraryIdentifier(),libraryID)
        let otherID=try DictionaryStore(path:location(),seed:false).libraryIdentifier()
        XCTAssertEqual(libraryID == otherID,false)
        let preferences=ReadingWorkspacePreferences(defaults:defaults,libraryID:libraryID)
        var state=preferences.load()
        state.recordSelection(section:"collection:article-a",entryID:"unit-87",at:Date(timeIntervalSince1970:100))
        state.recordPosition(section:"collection:article-a",entryID:"unit-87",position:ReadingPosition(offset:420,technicalExpanded:true,sourceExpanded:true))
        state.collectionOrder = .title; preferences.save(state)
        let restored=ReadingWorkspacePreferences(defaults:defaults,libraryID:libraryID).load()
        XCTAssertEqual(restored.section,"collection:article-a")
        XCTAssertEqual(restored.selectedEntries["collection:article-a"],"unit-87")
        XCTAssertEqual(restored.positions["collection:article-a"]?["unit-87"]?.offset,420)
        XCTAssertEqual(restored.positions["collection:article-a"]?["unit-87"]?.technicalExpanded,true)
        XCTAssertEqual(restored.collectionOrder,.title)
        XCTAssertEqual(ReadingWorkspacePreferences(defaults:defaults,libraryID:otherID).load().selectedEntries.isEmpty,true)
        let articles=[ReadingCollection(id:"article-a",title:"Alpha 向量",subtitle:"Representation",entryIDs:[],createdAt:Date(timeIntervalSince1970:1)),ReadingCollection(id:"article-b",title:"Beta",entryIDs:[],createdAt:Date(timeIntervalSince1970:2))]
        XCTAssertEqual(restored.collections(articles,matching:"  向量  ",order:.newest).map(\.id),["article-a"])
        XCTAssertEqual(restored.collections(articles,matching:"REPRESENTATION",order:.title).map(\.id),["article-a"])
        XCTAssertEqual(restored.collections(articles,matching:"",order:.recentlyRead).map(\.id),["article-a","article-b"])
        XCTAssertEqual(restored.collections(articles,matching:"",order:.newest).map(\.id),["article-b","article-a"])
        XCTAssertEqual(restored.collections(articles,matching:"",order:.title).map(\.id),["article-a","article-b"])
        XCTAssertEqual(restored.collections(articles,matching:"missing",order:.title).isEmpty,true)
        for i in 0..<510 { state.recordPosition(section:"all",entryID:"unit-\(i)",position:ReadingPosition(offset:Double(i))) }
        XCTAssertEqual(state.positions.values.reduce(0) { $0+$1.count },500)
        defaults.set(Data("invalid json".utf8),forKey:"reading-workspace-v1."+libraryID)
        XCTAssertEqual(preferences.load().section,"all")
    }

    func testAnchoredPaginationRespectsFiltersAndMissingEntries() throws {
        let store=try DictionaryStore(path:location(),seed:false)
        _ = try store.importBatch(ImportBatch(entries:(0..<130).map { EntryDraft(id:"anchor-\($0)",title:String(format:"Unit %03d",$0),summary:"anchor test") },collectionTitle:"Pagination article"))
        var query=LibraryQuery(); query.anchorEntryID="anchor-87"
        let page=try store.list(query)
        XCTAssertEqual(page.offset,60); XCTAssertEqual(page.entries.count,60)
        XCTAssertEqual(page.entries.contains { $0.id == "anchor-87" },true)
        query.collectionID=try store.collections().first!.id
        XCTAssertEqual(try store.list(query).offset,60)
        query.text="Unit 087"
        XCTAssertEqual(try store.list(query).offset,0)
        XCTAssertEqual(try store.list(query).entries.map(\.id),["anchor-87"])
        query.text=""; query.favoritesOnly=true
        XCTAssertEqual(try store.list(query).entries.count,0)
        query.favoritesOnly=false
        _ = try store.trash(id:"anchor-87",expectedRevision:1)
        XCTAssertEqual(try store.list(query).offset,0)
        XCTAssertEqual(try store.list(query).entries.contains { $0.id == "anchor-87" },false)
        query.anchorEntryID="not-found"
        XCTAssertEqual(try store.list(query).offset,0)
    }

    func testPersistenceAndUnicodeSearch() throws {
        let path = location()
        let first = try DictionaryStore(path: path, seed: false)
        let entry = try first.create(EntryDraft(title: "残差流", english: "Residual Stream", aliases: ["主干传送带"], summary: "贯穿模型各层的共享表示"))
        let second = try DictionaryStore(path: path, seed: false)
        XCTAssertEqual(try second.entry(id: entry.id).title, "残差流")
        XCTAssertEqual(try second.list(LibraryQuery(text: "残差")).total, 1)
        XCTAssertEqual(try second.list(LibraryQuery(text: "STREAM")).total, 1)
        XCTAssertEqual(try second.list(LibraryQuery(text: "传送带")).total, 1)
        XCTAssertEqual(try second.list(LibraryQuery(text: "\" OR *")).total, 0)
    }

    func testStaleRevisionDoesNotOverwriteNewContent() throws {
        let path = location(); let a = try DictionaryStore(path: path, seed: false); let b = try DictionaryStore(path: path, seed: false)
        let e = try a.create(EntryDraft(title: "权重", summary: "记忆数字", personalNote: "我的理解"))
        var patch = EntryPatch(); patch.summary = "模型里参与计算的可学习数值"
        let updated = try b.update(id: e.id, patch: patch, expectedRevision: e.revision, actor: "test-agent")
        XCTAssertEqual(updated.content.personalNote, "我的理解")
        XCTAssertThrowsError(try a.update(id: e.id, patch: patch, expectedRevision: e.revision))
        XCTAssertEqual(try a.entry(id: e.id).revision, 2)
        XCTAssertEqual(try a.history(id: e.id).first?.actor, "test-agent")
    }

    func testTrashRestoreAndReviewSurviveRestart() throws {
        let path = location(); let store = try DictionaryStore(path: path, seed: false)
        let e = try store.create(EntryDraft(title: "张量", summary: "多维数字表"))
        let reviewed = try store.recordReview(id: e.id, rating: 2, expectedRevision: e.revision)
        XCTAssertEqual(reviewed.mastery, .understood)
        XCTAssertGreaterThan(reviewed.nextReviewAt, Date().addingTimeInterval(6 * 86400))
        let removed = try store.trash(id: e.id, expectedRevision: reviewed.revision)
        XCTAssertEqual(try store.list(LibraryQuery()).total, 0)
        var q = LibraryQuery(); q.trashOnly = true
        XCTAssertEqual(try store.list(q).total, 1)
        let restarted = try DictionaryStore(path: path, seed: false)
        let restored = try restarted.restore(id: e.id, expectedRevision: removed.revision)
        XCTAssertNil(restored.deletedAt); XCTAssertEqual(restored.mastery, .understood)
    }

    func testAtomicImportAndStableCollectionOrder() throws {
        let store = try DictionaryStore(path: location(), seed: false)
        let invalid = ImportBatch(entries: [EntryDraft(title: "有效", summary: "解释"), EntryDraft(title: "", summary: "错误")])
        XCTAssertThrowsError(try store.importBatch(invalid)); XCTAssertEqual(try store.stats().entries, 0)
        let batch = ImportBatch(entries: [EntryDraft(id: "b", title: "乙", summary: "第二个"), EntryDraft(id: "a", title: "甲", summary: "第一个")], collectionTitle: "阅读路径")
        let result = try store.importBatch(batch)
        var q = LibraryQuery(); q.collectionID = result.collectionID
        XCTAssertEqual(try store.list(q).entries.map(\.id), ["b", "a"])
        XCTAssertEqual(try store.importBatch(batch).skipped, 2)
        XCTAssertEqual(try store.stats().entries, 2)
    }

    func testInvalidRelationsAndDuplicateNamesAreRejected() throws {
        let store = try DictionaryStore(path: location(), seed: false)
        _ = try store.create(EntryDraft(title: "Tensor", summary: "数字表"))
        XCTAssertThrowsError(try store.create(EntryDraft(title: "tensor", summary: "重复")))
        XCTAssertThrowsError(try store.create(EntryDraft(title: "甲", summary: "无效关系", relatedIDs: ["missing"])))
        XCTAssertThrowsError(try store.create(EntryDraft(title: "链接", summary: "解释", sourceURL: "javascript:alert(1)")))
    }

    func testSeedAndArchiveRoundTrip() throws {
        let source = try DictionaryStore(path: location())
        XCTAssertEqual(try source.collections().first?.entryIDs.count, 15)
        let archive = try source.exportArchive()
        let destination = try DictionaryStore(path: location(), seed: false)
        _ = try destination.importArchive(archive)
        XCTAssertEqual(try destination.stats().entries, try source.stats().entries)
        XCTAssertEqual(try destination.collections().first?.entryIDs, archive.collections.first?.entryIDs)
    }

    func testMarkdownNumberedNotesImport() throws {
        let batch = try LibraryImport.parseMarkdown("""
        # 一篇文章
        ### 模型构造
        1. **张量（Tensor）**
        * **大白话**：多维表格。
        2. **残差流（Residual Stream）**
        * **大白话**：主干传送带。
        """)
        XCTAssertEqual(batch.entries.count, 2)
        XCTAssertEqual(batch.entries.first?.summary, "多维表格。")
        XCTAssertEqual(batch.entries.last?.english, "Residual Stream")
    }

    func testTrashKeepsCollectionPositionAndBackupWithReusedName() throws {
        let store=try DictionaryStore(path:location(),seed:false)
        _=try store.importBatch(ImportBatch(entries:[EntryDraft(id:"old",title:"旧词",summary:"解释"),EntryDraft(id:"next",title:"下一个",summary:"解释")],collectionTitle:"路径"))
        let removed=try store.trash(id:"old",expectedRevision:1)
        XCTAssertEqual(try store.collections().first?.entryIDs,["next"])
        _=try store.create(EntryDraft(title:"后来收录",summary:"解释"),collectionID:store.collections().first!.id)
        _=try store.restore(id:"old",expectedRevision:removed.revision)
        XCTAssertEqual(try store.collections().first?.entryIDs.prefix(2).map { $0 },["old","next"])
        _=try store.trash(id:"old",expectedRevision:3)
        _=try store.create(EntryDraft(title:"旧词",summary:"新解释"))
        let destination=try DictionaryStore(path:location(),seed:false)
        _=try destination.importArchive(store.exportArchive())
        XCTAssertEqual(try destination.stats().entries,try store.stats().entries)
        XCTAssertEqual(try destination.stats().trash,1)
    }

    func testPaginationExactFilteringAndExternalChangeVersion() throws {
        let path=location(),a=try DictionaryStore(path:path,seed:false),b=try DictionaryStore(path:path,seed:false)
        let before=try a.dataVersion()
        _=try b.importBatch(ImportBatch(entries:(0..<85).map { EntryDraft(id:"p-\($0)",title:String(format:"分页 %03d",$0),summary:"模型解释") }))
        XCTAssertGreaterThan(try a.dataVersion(),before)
        var query=LibraryQuery(); let first=try a.list(query)
        XCTAssertEqual(first.entries.count,60); XCTAssertEqual(first.total,85)
        query.offset=60; let second=try a.list(query)
        XCTAssertEqual(second.entries.count,25)
        XCTAssertEqual(Set(first.entries.map(\.id)).intersection(second.entries.map(\.id)).count,0)
        query.entryID="p-84"; query.offset=0
        XCTAssertEqual(try a.list(query).total,1)
    }

    func testEmptyTrashCleansRelationsHistoryAndCollections() throws {
        let path = location(), store = try DictionaryStore(path:path, seed:false)
        _ = try store.importBatch(ImportBatch(entries:[
            EntryDraft(id:"remove", title:"删除对象", summary:"专用删除检索词"),
            EntryDraft(id:"keep", title:"保留对象", summary:"保留解释", sourceTitle:"原始来源", personalNote:"个人笔记", relatedIDs:["remove"]),
            EntryDraft(id:"last", title:"路径末项", summary:"末项", relatedIDs:["keep"])
        ], collectionTitle:"保留顺序"))
        // Cross both entry and history page boundaries.
        _ = try store.importBatch(ImportBatch(entries:(0..<205).map {
            EntryDraft(id:"extra-\($0)", title:"保留批次 \($0)", summary:"解释", relatedIDs:["remove"])
        }))
        _ = try store.trash(id:"remove", expectedRevision:1)
        let replacement = try store.create(EntryDraft(title:"删除对象", summary:"同名新条目"))
        let observer = try DictionaryStore(path:path, seed:false), version = try observer.dataVersion()
        XCTAssertEqual(try store.emptyTrash(actor:"check"), 1)
        XCTAssertGreaterThan(try observer.dataVersion(), version)
        XCTAssertEqual(try store.stats().trash, 0)
        XCTAssertEqual(try store.stats().entries, 208)
        XCTAssertThrowsError(try store.entry(id:"remove"))
        XCTAssertThrowsError(try store.restore(id:"remove", expectedRevision:2))
        XCTAssertEqual(try store.history(id:"remove").count, 0)
        var trash = LibraryQuery(text:"专用删除检索词"); trash.trashOnly = true
        XCTAssertEqual(try store.list(trash).total, 0)
        XCTAssertEqual(try store.collections(includeTrash:true).first?.entryIDs, ["keep","last"])
        let kept = try store.entry(id:"keep")
        XCTAssertEqual(kept.content.personalNote, "个人笔记")
        XCTAssertEqual(kept.content.sourceTitle, "原始来源")
        XCTAssertEqual(kept.content.relatedIDs, [])
        XCTAssertEqual(kept.revision, 2)
        XCTAssertEqual(try store.entry(id:"extra-204").content.relatedIDs, [])
        XCTAssertEqual(try store.entry(id:replacement.id).summary, "同名新条目")
        let history = try store.history(id:"keep")
        XCTAssertEqual(history.allSatisfy { $0.snapshot.content.relatedIDs.isEmpty }, true)
        _ = try store.revert(id:"keep", historyID:history.last!.id, expectedRevision:kept.revision)
        let archive = try store.exportArchive()
        XCTAssertEqual(archive.entries.contains { $0.id == "remove" }, false)
        let destination = try DictionaryStore(path:location(), seed:false)
        _ = try destination.importArchive(archive)
        XCTAssertEqual(try destination.stats().entries, 208)
        XCTAssertEqual(try store.emptyTrash(), 0)
    }
}

private let suite = DictionaryCoreTests()
let checks: [(String, () throws -> Void)] = [
    ("Streaming archives, legacy files, buffer boundaries, preview and rollback",suite.testStreamingArchiveFiles),
    ("Portable reading state, restart, sorting and library isolation",suite.testReadingStateIsolationSortingAndRestart),
    ("Anchored pagination respects collection, search, filters and deletion",suite.testAnchoredPaginationRespectsFiltersAndMissingEntries),
    ("Persistence and Unicode/escaped search", suite.testPersistenceAndUnicodeSearch),
    ("Concurrent stale revision and note preservation", suite.testStaleRevisionDoesNotOverwriteNewContent),
    ("Trash, restore and persisted review", suite.testTrashRestoreAndReviewSurviveRestart),
    ("Atomic import and ordered collection", suite.testAtomicImportAndStableCollectionOrder),
    ("Invalid relations, names and URLs", suite.testInvalidRelationsAndDuplicateNamesAreRejected),
    ("15-unit seed and backup round trip", suite.testSeedAndArchiveRoundTrip),
    ("User-format Markdown parsing", suite.testMarkdownNumberedNotesImport),
    ("Trash preserves collection order and reused-name backups",suite.testTrashKeepsCollectionPositionAndBackupWithReusedName),
    ("Bounded pagination and external connection invalidation",suite.testPaginationExactFilteringAndExternalChangeVersion),
    ("Permanent trash cleanup, references, history and archive integrity",suite.testEmptyTrashCleansRelationsHistoryAndCollections)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { fail(error.localizedDescription) }
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
if failures != 0 { exit(1) }
print("All \(checks.count) behavioral checks passed.")
