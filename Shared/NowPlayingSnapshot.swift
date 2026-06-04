//
//  NowPlayingSnapshot.swift
//  duo-sync (shared between main app and widget extension)
//
//  Plain Codable model written by the main app and read by the
//  widget extension via an App Group UserDefaults suite.
//

import Foundation

struct NowPlayingSnapshot: Codable, Equatable {
    var trackName: String
    var artistName: String
    var albumName: String
    var albumArtURL: URL?
    var isPlaying: Bool
    var progressMs: Int?
    var durationMs: Int?
    var updatedAt: Date

    static let placeholder = NowPlayingSnapshot(
        trackName: "Nothing playing",
        artistName: "—",
        albumName: "",
        albumArtURL: nil,
        isPlaying: false,
        progressMs: nil,
        durationMs: nil,
        updatedAt: Date()
    )

    static let preview = NowPlayingSnapshot(
        trackName: "Heat Waves",
        artistName: "Glass Animals",
        albumName: "Dreamland",
        albumArtURL: nil,
        isPlaying: true,
        progressMs: 72_000,
        durationMs: 238_000,
        updatedAt: Date()
    )
}
