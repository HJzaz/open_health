import BackgroundTasks
import UIKit

/// A due date is a scheduling hint; iOS decides background execution times.
enum AutoSyncPolicy {
    static let interval: TimeInterval = 2 * 60 * 60
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "ring.auto-sync.enabled") as? Bool ?? true
    }
    static func isDue(lastSuccess: Date?, now: Date = Date()) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }
    static let lastAttemptKey = "ring.auto-sync.last-attempt"
    static let windowKey = "ring.auto-sync.window"
    static let countKey = "ring.auto-sync.count"
    static let maximumAttempts = 12
    static func mayAttempt(lastSuccess: Date?, lastAttempt: Date?, windowStart: Date?, count: Int, now: Date) -> Bool {
        guard isDue(lastSuccess: lastSuccess, now: now) else { return false }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < interval { return false }
        if let windowStart, now.timeIntervalSince(windowStart) < 86400, count >= maximumAttempts { return false }
        return true
    }
    static func shouldRequestSleep(lastRequest: Date?, now: Date, hour: Int, manual: Bool) -> Bool {
        guard manual || (6..<18).contains(hour) else { return false }
        return lastRequest.map { now.timeIntervalSince($0) >= 6 * 3600 } ?? true
    }
    static func nextDate(lastSuccess: Date?, now: Date = Date()) -> Date {
        max(now.addingTimeInterval(60), (lastSuccess ?? now).addingTimeInterval(interval))
    }
}

@MainActor
enum BackgroundRingSync {
    static let identifier = "org.hatemaljandali.openhealth.ring-refresh"

    private static func logInstalledConfiguration() {
        let bundle = Bundle.main
        let modes = bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let permitted = bundle.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        dlog("schedule-config", "bundle=\(bundle.bundleIdentifier ?? "missing") task=\(identifier) modes=\(modes.joined(separator: ",")) permitted=\(permitted.joined(separator: ",")) taskPermitted=\(permitted.contains(identifier)) fetchMode=\(modes.contains("fetch")) refreshStatus=\(UIApplication.shared.backgroundRefreshStatus.rawValue)")
    }

    static func register() {
        logInstalledConfiguration()
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in await execute(task) }
        }
        dlog("schedule", "background task registration accepted=\(registered)")
    }

    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard AutoSyncPolicy.enabled,
              UserDefaults.standard.string(forKey: "ring.serial") != nil else { return }
        let timestamp = UserDefaults.standard.double(forKey: "ring.last-successful-sync-at")
        let last = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        var due = AutoSyncPolicy.nextDate(lastSuccess: last)
        let defaults = UserDefaults.standard
        let attempted = defaults.double(forKey: AutoSyncPolicy.lastAttemptKey)
        if attempted > 0 { due = max(due, Date(timeIntervalSince1970: attempted).addingTimeInterval(AutoSyncPolicy.interval)) }
        let window = defaults.double(forKey: AutoSyncPolicy.windowKey)
        if window > 0, defaults.integer(forKey: AutoSyncPolicy.countKey) >= AutoSyncPolicy.maximumAttempts {
            due = max(due, Date(timeIntervalSince1970: window).addingTimeInterval(86400))
        }
        request.earliestBeginDate = due
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Inspect the installed (possibly re-signed) plist rather than
            // assuming the source configuration reached the phone unchanged.
            logInstalledConfiguration()
            dlog("schedule", "background refresh unavailable domain=\((error as NSError).domain) code=\((error as NSError).code) description=\(error.localizedDescription)")
        }
    }

    private static func execute(_ task: BGTask) async {
        let ring = RingSync()
        var completed = false
        func complete(_ success: Bool) {
            guard !completed else { return }
            completed = true
            WorkCoordinator.shared.backgroundSyncAllowed = false
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            Task { @MainActor in
                ring.pause()
                complete(false)
            }
        }
        defer { schedule() }
        guard AutoSyncPolicy.enabled, UIApplication.shared.isProtectedDataAvailable else {
            complete(false)
            return
        }
        WorkCoordinator.shared.backgroundSyncAllowed = true
        let result = await ring.syncAutomaticallyIfNeeded(background: true)
        complete(result != nil)
    }
}
