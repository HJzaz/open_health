import XCTest
@testable import OuraApp

final class AutoSyncPolicyTests: XCTestCase {
    func testTwoHourBoundaryAndFirstSync() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AutoSyncPolicy.isDue(lastSuccess: nil, now: now))
        XCTAssertFalse(AutoSyncPolicy.isDue(lastSuccess: now.addingTimeInterval(-7199), now: now))
        XCTAssertTrue(AutoSyncPolicy.isDue(lastSuccess: now.addingTimeInterval(-7200), now: now))
        XCTAssertFalse(AutoSyncPolicy.isDue(lastSuccess: now.addingTimeInterval(10), now: now))
    }
    func testBackgroundDateAvoidsImmediateRetryLoop() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AutoSyncPolicy.nextDate(lastSuccess: now, now: now), now.addingTimeInterval(7200))
        XCTAssertEqual(AutoSyncPolicy.nextDate(lastSuccess: now.addingTimeInterval(-9000), now: now), now.addingTimeInterval(60))
    }
}
