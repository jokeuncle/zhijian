import Foundation
import DictionaryCore

final class MCPServer {
    let store: DictionaryStore
    init(store: DictionaryStore) { self.store = store }

    func serve() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            var requestID: Any = NSNull()
            do {
                guard line.utf8.count <= 64_000_000 else { throw LibraryError.invalid("请求超过 64 MB。") }
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
                guard let request = object as? [String: Any], request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
                    respond(["jsonrpc":"2.0", "id":requestID, "error":["code":-32600,"message":"Invalid Request"]]); continue
                }
                // JSON-RPC notifications never receive a reply, including initialized/cancelled.
                guard let id = request["id"] else { continue }; requestID = id
                let params = request["params"] as? [String: Any] ?? [:]
                let result: [String: Any]
                switch method {
                case "initialize":
                    let requested = params["protocolVersion"] as? String ?? "2024-11-05"
                    let supported = ["2024-11-05","2025-03-26","2025-06-18","2025-11-25"]
                    result = ["protocolVersion":supported.contains(requested) ? requested : "2025-11-25",
                              "capabilities":["tools":["listChanged":false]],
                              "serverInfo":["name":"zhijian","title":"知间概念词典","version":"1.0.0"],
                              "instructions":"本地个人概念词典。先搜索避免重名；修改、删除、恢复或复习前读取词条 revision 并传 expected_revision。只更新用户要求的字段，保留 personalNote 和来源。delete_entry 为可恢复删除。批量导入原子执行，重复词名跳过，不覆盖既有内容。collection 保留文章顺序；comparison 不是同义词。"]
                case "ping": result = [:]
                case "tools/list": result = ["tools":Self.tools]
                case "tools/call":
                    do {
                        guard let name = params["name"] as? String else { throw LibraryError.invalid("Missing tool name") }
                        result = try call(name, params["arguments"] as? [String: Any] ?? [:])
                    } catch {
                        result = ["content":[["type":"text","text":error.localizedDescription]],"isError":true]
                    }
                default:
                    respond(["jsonrpc":"2.0","id":id,"error":["code":-32601,"message":"Method not found"]]); continue
                }
                respond(["jsonrpc":"2.0","id":id,"result":result])
            } catch {
                respond(["jsonrpc":"2.0","id":requestID,"error":["code":-32700,"message":error.localizedDescription]])
            }
        }
    }

    private func call(_ name: String, _ a: [String: Any]) throws -> [String: Any] {
        func string(_ key: String) throws -> String {
            guard let value = a[key] as? String else { throw LibraryError.invalid("缺少字符串参数 \(key)") }; return value
        }
        func integer(_ key: String) throws -> Int {
            guard let value = a[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue == Double(value.intValue) else { throw LibraryError.invalid("缺少整数参数 \(key)") }; return value.intValue
        }
        switch name {
        case "search_entries":
            var q = LibraryQuery(text: a["query"] as? String ?? "", limit: a["limit"] as? Int ?? 60)
            q.offset = a["offset"] as? Int ?? 0; q.collectionID = a["collection_id"] as? String; q.category = a["category"] as? String
            q.favoritesOnly = a["favorites_only"] as? Bool ?? false; q.trashOnly = a["trash_only"] as? Bool ?? false
            q.dueOnly = a["due_only"] as? Bool ?? false
            if let status = a["mastery"] as? String { guard let m = Mastery(rawValue: status) else { throw LibraryError.invalid("未知的掌握状态。") }; q.mastery = m }
            return try output(store.list(q))
        case "get_entry": return try output(store.entry(id: string("id")))
        case "create_entry":
            guard let raw = a["entry"] as? [String: Any] else { throw LibraryError.invalid("需要 entry 对象。") }
            let draft = try LibraryJSON.decoder().decode(EntryDraft.self, from: JSONSerialization.data(withJSONObject: raw))
            return try output(store.create(draft, actor: "mcp", collectionID: a["collection_id"] as? String))
        case "update_entry":
            guard let patch = a["patch"] as? [String: Any] else { throw LibraryError.invalid("需要 patch 对象。") }
            let data = try JSONSerialization.data(withJSONObject: patch); try Commands.validatePatch(data)
            return try output(store.update(id: string("id"), patch: LibraryJSON.decoder().decode(EntryPatch.self, from: data), expectedRevision: integer("expected_revision"), actor: "mcp"))
        case "delete_entry": return try output(store.trash(id: string("id"), expectedRevision: integer("expected_revision"), actor: "mcp"))
        case "restore_entry": return try output(store.restore(id: string("id"), expectedRevision: integer("expected_revision"), actor: "mcp"))
        case "empty_trash":
            guard let confirm = a["confirm"] as? NSNumber, CFGetTypeID(confirm) == CFBooleanGetTypeID(), confirm.boolValue else {
                throw LibraryError.invalid("永久清空废纸篓不可恢复，需要用户明确授权并传 confirm: true。")
            }
            return try output(["deleted": store.emptyTrash(actor: "mcp")])
        case "review_entry": return try output(store.recordReview(id: string("id"), rating: integer("rating"), expectedRevision: integer("expected_revision"), actor: "mcp"))
        case "list_collections": return try output(store.collections())
        case "library_stats": return try output(store.stats())
        case "get_history": return try output(store.history(id: string("id")))
        case "revert_entry": return try output(store.revert(id: string("id"), historyID: integer("history_id"), expectedRevision: integer("expected_revision"), actor: "mcp"))
        case "import_entries":
            let batch = try LibraryJSON.decoder().decode(ImportBatch.self, from: JSONSerialization.data(withJSONObject: a))
            return try output(store.importBatch(batch, actor: "mcp"))
        default: throw LibraryError.invalid("未知工具：\(name)")
        }
    }

    private func output<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try LibraryJSON.encoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return ["content":[["type":"text","text":String(decoding:data,as:UTF8.self)]], "structuredContent": object is [String:Any] ? object : ["items":object], "isError":false]
    }
    private func respond(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) {
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        }
    }

    static var entryProperties: [String: Any] {
        let names = ["id","title","english","summary","analogy","details","caveat","category","sourceTitle","sourceURL","sourceExcerpt","personalNote"]
        var props = Dictionary(uniqueKeysWithValues: names.map { ($0,["type":"string"] as [String:Any]) })
        props["aliases"] = ["type":"array","items":["type":"string"]]
        props["relatedIDs"] = ["type":"array","items":["type":"string"]]
        props["kind"] = ["type":"string","enum":["concept","comparison"]]
        return props
    }
    static func schema(_ properties: [String:Any], required: [String] = []) -> [String:Any] {
        ["type":"object","properties":properties,"required":required,"additionalProperties":false]
    }
    static func tool(_ name: String, _ description: String, _ props: [String:Any] = [:], required: [String] = [], read: Bool = false, destructive: Bool = false) -> [String:Any] {
        ["name":name,"description":description,"inputSchema":schema(props,required:required),
         "annotations":["readOnlyHint":read,"destructiveHint":destructive,"openWorldHint":false]]
    }
    static var tools: [[String:Any]] {
        let text: [String:Any] = ["type":"string"], number: [String:Any] = ["type":"integer"]
        let identity: [String:Any] = ["id":text,"expected_revision":number]
        var patch = entryProperties; patch.removeValue(forKey:"id"); patch["favorite"] = ["type":"boolean"]
        return [
            tool("search_entries","搜索中文、英文、别名和解释；支持阅读集、收藏、复习和废纸篓过滤，分页返回摘要。",["query":text,"collection_id":text,"category":text,"mastery":["type":"string","enum":["new","learning","understood"]],"limit":["type":"integer","minimum":1,"maximum":200],"offset":["type":"integer","minimum":0],"favorites_only":["type":"boolean"],"trash_only":["type":"boolean"],"due_only":["type":"boolean"]],read:true),
            tool("get_entry","读取完整词条与当前 revision。",["id":text],required:["id"],read:true),
            tool("create_entry","新增词条，拒绝重复词名；可加入指定阅读集。",["entry":schema(entryProperties,required:["title","summary"]),"collection_id":text],required:["entry"]),
            tool("update_entry","仅修改 patch 中的字段；expected_revision 防止覆盖并发更新。",identity.merging(["patch":schema(patch)]) { _,new in new },required:["id","expected_revision","patch"]),
            tool("delete_entry","将词条移入可恢复的废纸篓。",identity,required:["id","expected_revision"]),
            tool("restore_entry","从废纸篓恢复词条。",identity,required:["id","expected_revision"]),
            tool("empty_trash","永久清空全部废纸篓词条及其历史，清理关联引用。不可恢复；仅在用户明确要求永久清空时调用。",["confirm":["type":"boolean","const":true]],required:["confirm"],destructive:true),
            tool("review_entry","记录复习：0 还没懂、1 有点模糊、2 能讲明白。",identity.merging(["rating":["type":"integer","enum":[0,1,2]]]) { _,new in new },required:["id","expected_revision","rating"]),
            tool("list_collections","读取文章学习路径与有序 entryIDs。",read:true),
            tool("get_history","读取词条最近 50 次改动及快照。",["id":text],required:["id"],read:true),
            tool("revert_entry","将内容恢复为指定历史快照，保留当前学习进度。",identity.merging(["history_id":number]) { _,new in new },required:["id","expected_revision","history_id"]),
            tool("import_entries","批量导入词条，可创建文章阅读集；原子执行，已有词名跳过，保留文章顺序。",["entries":["type":"array","items":schema(entryProperties,required:["title","summary"])],"collectionTitle":text,"collectionSubtitle":text],required:["entries"]),
            tool("library_stats","读取词条、收藏、待复习、掌握和废纸篓数量。",read:true)
        ]
    }
}
