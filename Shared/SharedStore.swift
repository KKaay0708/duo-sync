//
//  SharedStore.swift
//  duo-sync (shared between main app and widget extension)
//
//  Thin wrapper around an App Group UserDefaults suite. The widget
//  reads from the same group, so anything written here becomes
//  visible to the widget timeline provider.
//

import Foundation

enum SharedStore {
    /// The App Group identifier shared between the main app and the
    /// widget extension. This string MUST match the App Group ID you
    /// add in Xcode → Signing & Capabilities → App Groups on BOTH
    /// the `duo-sync` target and the `duo-sync-Widget` target.
    ///
    /// The format must start with `group.` — the rest is up to you.
    /// Convention is `group.<your-bundle-id>`. The bundle ID for this
    /// project is `kkaay.duo-sync`, so we use:
    static let appGroupID = "group.kkaay.duo-sync"

    private static let nowPlayingKey = "nowPlaying.v1"
    private static let watchedUserKey = "watchedUserID.v1"
    private static let supabaseURLKey = "supabaseURL.v1"
    private static let supabaseAnonKey = "supabaseAnonKey.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - Now Playing

    static func saveNowPlaying(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot = snapshot else {
            defaults.removeObject(forKey: nowPlayingKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: nowPlayingKey)
        }
    }

    static func loadNowPlaying() -> NowPlayingSnapshot? {
        guard let data = defaults.data(forKey: nowPlayingKey) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    // MARK: - Widget watch target
    //
    // The widget needs to know which user's now-playing state to fetch
    // when it refreshes on its own (without the app being open). For
    // MVP that's the current user; once friending exists it becomes
    // the partner's user_id.

    static func saveWatchedUserID(_ id: String?) {
        if let id = id {
            defaults.set(id, forKey: watchedUserKey)
        } else {
            defaults.removeObject(forKey: watchedUserKey)
        }
    }

    static func loadWatchedUserID() -> String? {
        defaults.string(forKey: watchedUserKey)
    }

    // MARK: - Supabase credentials for the widget
    //
    // The widget extension reads these from the App Group so it can
    // hit Supabase REST directly without needing access to the iOS
    // app's Info.plist or any shared bundle.

    static func saveSupabaseCredentials(url: String, anonKey: String) {
        defaults.set(url, forKey: supabaseURLKey)
        defaults.set(anonKey, forKey: supabaseAnonKey)
    }

    static func loadSupabaseCredentials() -> (url: String, anonKey: String)? {
        guard let url = defaults.string(forKey: supabaseURLKey),
              let key = defaults.string(forKey: supabaseAnonKey),
              !url.isEmpty, !key.isEmpty
        else { return nil }
        return (url, key)
    }
}
