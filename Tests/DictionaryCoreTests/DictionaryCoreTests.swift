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
    private func location() -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zhijian-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("library.sqlite").path
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
}

private let suite = DictionaryCoreTests()
let checks: [(String, () throws -> Void)] = [
    ("Persistence and Unicode/escaped search", suite.testPersistenceAndUnicodeSearch),
    ("Concurrent stale revision and note preservation", suite.testStaleRevisionDoesNotOverwriteNewContent),
    ("Trash, restore and persisted review", suite.testTrashRestoreAndReviewSurviveRestart),
    ("Atomic import and ordered collection", suite.testAtomicImportAndStableCollectionOrder),
    ("Invalid relations, names and URLs", suite.testInvalidRelationsAndDuplicateNamesAreRejected),
    ("15-unit seed and backup round trip", suite.testSeedAndArchiveRoundTrip),
    ("User-format Markdown parsing", suite.testMarkdownNumberedNotesImport),
    ("Trash preserves collection order and reused-name backups",suite.testTrashKeepsCollectionPositionAndBackupWithReusedName),
    ("Bounded pagination and external connection invalidation",suite.testPaginationExactFilteringAndExternalChangeVersion)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { fail(error.localizedDescription) }
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
if failures != 0 { exit(1) }
print("All \(checks.count) behavioral checks passed.")
