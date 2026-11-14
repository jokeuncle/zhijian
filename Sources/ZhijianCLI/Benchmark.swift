import Foundation
import DictionaryCore

enum Benchmark {
    static func run(count: Int) throws -> [String:Double] {
        guard (100...100_000).contains(count) else { throw LibraryError.invalid("benchmark count 应为 100–100000。") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zhijian-benchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("library.sqlite").path
        let store = try DictionaryStore(path:path,seed:false)
        let entries = (0..<count).map { i in
            EntryDraft(id:"bench-\(i)",title:"概念 \(i)",english:"Concept \(i)",aliases:["术语 \(i)"],summary:"用大白话理解模型里的第 \(i) 个知识点。",analogy:String(repeating:"像一条传送带，连接新的理解。",count:8),details:String(repeating:"隐状态与权重参与计算，方向投影用于分析。",count:12),category:"分类 \(i % 12)")
        }
        let start = CFAbsoluteTimeGetCurrent(); _ = try store.importBatch(ImportBatch(entries:entries))
        let importMS = (CFAbsoluteTimeGetCurrent()-start)*1000
        func sample(_ body:() throws -> Void) rethrows -> (Double,Double) {
            var values:[Double]=[]
            for _ in 0..<40 { let t=CFAbsoluteTimeGetCurrent(); try body(); values.append((CFAbsoluteTimeGetCurrent()-t)*1000) }
            values.sort(); return (values[values.count/2],values[Int(Double(values.count-1)*0.95)])
        }
        let first = try sample { _ = try store.list() }
        let short = try sample { _ = try store.list(LibraryQuery(text:"隐状")) }
        let long = try sample { _ = try store.list(LibraryQuery(text:"传送带")) }
        let english = try sample { _ = try store.list(LibraryQuery(text:"Concept 932")) }
        let reopened = CFAbsoluteTimeGetCurrent(); let second = try DictionaryStore(path:path,seed:false)
        let openMS = (CFAbsoluteTimeGetCurrent()-reopened)*1000
        _ = try second.list()
        let size = ((try? FileManager.default.attributesOfItem(atPath:path)[.size] as? NSNumber)?.doubleValue ?? 0)
        return ["entry_count":Double(count),"batch_import_ms":importMS,"first_page_median_ms":first.0,"first_page_p95_ms":first.1,
                "short_chinese_median_ms":short.0,"short_chinese_p95_ms":short.1,"indexed_chinese_median_ms":long.0,"indexed_chinese_p95_ms":long.1,
                "english_median_ms":english.0,"english_p95_ms":english.1,"reopen_ms":openMS,"database_mb":size/1_000_000]
    }
}
