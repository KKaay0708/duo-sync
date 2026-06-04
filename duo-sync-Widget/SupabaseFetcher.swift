//
//  SupabaseFetcher.swift
//  duo-sync-Widget
//
//  Tiny URLSession-based client that pulls the latest `now_playing_state`
//  row for the watched user from Supabase's PostgREST endpoint, used by
//  the widget extension to refresh itself even when the main iOS app
//  isn't running. Reads its config from the App Group (saved by the
//  main app at sign-in time).
//

import Foundation

enum SupabaseFetcher {

    /// Fetch the latest snapshot for the currently watched user.
    /// Returns nil if not configured, the user is unknown, the
    /// network call fails, or no row exists yet.
    static func fetchWatchedSnapshot() async -> NowPlayingSnapshot? {
        guard let userID = SharedStore.loadWatchedUserID() else {
            print("[Widget/Fetch] no watchedUserID — skipping")
            return nil
        }
        guard let creds = SharedStore.loadSupabaseCredentials() else {
            print("[Widget/Fetch] no Supabase credentials — skipping")
            return nil
        }
        guard let baseURL = URL(string: creds.url) else {
            print("[Widget/Fetch] invalid Supabase URL: \(creds.url)")
            return nil
        }

        let restURL = baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("now_playing_state")

        var components = URLComponents(url: restURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue(creds.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(creds.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        do {
            print("[Widget/Fetch] GET \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[Widget/Fetch] HTTP \(status), \(data.count) bytes")
            guard status < 300 else {
                if let body = String(data: data, encoding: .utf8) {
                    print("[Widget/Fetch] error body: \(body)")
                }
                return nil
            }
            let snap = decodeFirstRow(data)
            if let snap = snap {
                print("[Widget/Fetch] decoded snapshot: \(snap.trackName) — \(snap.artistName) playing=\(snap.isPlaying)")
            } else {
                print("[Widget/Fetch] response decoded to nil (empty array?)")
            }
            return snap
        } catch {
            print("[Widget/Fetch] network error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Decoding

    private static func decodeFirstRow(_ data: Data) -> NowPlayingSnapshot? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = array.first
        else { return nil }
        return Self.snapshot(from: row)
    }

    private static func snapshot(from row: [String: Any]) -> NowPlayingSnapshot? {
        let trackName = row["track_name"] as? String ?? "Nothing playing"
        let artistName = row["artist_name"] as? String ?? "—"
        let albumName = row["album_name"] as? String ?? ""
        let artURL = (row["album_art_url"] as? String).flatMap(URL.init(string:))
        let isPlaying = row["is_playing"] as? Bool ?? false
        let progressMs = row["progress_ms"] as? Int
        let durationMs = row["duration_ms"] as? Int

        return NowPlayingSnapshot(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            albumArtURL: artURL,
            isPlaying: isPlaying,
            progressMs: progressMs,
            durationMs: durationMs,
            updatedAt: Date()
        )
    }
}
