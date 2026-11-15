import Foundation
import DictionaryCore

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags = Set<String>()
    init(_ arguments: [String]) throws {
        let booleans: Set<String> = ["trash", "favorites", "due", "recent", "no-seed", "help", "yes"]
        let valueOptions: Set<String> = ["database", "json", "query", "collection", "category", "status", "limit", "offset", "revision", "rating", "actor", "count", "collection-title"]
        var index = 0
        while index < arguments.count {
            let value = arguments[index]
            if value == "-h" { flags.insert("help") }
            else if value.hasPrefix("--") {
                let name = String(value.dropFirst(2))
                if booleans.contains(name) { flags.insert(name) }
                else {
                    guard valueOptions.contains(name), index + 1 < arguments.count else { throw LibraryError.invalid("未知选项或缺少值：\(value)") }
                    index += 1; options[name] = arguments[index]
                }
            } else { positional.append(value) }
            index += 1
        }
    }
    func required(_ index: Int, name: String) throws -> String {
        guard positional.indices.contains(index) else { throw LibraryError.invalid("缺少\(name)，运行 zhijian help 查看用法。") }
        return positional[index]
    }
    func integer(_ name: String, default fallback: Int? = nil) throws -> Int {
        if let value = options[name], let int = Int(value) { return int }
        if options[name] == nil, let fallback { return fallback }
        throw LibraryError.invalid("--\(name) 需要整数值。")
    }
}

enum Commands {
    static let help = """
    知间 · 本地概念词典

    zhijian list [--query 文本] [--collection ID] [--limit 60] [--offset 0]
                 [--category 分类] [--status new|learning|understood] [--favorites] [--due] [--trash]
    zhijian get ID
    zhijian create --json 文件或- [--collection ID]
    zhijian update ID --revision N --json 文件或-
    zhijian delete|restore ID --revision N
    zhijian empty-trash --yes  （永久清空废纸篓及其历史，不可恢复）
    zhijian review ID --revision N --rating 0|1|2
    zhijian history ID
    zhijian revert ID HISTORY_ID --revision N
    zhijian collections|stats
    zhijian import 文件.json或.md [--collection-title 名称]
    zhijian export 输出.json或.md
    zhijian mcp
    zhijian benchmark [--count 10000]

    通用选项：--database 路径，--no-seed，--actor 来源
    也可设置 ZHIJIAN_DATABASE。默认词库：\(DictionaryStore.defaultPath)
    输出为 JSON；--json - 从 stdin 读取。删除进入废纸篓，更新需要当前 revision。
    """

    static func run(_ raw: [String]) throws {
        let a = try Arguments(raw)
        let command = a.positional.first ?? "help"
        if command == "help" || a.flags.contains("help") { print(help); return }
        if command == "benchmark" { try emit(Benchmark.run(count: a.integer("count", default: 10_000))); return }
        let store = try DictionaryStore(path: a.options["database"].map { NSString(string: $0).expandingTildeInPath } ?? DictionaryStore.defaultPath, seed: !a.flags.contains("no-seed"))
        let actor = a.options["actor"] ?? "cli"
        switch command {
        case "mcp": MCPServer(store: store).serve()
        case "list", "search":
            var q = LibraryQuery(text: a.options["query"] ?? "", limit: try a.integer("limit", default: 60))
            q.collectionID = a.options["collection"]; q.category = a.options["category"]
            q.offset = try a.integer("offset", default: 0); q.favoritesOnly = a.flags.contains("favorites")
            q.trashOnly = a.flags.contains("trash"); q.dueOnly = a.flags.contains("due"); q.recentOnly = a.flags.contains("recent")
            if let value = a.options["status"] { guard let mastery = Mastery(rawValue: value) else { throw LibraryError.invalid("status 应为 new、learning 或 understood。") }; q.mastery = mastery }
            try emit(store.list(q))
        case "get": try emit(store.entry(id: a.required(1, name: "词条 ID")))
        case "create":
            let draft = try LibraryJSON.decoder().decode(EntryDraft.self, from: inputJSON(a))
            try emit(store.create(draft, actor: actor, collectionID: a.options["collection"]))
        case "update":
            let data = try inputJSON(a); try validatePatch(data)
            try emit(store.update(id: a.required(1, name: "词条 ID"), patch: LibraryJSON.decoder().decode(EntryPatch.self, from: data), expectedRevision: a.integer("revision"), actor: actor))
        case "delete": try emit(store.trash(id: a.required(1, name: "词条 ID"), expectedRevision: a.integer("revision"), actor: actor))
        case "restore": try emit(store.restore(id: a.required(1, name: "词条 ID"), expectedRevision: a.integer("revision"), actor: actor))
        case "empty-trash":
            guard a.flags.contains("yes") else { throw LibraryError.invalid("清空废纸篓不可恢复；确认永久删除全部废纸篓词条后，请加 --yes。") }
            try emit(["deleted": store.emptyTrash(actor: actor)])
        case "review": try emit(store.recordReview(id: a.required(1, name: "词条 ID"), rating: a.integer("rating"), expectedRevision: a.integer("revision"), actor: actor))
        case "history": try emit(store.history(id: a.required(1, name: "词条 ID")))
        case "revert":
            guard let historyID = Int(try a.required(2, name: "历史记录 ID")) else { throw LibraryError.invalid("历史记录 ID 应为整数。") }
            try emit(store.revert(id: a.required(1, name: "词条 ID"), historyID: historyID, expectedRevision: a.integer("revision"), actor: actor))
        case "collections": try emit(store.collections())
        case "stats": try emit(store.stats())
        case "import":
            let path = try a.required(1, name: "文件路径")
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let archive = try? LibraryJSON.decoder().decode(LibraryArchive.self, from: data) { try emit(store.importArchive(archive, actor: actor)) }
            else {
                var batch = path.lowercased().hasSuffix(".md") ? try LibraryImport.parseMarkdown(String(decoding: data, as: UTF8.self)) : try LibraryImport.decode(data)
                if let title = a.options["collection-title"] { batch.collectionTitle = title }
                try emit(store.importBatch(batch, actor: actor))
            }
        case "export":
            let path = try a.required(1, name: "输出路径"), url = URL(fileURLWithPath: try a.required(1, name: "输出路径"))
            let archive = try store.exportArchive()
            let data = path.lowercased().hasSuffix(".md") ? Data(LibraryExport.markdown(archive).utf8) : try LibraryJSON.encoder(pretty: true).encode(archive)
            try data.write(to: url, options: .atomic); try emit(["path": url.path, "entries": String(archive.entries.count)])
        default: throw LibraryError.invalid("未知命令：\(command)。运行 zhijian help 查看用法。")
        }
    }

    static func emit<T: Encodable>(_ value: T) throws { print(try LibraryJSON.string(value, pretty: true)) }
    private static func inputJSON(_ a: Arguments) throws -> Data {
        guard let path = a.options["json"] else { throw LibraryError.invalid("需要 --json 文件路径，或 --json - 从 stdin 读取。") }
        let data = path == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.count <= 64_000_000 else { throw LibraryError.invalid("输入超过 64 MB，请拆分导入。") }
        return data
    }
    static func validatePatch(_ data: Data) throws {
        let allowed: Set<String> = ["title","english","summary","analogy","details","caveat","category","sourceTitle","sourceURL","sourceExcerpt","personalNote","aliases","relatedIDs","kind","favorite"]
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], !object.isEmpty else { throw LibraryError.invalid("更新内容应为非空 JSON 对象。") }
        let unknown = Set(object.keys).subtracting(allowed)
        guard unknown.isEmpty, object.values.allSatisfy({ !($0 is NSNull) }) else { throw LibraryError.invalid("存在未知或空值字段：\(unknown.sorted().joined(separator: ", "))。清空文字请传空字符串。") }
    }
}
