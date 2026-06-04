//
//  LiveActivityManager.swift
//  duo-sync
//
//  Starts / updates / ends the now-playing Live Activity.
//
//  Lifecycle:
//    - Started when the user signs in (or first time a snapshot arrives).
//    - Updated on every NowPlayingService poll that yields a new snapshot.
//    - Ended on sign-out.
//
//  Live Activities are exempt from WidgetKit's refresh budget, so each
//  `Activity.update(...)` renders the lock-screen + Dynamic Island
//  views immediately — no throttling.
//
 
import ActivityKit
import Foundation
import Combine

@MainActor
final class LiveActivityManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    static let shared = LiveActivityManager()

    @Published private(set) var isActive = false

    private var activity: Activity<NowPlayingActivityAttributes>?

    private init() {
        // Re-attach to an already-running activity if the app was
        // re-launched (e.g. after a crash or 7-day cert refresh).
        if let existing = Activity<NowPlayingActivityAttributes>.activities.first {
            self.activity = existing
            self.isActive = true
            print("[LiveActivity] re-attached to existing activity \(existing.id)")
        }
    }

    // MARK: - Public API

    /// Begin a new activity for the given watched user. No-op if one is
    /// already running.
    func start(watchedName: String, watchedUserID: String, snapshot: NowPlayingSnapshot?) {
        guard isEnabledOnDevice else {
            print("[LiveActivity] Live Activities not enabled on device")
            return
        }
        if activity != nil { return }

        let attrs = NowPlayingActivityAttributes(
            watchedName: watchedName,
            watchedUserID: watchedUserID
        )
        let state: NowPlayingActivityAttributes.ContentState =
            snapshot.map(NowPlayingActivityAttributes.ContentState.init(from:))
            ?? .placeholder

        do {
            let activity = try Activity<NowPlayingActivityAttributes>.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil)
            )
            self.activity = activity
            self.isActive = true
            print("[LiveActivity] started activity \(activity.id)")
        } catch {
            print("[LiveActivity] start failed:", error.localizedDescription)
        }
    }

    /// Push a new snapshot into the running activity. Cheap; safe to
    /// call on every poll.
    func update(snapshot: NowPlayingSnapshot) {
        guard let activity = activity else { return }
        let state = NowPlayingActivityAttributes.ContentState(from: snapshot)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// End the activity. Optionally dismisses immediately; otherwise
    /// iOS keeps a "final state" card around briefly per its rules.
    func end(dismiss immediately: Bool = true) {
        guard let activity = activity else { return }
        let state = activity.content.state
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: immediately ? .immediate : .default
            )
            await MainActor.run {
                self.activity = nil
                self.isActive = false
                print("[LiveActivity] ended")
            }
        }
    }

    // MARK: - Helpers

    private var isEnabledOnDevice: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
}

