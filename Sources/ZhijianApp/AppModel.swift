import SwiftUI
import DictionaryCore
import AppKit

enum LibrarySection: Equatable {
    case all, recent, favorites, review, trash, collection(String)
    var storageKey: String {
        switch self { case .all: return "all"; case .recent: return "recent"; case .favorites: return "favorites"; case .review: return "review"; case .trash: return "trash"; case .collection(let id): return "collection:"+id }
    }
    init(storageKey: String) {
        if storageKey.hasPrefix("collection:") { self = .collection(String(storageKey.dropFirst("collection:".count))); return }
        switch storageKey { case "recent": self = .recent; case "favorites": self = .favorites; case "review": self = .review; case "trash": self = .trash; default: self = .all }
    }
    var title: String {
        switch self { case .all: return "我的概念词典"; case .recent: return "最近读过"; case .favorites: return "值得再读"; case .review: return "温故知新"; case .trash: return "废纸篓"; case .collection: return "文章阅读集" }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: LibrarySection = .all {
        didSet { if oldValue != section {
            if section == .review || section == .trash { isReadingMode=false }
            detailTask?.cancel(); detailGeneration += 1
            selectedID=nil; selectedEntry=nil; relatedEntries=[]
            search = ""; masteryFilter = nil; reviewedThisSession = 0
            if ready { readingState.section=section.storageKey; saveReadingState() }
            scheduleSearch()
        } }
    }
    @Published var search = "" { didSet { if oldValue != search { scheduleSearch() } } }
    @Published var masteryFilter: Mastery? { didSet { if oldValue != masteryFilter { scheduleSearch() } } }
    @Published var entries: [EntrySummary] = []
    @Published var total = 0
    @Published var selectedID: String?
    @Published var selectedEntry: Entry?
    @Published var relatedEntries: [Entry] = []
    @Published var collections: [ReadingCollection] = []
    @Published var visibleCollections: [ReadingCollection] = []
    @Published var collectionSearch = "" { didSet { scheduleCollectionSearch() } }
    @Published var collectionOrder: CollectionOrder = .recentlyRead {
        didSet { readingState.collectionOrder=collectionOrder; saveReadingState(); updateVisibleCollections() }
    }
    @Published private(set) var pageOffset = 0
    private var readingState = ReadingWorkspaceState()
    private var readingPreferences: ReadingWorkspacePreferences?
    private var collectionSearchTask: Task<Void,Never>?

    @Published var stats = LibraryStats(entries:0,favorites:0,due:0,understood:0,trash:0,categories:[])
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var ready = false
    @Published var error: String?
    @Published var toast: String?
    @Published var editorPresented = false
    @Published var editingEntry: Entry?
    @Published var importPresented = false
    @Published var agentPresented = false
    @Published var historyPresented = false
    @Published var isReadingMode = false
    @Published var focusSearch = 0
    @Published var reviewedThisSession = 0
    var noteDrafts:[String:(text:String,revision:Int,baseline:String)] = [:]
    private(set) var store: DictionaryStore?
    private var listTask: Task<Void,Never>?
    private var detailTask: Task<Void,Never>?
    private var toastTask: Task<Void,Never>?
    private var generation = 0
    private var detailGeneration = 0
    private var version = 0
    private var bootstrapped = false

    var activeCollection: ReadingCollection? {
        if case .collection(let id) = section { return collections.first { $0.id == id } }; return nil
    }
    var heading: String { activeCollection?.title ?? section.title }
    var hasMore: Bool { pageOffset + entries.count < total }
    var currentPosition: Int? {
        guard let selectedID else { return nil }; return activeCollection?.entryIDs.firstIndex(of: selectedID)
    }

    // Use the collection path only when no filter narrows it; otherwise follow visible results.
    private var navigationIDs: [String] {
        if search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, masteryFilter == nil, let activeCollection {
            return activeCollection.entryIDs
        }
        return entries.map(\.id)
    }
    private var navigationIndex: Int? { selectedID.flatMap { navigationIDs.firstIndex(of:$0) } }
    var canSelectPrevious: Bool {
        guard !isLoading, let index=navigationIndex else { return false }
        return index > 0 || (activeCollection == nil || !search.isEmpty || masteryFilter != nil) && pageOffset > 0
    }
    func loadPreviousPage() {
        guard !isLoading,pageOffset > 0 else { return }
        Task { await loadPage(offset:max(0,pageOffset-60)) }
    }
    var canSelectNext: Bool {
        guard !isLoading, let index=navigationIndex else { return false }
        let usesCollectionPath=activeCollection != nil && search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && masteryFilter == nil
        return index+1 < navigationIDs.count || (!usesCollectionPath && hasMore)
    }
    func selectPrevious() {
        guard canSelectPrevious, let index=navigationIndex else { return }
        if index > 0 {
            let target=navigationIDs[index-1]
            select(target)
            if !entries.contains(where: { $0.id == target }) { Task { await loadPage(preserveSelection:true) } }
        }
        else if pageOffset > 0 {
            let token=generation
            Task {
                await loadPage(offset:max(0,pageOffset-60))
                guard token == generation, let last=entries.last else { return }
                select(last.id)
            }
        }
    }
    func selectNext() {
        guard canSelectNext, let index=navigationIndex else { return }
        let ids=navigationIDs
        if index+1 < ids.count {
            let target=ids[index+1]
            select(target)
            if !entries.contains(where: { $0.id == target }), hasMore {
                Task { await loadPage(append:true) }
            }
            return
        }
        let token=generation, previousID=selectedID
        Task {
            await loadPage(append:true)
            guard token == generation, previousID == selectedID, index+1 < navigationIDs.count else { return }
            select(navigationIDs[index+1])
        }
    }

    func bootstrap() async {
        guard !bootstrapped else { return }; bootstrapped = true
        do {
            let opened = try await Task.detached(priority: .userInitiated) { try DictionaryStore() }.value
            store = opened; version = try await background { try opened.dataVersion() }
            await refreshMetadata()
            let libraryID = try await background { try opened.libraryIdentifier() }
            readingPreferences=ReadingWorkspacePreferences(libraryID:libraryID)
            readingState=readingPreferences!.load()
            collectionOrder=readingState.collectionOrder
            let restored=LibrarySection(storageKey:readingState.section)
            if case .collection(let id)=restored, !collections.contains(where: { $0.id == id }) { section = .all }
            else { section=restored }
            readingState.section=section.storageKey; saveReadingState()
            updateVisibleCollections()
            ready = true; await loadPage()
        } catch { self.error = error.localizedDescription; isLoading = false }
    }

    func pollForExternalChanges() async {
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard NSApplication.shared.isActive, let store else { continue }
            do {
                let current = try await background { try store.dataVersion() }
                if version != current { version = current; await refresh() }
            } catch { self.error = error.localizedDescription }
        }
    }

    func scheduleSearch() {
        guard ready else { return }
        listTask?.cancel(); generation += 1
        let token = generation
        listTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:160_000_000) } catch { return }
            guard let self, token == self.generation else { return }
            await self.loadPage(token: token)
        }
    }

    func loadPage(append: Bool = false, token: Int? = nil, preserveSelection: Bool = false, offset: Int? = nil) async {
        guard let store else { return }
        if append && isLoading { return }
        if let token, token != generation { return }
        let token = generation
        let remembered = search.isEmpty && masteryFilter == nil ? readingState.selectedEntries[section.storageKey] : nil
        let desired = preserveSelection ? selectedID : (offset == nil ? remembered : nil)
        var query = query(); query.offset = offset ?? (append ? pageOffset + entries.count : 0)
        if !append { query.anchorEntryID=desired }
        isLoading = true
        do {
            let selected = desired
            let retainedCount = preserveSelection ? entries.count : 0
            let response = try await background { [query] in
                let page=try store.list(query)
                var summaries=page.entries
                while !append && summaries.count < min(retainedCount,page.total-page.offset) {
                    var next=query; next.anchorEntryID=nil; next.offset=page.offset+summaries.count
                    let more=try store.list(next).entries
                    if more.isEmpty { break }
                    summaries.append(contentsOf:more)
                }
                var matches=false
                if let selected {
                    var exact=query; exact.entryID=selected; exact.offset=0; exact.limit=1
                    matches = try store.list(exact).total > 0
                }
                return (summaries,page.total,matches,page.offset)
            }
            guard token == generation, !Task.isCancelled else { return }
            if append { entries.append(contentsOf:response.0) } else { entries = response.0; pageOffset=response.3 }
            total = response.1; isLoading = false
            if !append {
                if let desired, response.2 || entries.contains(where: { $0.id == desired }) { select(desired) }
                else if let first = entries.first { select(first.id) }
                else { selectedID = nil; selectedEntry = nil; relatedEntries = [] }
            }
        } catch { if token == generation { self.error = error.localizedDescription; isLoading = false } }
    }

    func query() -> LibraryQuery {
        var query = LibraryQuery(text:search); query.mastery = masteryFilter
        switch section {
        case .all: break
        case .recent: query.recentOnly = true
        case .favorites: query.favoritesOnly = true
        case .review: query.dueOnly = true
        case .trash: query.trashOnly = true
        case .collection(let id): query.collectionID = id
        }
        return query
    }

    func select(_ id: String) {
        selectedID = id
        detailTask?.cancel(); detailGeneration += 1
        let token = detailGeneration, context=section.storageKey
        guard let store else { return }
        detailTask = Task { [weak self] in
            do {
                let result = try await self?.background {
                    let entry = try store.entry(id:id)
                    let relations = entry.content.relatedIDs.prefix(30).compactMap { try? store.entry(id:$0) }.filter { $0.deletedAt == nil }
                    try store.markOpened(id:id)
                    return (entry,relations)
                }
                guard let self, token == self.detailGeneration, !Task.isCancelled, let result else { return }
                self.selectedEntry = result.0; self.relatedEntries = result.1
                self.readingState.recordSelection(section:context,entryID:id)
                self.saveReadingState(); self.updateVisibleCollections()
            } catch { if let self, token == self.detailGeneration { self.error = error.localizedDescription } }
        }
    }

    var canToggleReadingMode: Bool {
        isReadingMode || (selectedEntry != nil && selectedEntry?.deletedAt == nil && section != .review)
    }
    func toggleReadingMode() {
        guard canToggleReadingMode else { return }
        isReadingMode.toggle()
    }
    func searchEntries() {
        isReadingMode=false
        DispatchQueue.main.async { self.focusSearch += 1 }
    }

    private func saveReadingState() { readingPreferences?.save(readingState) }
    private func updateVisibleCollections() {
        visibleCollections=readingState.collections(collections,matching:collectionSearch,order:collectionOrder)
    }
    private func scheduleCollectionSearch() {
        collectionSearchTask?.cancel()
        collectionSearchTask=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:160_000_000) } catch { return }
            self?.updateVisibleCollections()
        }
    }
    func readingPosition(entryID: String, sectionKey: String) -> ReadingPosition {
        readingState.positions[sectionKey]?[entryID] ?? ReadingPosition()
    }
    func saveReadingPosition(entryID: String, sectionKey: String, position: ReadingPosition) {
        readingState.recordPosition(section:sectionKey,entryID:entryID,position:position)
        saveReadingState()
    }

    func navigateToRelated(_ id: String) {
        // Keep the article path when the concept belongs to it; otherwise move to the complete dictionary.
        if activeCollection?.entryIDs.contains(id) != true, !entries.contains(where: { $0.id == id }) {
            section = .all
            listTask?.cancel(); generation += 1
            Task { await loadPage(); select(id) }
        } else { select(id) }
    }

    func refresh() async { await refreshMetadata(); generation += 1; await loadPage(preserveSelection:true) }
    func refreshMetadata() async {
        guard let store else { return }
        do {
            let result = try await background { (try store.stats(),try store.collections()) }
            stats = result.0; collections = result.1; updateVisibleCollections()
        } catch { self.error = error.localizedDescription }
    }

    func newEntry() { editingEntry = nil; editorPresented = true }
    func editSelected() { guard let selectedEntry, selectedEntry.deletedAt == nil else { return }; editingEntry = selectedEntry; editorPresented = true }
    func saveDraft(_ draft: EntryDraft, existing: Entry?) async -> Bool {
        let collectionID = activeCollection?.id
        return await mutate { store in
            if let existing { return try store.update(id:existing.id,patch:EntryPatch(content:draft),expectedRevision:existing.revision) }
            return try store.create(draft,collectionID:collectionID)
        }
    }
    func saveNote(_ text: String, entry: Entry, revision: Int) async -> Bool {
        var patch = EntryPatch(); patch.personalNote = text
        return await mutate { [patch] in try $0.update(id:entry.id,patch:patch,expectedRevision:revision) }
    }
    func toggleFavorite() {
        guard let entry = selectedEntry else { return }
        var patch = EntryPatch(); patch.favorite = !entry.favorite
        Task { [patch] in _ = await mutate { try $0.update(id:entry.id,patch:patch,expectedRevision:entry.revision) } }
    }
    func trashSelected() {
        guard let entry = selectedEntry else { return }
        Task { if await mutate({ try $0.trash(id:entry.id,expectedRevision:entry.revision) }) { notify("已移入废纸篓，可随时恢复") } }
    }
    func restoreSelected() {
        guard let entry = selectedEntry else { return }
        Task { if await mutate({ try $0.restore(id:entry.id,expectedRevision:entry.revision) }) { notify("词条已恢复") } }
    }
    func emptyTrash() async {
        guard let store, !isSaving else { return }; isSaving = true
        defer { isSaving = false }
        do {
            detailTask?.cancel(); detailGeneration += 1
            let count = try await background { try store.emptyTrash() }
            if selectedEntry?.deletedAt != nil {
                selectedID = nil; selectedEntry = nil; relatedEntries = []
            }
            await refresh(); notify("已永久删除 \(count) 个词条")
        } catch { self.error = error.localizedDescription }
    }
    func rate(_ entry: Entry, rating: Int) async {
        if await mutate({ try $0.recordReview(id:entry.id,rating:rating,expectedRevision:entry.revision) }) { reviewedThisSession += 1 }
    }
    func revert(_ record: ChangeRecord) async -> Bool {
        guard let selectedEntry else { return false }
        return await mutate { try $0.revert(id:selectedEntry.id,historyID:record.id,expectedRevision:selectedEntry.revision) }
    }
    private func mutate(_ operation: @escaping @Sendable (DictionaryStore) throws -> Entry) async -> Bool {
        guard let store, !isSaving else { return false }; isSaving = true
        defer { isSaving = false }
        do {
            let changed = try await background { try operation(store) }
            selectedEntry = changed; selectedID = changed.id
            await refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func importBatch(_ batch: ImportBatch) async -> Bool {
        guard let store, !isSaving else { return false }; isSaving = true
        defer { isSaving = false }
        do {
            let result = try await background { try store.importBatch(batch) }
            if let collectionID = result.collectionID { section = .collection(collectionID) }
            await refresh(); notify("收录 \(result.created) 个词条，跳过 \(result.skipped) 个已有词条"); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func importArchive(_ archive: LibraryArchive) async -> Bool {
        guard let store, !isSaving else { return false }; isSaving = true
        defer { isSaving = false }
        do {
            let result = try await background { try store.importArchive(archive) }
            await refresh(); notify("恢复 \(result.created) 个词条，保留 \(result.skipped) 个已有词条"); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func importArchiveFile(_ url: URL) async -> Bool {
        guard let store, !isSaving else { return false }; isSaving = true
        defer { isSaving = false }
        do {
            guard let result = try await background({ try store.importArchive(from: url) }) else {
                throw LibraryError.invalid("请选择知间 JSON 备份文件。")
            }
            await refresh(); notify("恢复 \(result.created) 个词条，保留 \(result.skipped) 个已有词条"); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func notify(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { try? await Task.sleep(nanoseconds:3_000_000_000); if !Task.isCancelled { toast = nil } }
    }
    func background<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority:.userInitiated,operation:operation).value
    }
}
