import Foundation
import Darwin

public struct ArchivePreview: Sendable {
    public var count: Int = 0
    public var titles: [String] = []
}

enum ArchiveFileError: Error { case notArchive }

/// Reads the existing JSON archive format one record at a time, including pretty-printed files.
/// Only record bytes and lightweight identity/collection metadata are retained.
enum ArchiveFile {
    static func read(_ url: URL, entry: (Entry) throws -> Void,
                     collection: (ReadingCollection) throws -> Void) throws {
        let reader = try JSONRecordReader(url)
        let decoder = LibraryJSON.decoder()
        guard try reader.peek() == 123 else { throw ArchiveFileError.notArchive }
        try reader.expect(123)
        var keys = Set<String>(), version: Int?
        if try reader.peek() != 125 {
            while true {
                let key = try decoder.decode(String.self, from: reader.value(limit: 4096))
                guard keys.insert(key).inserted else { throw reader.invalid() }
                try reader.expect(58)
                switch key {
                case "entries":
                    try reader.array {
                        try autoreleasepool {
                            let data = try reader.value()
                            let record: Entry
                            do { record = try decoder.decode(Entry.self, from: data) }
                            catch {
                                if version == nil, (try? decoder.decode(EntryDraft.self, from: data)) != nil {
                                    throw ArchiveFileError.notArchive
                                }
                                throw error
                            }
                            try entry(record)
                        }
                    }
                case "collections":
                    try reader.array { try collection(decoder.decode(ReadingCollection.self, from: reader.value(limit: 64_000_000))) }
                case "schemaVersion":
                    version = try decoder.decode(Int.self, from: reader.value())
                    guard version == 1 else { throw LibraryError.invalid("不支持这个备份版本。") }
                case "exportedAt": _ = try decoder.decode(Date.self, from: reader.value())
                default: _ = try JSONSerialization.jsonObject(with: reader.value(), options: [.fragmentsAllowed])
                }
                if try reader.peek() != 44 { break }
                try reader.expect(44)
            }
        }
        try reader.expect(125)
        guard try reader.peek() == nil else { throw reader.invalid() }
        guard version != nil else { throw ArchiveFileError.notArchive }
        guard keys.isSuperset(of: ["entries", "collections", "exportedAt"]) else { throw reader.invalid() }
    }
}

public extension LibraryImport {
    /// A bounded preview for native file selection; nil means ordinary notes JSON/Markdown.
    static func previewArchive(at url: URL) throws -> ArchivePreview? {
        var preview = ArchivePreview()
        do {
            try ArchiveFile.read(url, entry: { entry in
                preview.count += 1
                if preview.titles.count < 8 { preview.titles.append(entry.title) }
            }, collection: { _ in })
            return preview
        } catch ArchiveFileError.notArchive { return nil }
    }
}

private final class JSONRecordReader {
    private let file: FileHandle
    private var buffer = [UInt8]()
    private var offset = 0
    init(_ url: URL) throws { file = try FileHandle(forReadingFrom: url) }
    deinit { try? file.close() }
    func invalid() -> LibraryError { .invalid("备份 JSON 不完整或格式无效。") }
    private func byte() throws -> UInt8? {
        if offset == buffer.count {
            buffer = Array(try file.read(upToCount: 65536) ?? Data()); offset = 0
        }
        return offset < buffer.count ? buffer[offset] : nil
    }
    func peek() throws -> UInt8? {
        while let b = try byte(), b == 32 || b == 10 || b == 13 || b == 9 { offset += 1 }
        return try byte()
    }
    func expect(_ expected: UInt8) throws {
        guard try peek() == expected else { throw invalid() }; offset += 1
    }
    func array(_ record: () throws -> Void) throws {
        try expect(91)
        if try peek() != 93 {
            while true {
                try record()
                if try peek() != 44 { break }
                try expect(44)
            }
        }
        try expect(93)
    }
    func value(limit: Int = 16_000_000) throws -> Data {
        guard let first = try peek() else { throw invalid() }
        var bytes = [UInt8](), stack = [UInt8](), quoted = false, escaped = false
        let compound = first == 123 || first == 91
        let string = first == 34
        while let b = try byte() {
            if !quoted && stack.isEmpty && !bytes.isEmpty {
                if compound || string || b == 44 || b == 125 || b == 93 || b == 32 || b == 10 || b == 13 || b == 9 { break }
            }
            guard bytes.count < limit else { throw LibraryError.invalid("备份中的单条记录过大。") }
            bytes.append(b); offset += 1
            if quoted {
                if escaped { escaped = false }
                else if b == 92 { escaped = true }
                else if b == 34 { quoted = false }
            } else {
                switch b {
                case 34: quoted = true
                case 123: stack.append(125)
                case 91: stack.append(93)
                case 125, 93:
                    guard stack.popLast() == b else { throw invalid() }
                default: break
                }
                guard stack.count <= 128 else { throw invalid() }
            }
        }
        guard !bytes.isEmpty, !quoted, stack.isEmpty else { throw invalid() }
        return Data(bytes)
    }
}

/// Sibling temporary file + atomic rename: a failed export preserves the previous backup.
final class ArchiveWriter {
    private let temporary: URL
    private let destination: URL
    private let file: FileHandle
    init(_ destination: URL) throws {
        self.destination = destination
        temporary = destination.deletingLastPathComponent().appendingPathComponent(".zhijian-" + UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw LibraryError.invalid("无法创建导出文件。")
        }
        file = try FileHandle(forWritingTo: temporary)
    }
    deinit { try? file.close(); try? FileManager.default.removeItem(at: temporary) }
    func write(_ text: String) throws { try file.write(contentsOf: Data(text.utf8)) }
    func finish() throws {
        try file.synchronize(); try file.close()
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
