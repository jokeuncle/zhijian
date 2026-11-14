import Foundation

struct SeedContent: Decodable {
    var entries: [EntryDraft]
    var collection: ReadingCollection
    static func load() throws -> SeedContent {
        // Locate resources relative to the actual executable. Never depend on SwiftPM's build-machine fallback.
        let roots = [Bundle.main.resourceURL,
                     Bundle.main.bundleURL,
                     Bundle.main.executableURL?.deletingLastPathComponent(),
                     Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")]
        for root in roots.compactMap({ $0 }) {
            let url=root.appendingPathComponent("Zhijian_DictionaryCore.bundle/seed.json")
            if FileManager.default.fileExists(atPath:url.path) {
                return try LibraryJSON.decoder().decode(SeedContent.self,from:Data(contentsOf:url))
            }
        }
        throw LibraryError.invalid("应用包内的初始学习资料缺失，请重新下载完整应用。")
    }
}
