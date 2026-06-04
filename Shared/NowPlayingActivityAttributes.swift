//
//  NowPlayingActivityAttributes.swift
//  duo-sync (shared between main app and widget extension)
//
//  ActivityAttributes for the now-playing Live Activity.
//
//  - `ContentState` holds the dynamic fields (track, artist, art, etc).
//     The main app updates this each time NowPlayingService gets a
//     fresh snapshot; iOS re-renders the lock-screen + Dynamic Island
//     views automatically with no widget-budget throttling.
//
//  - The fixed attributes carry the identity of the user whose
//     listening is being shown (you, or eventually your partner).
//

import ActivityKit
import Foundation

struct NowPlayingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var trackName: String
        var artistName: String
        var albumName: String
        var albumArtURL: URL?
        var isPlaying: Bool
        var progressMs: Int?
        var durationMs: Int?
        var updatedAt: Date
    }

    /// Displayed name of the person whose listening is being shown.
    var watchedName: String

    /// Spotify/duo-sync user id of whoever is being watched.
    var watchedUserID: String
}

// MARK: - Bridging helpers

extension NowPlayingActivityAttributes.ContentState {
    init(from snapshot: NowPlayingSnapshot) {
        self.trackName = snapshot.trackName
        self.artistName = snapshot.artistName
        self.albumName = snapshot.albumName
        self.albumArtURL = snapshot.albumArtURL
        self.isPlaying = snapshot.isPlaying
        self.progressMs = snapshot.progressMs
        self.durationMs = snapshot.durationMs
        self.updatedAt = snapshot.updatedAt
    }

    static let preview = NowPlayingActivityAttributes.ContentState(
        trackName: "Heat Waves",
        artistName: "Glass Animals",
        albumName: "Dreamland",
        albumArtURL: nil,
        isPlaying: true,
        progressMs: 72_000,
        durationMs: 238_000,
        updatedAt: Date()
    )

    static let placeholder = NowPlayingActivityAttributes.ContentState(
        trackName: "Nothing playing",
        artistName: "—",
        albumName: "",
        albumArtURL: nil,
        isPlaying: false,
        progressMs: nil,
        durationMs: nil,
        updatedAt: Date()
    )
}
