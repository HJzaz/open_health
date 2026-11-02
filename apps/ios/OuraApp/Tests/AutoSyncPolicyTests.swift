import XCTest
@testable import OuraApp

final class AutoSyncPolicyTests: XCTestCase {
    func testFailedAttemptsAndBudgetCannotBeBypassedByResumeOrRelaunch() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(AutoSyncPolicy.mayAttempt(lastSuccess: nil, lastAttempt: now.addingTimeInterval(-60), windowStart: now, count: 1, now: now))
        XCTAssertTrue(AutoSyncPolicy.mayAttempt(lastSuccess: nil, lastAttempt: now.addingTimeInterval(-7200), windowStart: now, count: 1, now: now))
        XCTAssertFalse(AutoSyncPolicy.mayAttempt(lastSuccess: nil, lastAttempt: nil, windowStart: now, count: 12, now: now))
        XCTAssertTrue(AutoSyncPolicy.mayAttempt(lastSuccess: nil, lastAttempt: nil, windowStart: now.addingTimeInterval(-86400), count: 12, now: now))
        XCTAssertFalse(AutoSyncPolicy.mayAttempt(lastSuccess: now, lastAttempt: nil, windowStart: nil, count: 0, now: now))
    }
    func testSleepProcessingIsThrottledAndAutomaticNightRequestsAreSkipped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(AutoSyncPolicy.shouldRequestSleep(lastRequest: nil, now: now, hour: 2, manual: false))
        XCTAssertTrue(AutoSyncPolicy.shouldRequestSleep(lastRequest: nil, now: now, hour: 9, manual: false))
        XCTAssertFalse(AutoSyncPolicy.shouldRequestSleep(lastRequest: now.addingTimeInterval(-21599), now: now, hour: 9, manual: true))
        XCTAssertTrue(AutoSyncPolicy.shouldRequestSleep(lastRequest: now.addingTimeInterval(-21600), now: now, hour: 2, manual: true))
    }
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
