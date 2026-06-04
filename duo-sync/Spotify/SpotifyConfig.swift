//
//  SpotifyConfig.swift
//  duo-sync
//
//  Centralized configuration for Spotify Web API integration.
//

import Foundation

enum SpotifyConfig {
    // MARK: - App Credentials
    //
    // The Spotify Client ID is loaded from `Config/Secrets.xcconfig`
    // (variable `SPOTIFY_CLIENT_ID`). The xcconfig surfaces it into
    // the auto-generated Info.plist under the key `SpotifyClientID`,
    // and we read it from `Bundle.main` here at runtime.
    //
    // The placeholder value below is the sentinel used to detect that
    // no real client ID is configured. DO NOT replace it with your
    // real Spotify Client ID — paste that into `hardcodedClientID`
    // below (or set it in Config/Secrets.xcconfig).
    static let placeholderClientID = "kaitlynspotifyclientid"

    /// Optional hard-coded fallback used when the xcconfig pipeline
    /// isn't propagating into Info.plist. Safe to commit — PKCE has
    /// no client secret. Leave as "" to rely solely on the xcconfig.
    private static let hardcodedClientID: String = "beb87efbee1d4fe89a69ab1b85b68a23"

    static let clientID: String = {
        // 1) Value injected by Secrets.xcconfig → Info.plist
        if let id = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String,
           !id.isEmpty,
           id != placeholderClientID {
            print("[SpotifyConfig] using clientID from Info.plist (xcconfig):", id)
            return id
        }
        // 2) Hard-coded fallback in this file
        if !hardcodedClientID.isEmpty, hardcodedClientID != placeholderClientID {
            print("[SpotifyConfig] using clientID from hardcoded fallback:", hardcodedClientID)
            return hardcodedClientID
        }
        // 3) Nothing configured — guest mode will activate
        print("[SpotifyConfig] clientID NOT configured — guest mode will be used")
        return placeholderClientID
    }()

    /// Custom URL scheme registered in Info.plist under CFBundleURLTypes.
    /// Example value below uses `duosync://callback` — register `duosync`
    /// as a URL scheme in the target's Info settings, and add the same
    /// URI in the Spotify developer dashboard.
    static let redirectURI: String = "duosync://callback"

    /// The scheme portion of the redirect URI, used by ASWebAuthenticationSession.
    static let callbackURLScheme: String = "duosync"

    // MARK: - Endpoints
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let webAPIBaseURL = URL(string: "https://api.spotify.com/v1")!

    // MARK: - Scopes
    /// Adjust scopes based on what features duo-sync needs.
    /// See: https://developer.spotify.com/documentation/web-api/concepts/scopes
    static let scopes: [String] = [
        "user-read-private",
        "user-read-email",
        "user-read-currently-playing",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-recently-played",
        "user-top-read",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-private",
        "playlist-modify-public"
    ]

    static var scopeString: String {
        scopes.joined(separator: " ")
    }
}
