import Foundation

public enum CollectionOrder: String, Codable, CaseIterable, Sendable {
    case recentlyRead, newest, title
    public var label: String {
        switch self { case .recentlyRead: return "最近阅读"; case .newest: return "最近收录"; case .title: return "名称" }
    }
}

public struct ReadingPosition: Codable, Sendable {
    public var offset: Double = 0
    public var technicalExpanded = false
    public var sourceExpanded = false
    public var updatedAt = Date()
    public init(offset: Double = 0, technicalExpanded: Bool = false, sourceExpanded: Bool = false) {
        self.offset = offset.isFinite ? max(0,offset) : 0
        self.technicalExpanded = technicalExpanded; self.sourceExpanded = sourceExpanded
    }
}

/// UI preferences contain IDs and reading positions only, never dictionary content or file paths.
public struct ReadingWorkspaceState: Codable, Sendable {
    public var section = "all"
    public var selectedEntries: [String:String] = [:]
    public var lastRead: [String:Date] = [:]
    public var positions: [String:[String:ReadingPosition]] = [:]
    public var collectionOrder: CollectionOrder = .recentlyRead
    public init() {}

    public mutating func recordSelection(section: String, entryID: String, at date: Date = Date()) {
        self.section = section; selectedEntries[section] = entryID
        if section.hasPrefix("collection:") { lastRead[String(section.dropFirst("collection:".count))] = date }
    }
    public mutating func recordPosition(section: String, entryID: String, position: ReadingPosition) {
        positions[section,default:[:]][entryID] = position
        // Bound accumulated scroll state independently of library size.
        let all = positions.flatMap { section, values in values.map { (section,$0.key,$0.value.updatedAt) } }
        if all.count > 500 {
            for (section,id,_) in all.sorted(by: { $0.2 < $1.2 }).prefix(all.count-500) { positions[section]?.removeValue(forKey:id) }
        }
    }
    public func collections(_ collections: [ReadingCollection], matching query: String, order: CollectionOrder) -> [ReadingCollection] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        return collections.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.subtitle.localizedStandardContains(query) }.sorted { a,b in
            switch order {
            case .recentlyRead:
                let left=lastRead[a.id] ?? .distantPast, right=lastRead[b.id] ?? .distantPast
                if left != right { return left > right }
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            case .newest: if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            case .title:
                let comparison=a.title.localizedStandardCompare(b.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return a.id < b.id
        }
    }
}

public final class ReadingWorkspacePreferences {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, libraryID: String) {
        self.defaults=defaults; self.key="reading-workspace-v1."+libraryID
    }
    public func load() -> ReadingWorkspaceState {
        guard let data=defaults.data(forKey:key), let state=try? JSONDecoder().decode(ReadingWorkspaceState.self,from:data) else { return ReadingWorkspaceState() }
        return state
    }
    public func save(_ state: ReadingWorkspaceState) {
        if let data=try? JSONEncoder().encode(state) { defaults.set(data,forKey:key) }
    }
}
