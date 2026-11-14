import Foundation

public enum LibraryImport {
    public static func decode(_ data: Data) throws -> ImportBatch {
        if let batch = try? LibraryJSON.decoder().decode(ImportBatch.self, from: data) { return batch }
        if let entries = try? LibraryJSON.decoder().decode([EntryDraft].self, from: data) { return ImportBatch(entries: entries) }
        throw LibraryError.invalid("JSON 应为包含 entries 数组的对象，或词条数组。每个词条至少需要 title 和 summary。")
    }

    public static func parseMarkdown(_ text: String) throws -> ImportBatch {
        let numbered = try NSRegularExpression(pattern: #"^\s*\d+[.、]\s+\*\*(.+?)\*\*\s*$"#)
        let heading = try NSRegularExpression(pattern: #"^#{2,4}\s+(.+)$"#)
        var drafts: [EntryDraft] = [], title = "导入的阅读笔记", category = "未分类"
        var current: EntryDraft?, lines: [String] = []
        let hasNumbered = text.components(separatedBy: .newlines).contains { numbered.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        func finish() {
            guard var entry = current else { return }
            let body = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.trimmingCharacters(in: .whitespaces) != "---" }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let plain = body.replacingOccurrences(of: #"^\s*[-*]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**大白话**：", with: "").replacingOccurrences(of: "**大白话**:", with: "")
                .replacingOccurrences(of: "**", with: "")
            entry.summary = plain.components(separatedBy: .newlines).first ?? ""
            entry.analogy = plain; entry.sourceExcerpt = body; entry.sourceTitle = title
            drafts.append(entry); current = nil; lines = []
        }
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("# ") { title = String(line.dropFirst(2)); continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = numbered.firstMatch(in: line, range: range), let r = Range(match.range(at: 1), in: line) {
                finish(); current = draftFromTitle(String(line[r]), category: category); continue
            }
            if let match = heading.firstMatch(in: line, range: range), let r = Range(match.range(at: 1), in: line) {
                let value = String(line[r])
                if hasNumbered { finish(); category = value }
                else { finish(); current = draftFromTitle(value, category: category) }
                continue
            }
            if current != nil { lines.append(line) }
        }
        finish()
        guard !drafts.isEmpty else { throw LibraryError.invalid("没有找到词条。请使用「## 词名」或「1. **词名**」开头，下一行写解释。") }
        drafts = try drafts.map { try $0.validated() }
        return ImportBatch(entries: drafts, collectionTitle: title)
    }

    private static func draftFromTitle(_ value: String, category: String) -> EntryDraft {
        let clean = value.replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
        let regex = try? NSRegularExpression(pattern: #"^(.+?)[（(]([^）)]+)[）)]$"#)
        if let match = regex?.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let titleRange = Range(match.range(at: 1), in: clean), let englishRange = Range(match.range(at: 2), in: clean) {
            return EntryDraft(title: String(clean[titleRange]).trimmingCharacters(in: .whitespaces), english: String(clean[englishRange]), summary: "", category: category)
        }
        return EntryDraft(title: clean, summary: "", category: category)
    }
}

public enum LibraryExport {
    public static func markdown(_ archive: LibraryArchive) -> String {
        var text = "# 知间概念词典\n\n"
        for entry in archive.entries where entry.deletedAt == nil {
            let c = entry.content
            text += "## \(c.title)" + (c.english.isEmpty ? "" : "（\(c.english)）") + "\n\n\(c.summary)\n\n"
            for (label, value) in [("打个比方", c.analogy), ("再深一层", c.details), ("比喻的边界", c.caveat), ("来自哪里", c.sourceTitle), ("来源链接", c.sourceURL), ("我的理解", c.personalNote)] where !value.isEmpty {
                // Bold labels keep the document round-trippable: only level-two headings introduce entries.
                text += "**\(label)**\n\n\(value)\n\n"
            }
            text += "---\n\n"
        }
        return text
    }
}
