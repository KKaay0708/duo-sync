//
//  NowPlayingService.swift
//  duo-sync
//
//  Polls Spotify Web API for the user's currently-playing track
//  and:
//    1) publishes a @Published snapshot for the SwiftUI HomeView
//    2) writes the snapshot to the App Group store
//    3) asks WidgetCenter to reload the widget timeline
//
//  Spotify rate-limits aggressively, so we poll every 15s while
//  the app is in the foreground and stop when backgrounded.
//

import Foundation
import Combine
import WidgetKit
import UIKit

@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var snapshot: NowPlayingSnapshot?

    private let auth: SpotifyAuthManager
    private let api: SpotifyAPIClient
    private var pollTask: Task<Void, Never>?

    /// Seconds between polls while foregrounded.
    var pollInterval: TimeInterval = 15

    init(auth: SpotifyAuthManager) {
        self.auth = auth
        self.api = SpotifyAPIClient(auth: auth)
        self.snapshot = SharedStore.loadNowPlaying()
        observeLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public control

    func start() {
        stop()
        guard !auth.isGuest else {
            // No real tokens — leave whatever placeholder/last snapshot is in place.
            return
        }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Force a single refresh (e.g. pull-to-refresh).
    func refreshNow() async {
        await fetchOnce()
    }

    // MARK: - Polling

    private func pollLoop() async {
        while !Task.isCancelled {
            await fetchOnce()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func fetchOnce() async {
        do {
            let playing = try await api.currentlyPlaying()
            let snap = Self.makeSnapshot(from: playing)
            self.snapshot = snap
            SharedStore.saveNowPlaying(snap)

            print("[NowPlaying] poll \(snap?.trackName ?? "nil")")

            // 1) Push the Live Activity (no widget budget — instant).
            if let snap = snap {
                LiveActivityManager.shared.update(snapshot: snap)
            }

            // 2) Ask iOS to refresh the home/lock-screen widget. iOS
            //    throttles this internally per its budget — extras are
            //    coalesced. Activity update above is the real-time path.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Don't clear the existing snapshot on transient errors.
        }
    }

    private static func makeSnapshot(from playing: CurrentlyPlaying?) -> NowPlayingSnapshot? {
        guard let playing = playing, let item = playing.item else { return nil }
        let artURL = item.album.images.first.flatMap { URL(string: $0.url) }
        return NowPlayingSnapshot(
            trackName: item.name,
            artistName: item.artists.map { $0.name }.joined(separator: ", "),
            albumName: item.album.name,
            albumArtURL: artURL,
            isPlaying: playing.is_playing,
            progressMs: playing.progress_ms,
            durationMs: item.duration_ms,
            updatedAt: Date()
        )
    }

    // MARK: - App lifecycle

    private func observeLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func handleDidBecomeActive() {
        Task { @MainActor in
            start()
        }
    }

    @objc private func handleDidEnterBackground() {
        Task { @MainActor in
            stop()
        }
    }
}
