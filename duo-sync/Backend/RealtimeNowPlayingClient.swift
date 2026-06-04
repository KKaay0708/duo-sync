//
//  RealtimeNowPlayingClient.swift
//  duo-sync
//
//  Opens a Supabase Realtime channel and subscribes to row changes on
//  the `now_playing_state` table, filtered by `user_id`. Every change
//  is decoded into a `NowPlayingSnapshot`, written to the App Group,
//  and pushed to the widget via `WidgetCenter.reloadAllTimelines()`.
//
//  REQUIRES the Supabase Swift SDK to be added as a Swift Package
//  Dependency in Xcode:
//      File → Add Package Dependencies… →
//        https://github.com/supabase/supabase-swift
//      Pick the "Supabase" library, add to the duo-sync target.
//
//  When the SDK is not installed yet, this file is gated behind
//  `canImport(Supabase)` so the project still builds.
//

import Foundation
import WidgetKit

#if canImport(Supabase)
import Supabase
import Realtime

@MainActor
final class RealtimeNowPlayingClient {

    static let shared = RealtimeNowPlayingClient()

    private var client: SupabaseClient?
    private var channel: RealtimeChannelV2?
    private var subscribedUserID: UUID?

    private init() {
        guard let url = SupabaseConfig.url, SupabaseConfig.isConfigured else {
            print("[Realtime] not configured — skipping")
            return
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
    }

    // MARK: - Public API

    /// Subscribe to a user's now-playing changes. For an MVP that follows
    /// your own listening, pass the current user's ID. Later, swap in
    /// the partner's ID once friending exists.
    func subscribe(toUserID userID: UUID) async {
        guard let client = client else { return }
        if subscribedUserID == userID, channel != nil { return }

        await unsubscribe()

        let channel = client.channel("now_playing:\(userID.uuidString)")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "now_playing_state",
            filter: "user_id=eq.\(userID.uuidString)"
        )

        Task { [weak self] in
            for await change in changes {
                await self?.handle(change: change)
            }
        }

        await channel.subscribe()
        self.channel = channel
        self.subscribedUserID = userID
        print("[Realtime] subscribed to now_playing for user \(userID)")
    }

    func unsubscribe() async {
        if let channel = channel {
            await channel.unsubscribe()
        }
        channel = nil
        subscribedUserID = nil
    }

    // MARK: - Event handling

    private func handle(change: AnyAction) async {
        // Each event carries either `record` (INSERT/UPDATE) or
        // `oldRecord` (DELETE). We only care about new state.
        let row: [String: AnyJSON]?
        switch change {
        case .insert(let action): row = action.record
        case .update(let action): row = action.record
        case .delete:            row = nil
        }
        guard let row = row else { return }
        guard let snap = Self.snapshot(from: row) else { return }

        SharedStore.saveNowPlaying(snap)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .realtimeNowPlayingUpdated, object: snap)
        print("[Realtime] applied snapshot:", snap.trackName)
    }

    private static func snapshot(from row: [String: AnyJSON]) -> NowPlayingSnapshot? {
        func str(_ k: String) -> String? { row[k]?.stringValue }
        func int(_ k: String) -> Int?    { row[k]?.intValue ?? Int(row[k]?.doubleValue ?? .nan) }
        func bool(_ k: String) -> Bool   { row[k]?.boolValue ?? false }

        let trackName = str("track_name") ?? "Nothing playing"
        let artistName = str("artist_name") ?? "—"
        return NowPlayingSnapshot(
            trackName: trackName,
            artistName: artistName,
            albumName: str("album_name") ?? "",
            albumArtURL: str("album_art_url").flatMap(URL.init(string:)),
            isPlaying: bool("is_playing"),
            progressMs: int("progress_ms"),
            durationMs: int("duration_ms"),
            updatedAt: Date()
        )
    }
}

#else
// Stub used until the Supabase Swift package is added to the target.
@MainActor
final class RealtimeNowPlayingClient {
    static let shared = RealtimeNowPlayingClient()
    private init() {}
    func subscribe(toUserID userID: UUID) async {
        print("[Realtime] Supabase SDK not added yet — subscribe() is a no-op")
    }
    func unsubscribe() async {}
}
#endif

extension Notification.Name {
    static let realtimeNowPlayingUpdated = Notification.Name("RealtimeNowPlayingUpdated")
}
