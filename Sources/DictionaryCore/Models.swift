import Foundation

public enum Mastery: String, Codable, CaseIterable, Sendable {
    case new, learning, understood
    public var label: String {
        switch self { case .new: return "还没学过"; case .learning: return "正在理解"; case .understood: return "能讲明白" }
    }
}

public enum EntryKind: String, Codable, Sendable { case concept, comparison }

public struct EntryDraft: Codable, Equatable, Sendable {
    public var id: String?
    public var title: String
    public var english: String
    public var aliases: [String]
    public var summary: String
    public var analogy: String
    public var details: String
    public var caveat: String
    public var category: String
    public var kind: EntryKind
    public var sourceTitle: String
    public var sourceURL: String
    public var sourceExcerpt: String
    public var personalNote: String
    public var relatedIDs: [String]

    public init(id: String? = nil, title: String, english: String = "", aliases: [String] = [], summary: String,
                analogy: String = "", details: String = "", caveat: String = "", category: String = "未分类",
                kind: EntryKind = .concept, sourceTitle: String = "", sourceURL: String = "", sourceExcerpt: String = "",
                personalNote: String = "", relatedIDs: [String] = []) {
        self.id = id; self.title = title; self.english = english; self.aliases = aliases; self.summary = summary
        self.analogy = analogy; self.details = details; self.caveat = caveat; self.category = category; self.kind = kind
        self.sourceTitle = sourceTitle; self.sourceURL = sourceURL; self.sourceExcerpt = sourceExcerpt
        self.personalNote = personalNote; self.relatedIDs = relatedIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, title, english, aliases, summary, analogy, details, caveat, category, kind
        case sourceTitle, sourceURL, sourceExcerpt, personalNote, relatedIDs
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        english = try c.decodeIfPresent(String.self, forKey: .english) ?? ""
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        analogy = try c.decodeIfPresent(String.self, forKey: .analogy) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        caveat = try c.decodeIfPresent(String.self, forKey: .caveat) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "未分类"
        kind = try c.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .concept
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle) ?? ""
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        sourceExcerpt = try c.decodeIfPresent(String.self, forKey: .sourceExcerpt) ?? ""
        personalNote = try c.decodeIfPresent(String.self, forKey: .personalNote) ?? ""
        relatedIDs = try c.decodeIfPresent([String].self, forKey: .relatedIDs) ?? []
    }

    public var searchText: String {
        ([title, english, summary, analogy, details, caveat, category, sourceTitle, sourceExcerpt, personalNote] + aliases).joined(separator: "\n")
    }

    public func validated() throws -> EntryDraft {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.category.isEmpty { copy.category = "未分类" }
        guard !copy.title.isEmpty, copy.title.count <= 200 else { throw LibraryError.invalid("词名不能为空，且不能超过 200 个字符。") }
        guard !copy.summary.isEmpty else { throw LibraryError.invalid("请写下一句话解释。") }
        guard searchText.utf8.count <= 1_000_000 else { throw LibraryError.invalid("单个词条内容不能超过 1 MB。") }
        if let id, id.isEmpty || id.count > 200 { throw LibraryError.invalid("词条 ID 无效。") }
        if !sourceURL.isEmpty {
            guard let url = URL(string: sourceURL), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw LibraryError.invalid("来源链接需要是完整的 http 或 https 地址。")
            }
        }
        copy.aliases = Array(NSOrderedSet(array: aliases.compactMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines); return clean.isEmpty ? nil : clean
        })) as? [String] ?? []
        copy.relatedIDs = Array(Set(relatedIDs)).sorted()
        return copy
    }
}

public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var revision: Int
    public var content: EntryDraft
    public var mastery: Mastery
    public var favorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date?
    public var deletedAt: Date?
    public var nextReviewAt: Date
    public var reviewCount: Int
    public var title: String { content.title }
    public var summary: String { content.summary }
}

public struct EntryPatch: Codable, Sendable {
    public var title: String?, english: String?, summary: String?, analogy: String?, details: String?, caveat: String?
    public var category: String?, sourceTitle: String?, sourceURL: String?, sourceExcerpt: String?, personalNote: String?
    public var aliases: [String]?, relatedIDs: [String]?
    public var kind: EntryKind?
    public var favorite: Bool?
    public init() {}
    public init(content: EntryDraft) {
        title = content.title; english = content.english; summary = content.summary; analogy = content.analogy
        details = content.details; caveat = content.caveat; category = content.category; kind = content.kind
        sourceTitle = content.sourceTitle; sourceURL = content.sourceURL; sourceExcerpt = content.sourceExcerpt
        personalNote = content.personalNote; aliases = content.aliases; relatedIDs = content.relatedIDs
    }
    public func applying(to entry: Entry) -> Entry {
        var e = entry
        if let title { e.content.title = title }; if let english { e.content.english = english }
        if let summary { e.content.summary = summary }; if let analogy { e.content.analogy = analogy }
        if let details { e.content.details = details }; if let caveat { e.content.caveat = caveat }
        if let category { e.content.category = category }; if let aliases { e.content.aliases = aliases }
        if let sourceTitle { e.content.sourceTitle = sourceTitle }; if let sourceURL { e.content.sourceURL = sourceURL }
        if let sourceExcerpt { e.content.sourceExcerpt = sourceExcerpt }; if let personalNote { e.content.personalNote = personalNote }
        if let relatedIDs { e.content.relatedIDs = relatedIDs }; if let kind { e.content.kind = kind }
        if let favorite { e.favorite = favorite }
        return e
    }
}

public struct EntrySummary: Codable, Identifiable, Equatable, Sendable {
    public var id: String, title: String, english: String, summary: String, category: String
    public var kind: EntryKind, mastery: Mastery
    public var favorite: Bool
    public var position: Int?
}

public struct LibraryQuery: Sendable {
    public var text = ""
    public var collectionID: String?
    public var entryID: String?
    public var anchorEntryID: String?
    public var category: String?
    public var mastery: Mastery?
    public var favoritesOnly = false
    public var trashOnly = false
    public var dueOnly = false
    public var recentOnly = false
    public var limit = 60
    public var offset = 0
    public init(text: String = "", limit: Int = 60) { self.text = text; self.limit = limit }
}

public struct EntryPage: Codable, Sendable {
    public var entries: [EntrySummary]
    public var total: Int
    public var offset: Int
    public var hasMore: Bool { offset + entries.count < total }
}

public struct ReadingCollection: Codable, Identifiable, Sendable {
    public var id: String, title: String, subtitle: String
    public var entryIDs: [String]
    public var createdAt: Date
    public init(id: String = UUID().uuidString.lowercased(), title: String, subtitle: String = "", entryIDs: [String], createdAt: Date = Date()) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.entryIDs = entryIDs; self.createdAt = createdAt
    }
}

public struct LibraryStats: Codable, Sendable {
    public var entries: Int, favorites: Int, due: Int, understood: Int, trash: Int
    public var categories: [String]
    public init(entries:Int,favorites:Int,due:Int,understood:Int,trash:Int,categories:[String]) {
        self.entries=entries; self.favorites=favorites; self.due=due; self.understood=understood; self.trash=trash; self.categories=categories
    }
}

public struct ChangeRecord: Codable, Identifiable, Sendable {
    public var id: Int
    public var entryID: String, action: String, actor: String
    public var timestamp: Date
    public var snapshot: Entry
}

public struct ImportBatch: Codable, Sendable {
    public var entries: [EntryDraft]
    public var collectionTitle: String?
    public var collectionSubtitle: String?
    public init(entries: [EntryDraft], collectionTitle: String? = nil, collectionSubtitle: String? = nil) {
        self.entries = entries; self.collectionTitle = collectionTitle; self.collectionSubtitle = collectionSubtitle
    }
}

public struct ImportResult: Codable, Sendable { public var created: Int, skipped: Int; public var collectionID: String? }

public struct LibraryArchive: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var exportedAt: Date = Date()
    public var entries: [Entry]
    public var collections: [ReadingCollection]
}

public enum LibraryError: Error, LocalizedError {
    case invalid(String), database(String), notFound(String), conflict
    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .database(let message): return message
        case .notFound(let id): return "找不到词条：\(id)"
        case .conflict: return "词条已在其他窗口或 Agent 中被修改。请刷新后重试，避免覆盖新内容。"
        }
    }
}

public enum LibraryJSON {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    public static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
    public static func string<T: Encodable>(_ value: T, pretty: Bool = false) throws -> String {
        String(decoding: try encoder(pretty: pretty).encode(value), as: UTF8.self)
    }
}
