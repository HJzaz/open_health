import XCTest
import SQLite3
@testable import OuraApp

final class LocalBackupTests: XCTestCase {
    @MainActor func testSnapshotsAreSelfContainedAndRetentionIsBounded() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE sample(value INTEGER); INSERT INTO sample VALUES(42);", nil, nil, nil), SQLITE_OK)
        let store = LocalBackups(folder: dir.appendingPathComponent("snapshots"))
        let now = Date()
        for i in 0..<4 {
            let result = await store.capture(dbPath: source.path, force: true, now: now.addingTimeInterval(Double(i) * 2))
            XCTAssertNotNil(result)
        }
        XCTAssertEqual(store.snapshots.count, 3)
        let copy = try XCTUnwrap(store.snapshots.first?.url)
        XCTAssertEqual(try databaseIntegrity(dbPath: copy.path), "ok")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path + "-wal"))
        let skipped = await store.capture(dbPath: source.path, now: now.addingTimeInterval(100))
        XCTAssertNil(skipped)
        XCTAssertEqual(store.snapshots.count, 3)
    }
    @MainActor func testFailureDoesNotDeleteExistingSnapshotsOrSource() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("oura-snapshot-old.db")
        try Data("kept".utf8).write(to: old)
        let store = LocalBackups(folder: dir)
        let invalid = dir.appendingPathComponent("invalid.db")
        try Data("not a database".utf8).write(to: invalid)
        let result = await store.capture(dbPath: invalid.path, force: true)
        XCTAssertNil(result)
        XCTAssertEqual(try Data(contentsOf: old), Data("kept".utf8))
        XCTAssertEqual(try Data(contentsOf: invalid), Data("not a database".utf8))
        XCTAssertEqual(store.snapshots.count, 1)
    }
}
