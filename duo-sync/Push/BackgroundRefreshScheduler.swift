//
//  BackgroundRefreshScheduler.swift
//  duo-sync
//
//  BGTaskScheduler-based periodic background refresh. iOS gives the
//  app a brief CPU window every ~15-60 minutes to poll Spotify and
//  reload the widget without a user-initiated foreground.
//
//  Required Xcode setup:
//    1) Target → Signing & Capabilities → + Capability → Background Modes
//       → check "Background fetch" AND "Background processing".
//    2) Add this task identifier to Info.plist via Secrets.xcconfig:
//          INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers = kkaay.duo-sync.refresh
//
//  Without those, scheduling fails silently (logged in debug).
//

import BackgroundTasks
import Foundation
import WidgetKit

enum BackgroundRefreshScheduler {
    static let taskIdentifier = "kkaay.duo-sync.refresh"

    /// Call once from `PushAppDelegate.application(_:didFinishLaunching...)`.
    static func register(handler: @escaping (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(refreshTask)
        }
    }

    /// Schedule the next refresh. iOS may run sooner or much later than `interval`.
    static func schedule(after interval: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGRefresh] scheduled next refresh in \(Int(interval))s")
        } catch {
            #if DEBUG
            print("[BGRefresh] not scheduled (capability likely disabled):",
                  error.localizedDescription)
            #endif
        }
    }
}
