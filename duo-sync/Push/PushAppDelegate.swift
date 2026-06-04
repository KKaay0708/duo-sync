//
//  PushAppDelegate.swift
//  duo-sync
//
//  Bridges UIApplicationDelegate APIs that SwiftUI doesn't expose:
//  capturing APNs device tokens for silent push (paid account), and
//  running BGAppRefreshTask handlers for periodic background warm-up.
//

import BackgroundTasks
import UIKit
import WidgetKit

final class PushAppDelegate: NSObject, UIApplicationDelegate {

    weak var nowPlaying: NowPlayingService?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // APNs registration. Paid account: token reaches the backend
        // via /me/device-token and the poll worker can dispatch silent
        // push. Free account: registration silently fails — harmless.
        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }

        // Background refresh fallback for when the Realtime WebSocket
        // and main-app polling can't keep up (i.e. both apps closed).
        BackgroundRefreshScheduler.register { [weak self] task in
            self?.handleBackgroundRefresh(task: task)
        }
        BackgroundRefreshScheduler.schedule()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // iOS clears pending BGTasks on launch — re-queue on each
        // background.
        BackgroundRefreshScheduler.schedule()
    }

    // MARK: - APNs token capture

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Push] APNs device token captured (len=\(hex.count))")
        Task {
            do {
                try await BackendClient.shared.registerDeviceToken(hex)
                print("[Push] device token registered with backend")
            } catch {
                print("[Push] failed to register device token:", error.localizedDescription)
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] APNs registration failed:", error.localizedDescription)
    }

    // MARK: - Silent push handler

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[Push] silent push received:", userInfo)
        guard let nowPlaying = nowPlaying else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await nowPlaying.refreshNow()
            WidgetCenter.shared.reloadAllTimelines()
            completionHandler(.newData)
        }
    }

    // MARK: - Background refresh handler

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        BackgroundRefreshScheduler.schedule()
        let work = Task { @MainActor in
            await nowPlaying?.refreshNow()
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
