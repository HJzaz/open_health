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
    static func nextDate(lastSuccess: Date?, now: Date = Date()) -> Date {
        max(now.addingTimeInterval(60), (lastSuccess ?? now).addingTimeInterval(interval))
    }
}

@MainActor
enum BackgroundRingSync {
    static let identifier = "org.hatemaljandali.openhealth.ring-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in await execute(task) }
        }
    }

    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard AutoSyncPolicy.enabled,
              UserDefaults.standard.string(forKey: "ring.serial") != nil else { return }
        let timestamp = UserDefaults.standard.double(forKey: "ring.last-successful-sync-at")
        let last = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = AutoSyncPolicy.nextDate(lastSuccess: last)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh can be disabled by the user or system. Manual and
            // foreground sync continue; never claim a request is guaranteed to run.
            dlog("schedule", "background refresh unavailable")
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
