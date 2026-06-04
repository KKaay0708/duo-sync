//
//  SpotifyAuthManager.swift
//  duo-sync
//
//  Handles Spotify OAuth using the Authorization Code with PKCE flow
//  (recommended for native apps — no client secret required).
//
//  Flow:
//    1) Generate code verifier + code challenge (PKCE).
//    2) Open ASWebAuthenticationSession to /authorize.
//    3) On successful redirect to `duosync://callback?code=...`,
//       exchange the code at /api/token for an access + refresh token.
//    4) Persist tokens in the Keychain.
//    5) Refresh tokens automatically when the access token expires.
//

import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import Combine

// MARK: - Token model

struct SpotifyTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var scope: String
    /// Absolute date when the access token expires.
    var expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60) // refresh 60s early
    }
}

/// Lightweight user profile used by the UI.
/// Populated from the Spotify Web API after a real sign-in, or
/// stubbed out via `signInAsGuest()` while developing.
struct SpotifyUserProfile: Codable, Equatable {
    var id: String
    var displayName: String
    var avatarURL: URL?
}

private struct TokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let scope: String
    let expires_in: Int
    let refresh_token: String?
}

// MARK: - Auth Manager

@MainActor
final class SpotifyAuthManager: NSObject, ObservableObject {

    enum AuthState: Equatable {
        case signedOut
        case authorizing
        case signedIn
        case error(String)
    }

    @Published private(set) var state: AuthState = .signedOut
    @Published private(set) var tokens: SpotifyTokens?
    @Published private(set) var profile: SpotifyUserProfile?
    @Published private(set) var isGuest: Bool = false

    private let tokensKey = "spotify.tokens.v1"
    private let profileKey = "spotify.profile.v1"
    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?

    /// True when the Spotify client ID has been replaced with a real value.
    /// While developing without real credentials we route sign-in
    /// through `signInAsGuest()` automatically.
    private var isClientIDConfigured: Bool {
        let id = SpotifyConfig.clientID
        return !id.isEmpty
            && id != SpotifyConfig.placeholderClientID
            && id != "YOUR_SPOTIFY_CLIENT_ID"
    }

    override init() {
        super.init()
        if let stored = KeychainHelper.shared.readCodable(SpotifyTokens.self, for: tokensKey) {
            self.tokens = stored
            self.state = .signedIn
        }
        if let storedProfile = KeychainHelper.shared.readCodable(SpotifyUserProfile.self, for: profileKey) {
            self.profile = storedProfile
        }
    }

    // MARK: - Public API

    /// Kicks off the OAuth flow. Call from a SwiftUI button action.
    /// If the Spotify client ID hasn't been configured yet, this falls
    /// back to a mock guest sign-in so the rest of the app is usable
    /// during development.
    func signIn() {
        print("[Auth] signIn() called. clientID=\(SpotifyConfig.clientID) configured=\(isClientIDConfigured)")
        guard isClientIDConfigured else {
            print("[Auth] -> guest mode (client ID not configured)")
            signInAsGuest()
            return
        }
        print("[Auth] -> launching real Spotify OAuth")

        state = .authorizing
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(from: verifier)
        codeVerifier = verifier

        guard let authURL = buildAuthorizationURL(codeChallenge: challenge) else {
            state = .error("Failed to build authorization URL")
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: SpotifyConfig.callbackURLScheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.state = .signedOut
                    } else {
                        self.state = .error(error.localizedDescription)
                    }
                    return
                }
                guard let callbackURL = callbackURL else {
                    self.state = .error("No callback URL")
                    return
                }
                await self.handleCallback(url: callbackURL)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    func signOut() {
        tokens = nil
        profile = nil
        isGuest = false
        KeychainHelper.shared.delete(for: tokensKey)
        KeychainHelper.shared.delete(for: profileKey)
        SharedStore.saveWatchedUserID(nil)
        SharedStore.saveNowPlaying(nil)
        LiveActivityManager.shared.end()
        Task { await BackendClient.shared.clearSession() }
        state = .signedOut
    }

    /// Mock sign-in used while developing without real Spotify credentials.
    /// No network calls; just flips state to `.signedIn` with a stub profile.
    func signInAsGuest() {
        let mock = SpotifyUserProfile(
            id: "guest",
            displayName: "guest",
            avatarURL: nil
        )
        self.profile = mock
        try? KeychainHelper.shared.saveCodable(mock, for: profileKey)
        self.isGuest = true
        self.state = .signedIn
    }

    /// Fetches the user's profile from /me and caches it.
    /// Safe to call after a real sign-in completes.
    func loadProfile() async {
        guard !isGuest, tokens != nil else { return }
        do {
            let token = try await validAccessToken()
            var req = URLRequest(url: SpotifyConfig.webAPIBaseURL.appendingPathComponent("/me"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)

            struct Me: Decodable {
                let id: String
                let display_name: String?
                let images: [SpotifyImageDTO]?
            }
            struct SpotifyImageDTO: Decodable { let url: String }

            let me = try JSONDecoder().decode(Me.self, from: data)
            let profile = SpotifyUserProfile(
                id: me.id,
                displayName: me.display_name ?? me.id,
                avatarURL: me.images?.first.flatMap { URL(string: $0.url) }
            )
            self.profile = profile
            try? KeychainHelper.shared.saveCodable(profile, for: profileKey)
        } catch {
            // Non-fatal — leave whatever profile was stored.
        }
    }

    /// Returns a valid access token, refreshing it if needed.
    func validAccessToken() async throws -> String {
        guard var current = tokens else {
            throw SpotifyAuthError.notAuthenticated
        }
        if current.isExpired {
            current = try await refresh(using: current.refreshToken)
            self.tokens = current
            try? KeychainHelper.shared.saveCodable(current, for: tokensKey)
        }
        return current.accessToken
    }

    // MARK: - Callback Handling

    private func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            if let err = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value {
                state = .error("Spotify returned error: \(err)")
            } else {
                state = .error("Missing authorization code")
            }
            return
        }

        guard let verifier = codeVerifier else {
            state = .error("Missing PKCE code verifier")
            return
        }

        do {
            let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: verifier)
            self.tokens = tokens
            self.isGuest = false
            try? KeychainHelper.shared.saveCodable(tokens, for: tokensKey)
            self.state = .signedIn
            await loadProfile()
            await registerWithBackend(tokens: tokens)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Hand the freshly-issued Spotify tokens to the duo-sync backend so
    /// it can keep its own copy (encrypted at rest) and the poll worker
    /// can drive silent push for the widget when the app is closed.
    /// Non-fatal: if the backend is unreachable we still consider the
    /// user signed in.
    private func registerWithBackend(tokens: SpotifyTokens) async {
        do {
            let session = try await BackendClient.shared.signInWithSpotify(tokens: tokens)
            print("[Auth] backend session established for \(session.user.spotify_id)")

            // Persist what the widget needs to fetch on its own when
            // the app is fully closed.
            SharedStore.saveWatchedUserID(session.user.id)
            if let url = SupabaseConfig.url?.absoluteString, SupabaseConfig.isConfigured {
                SharedStore.saveSupabaseCredentials(url: url, anonKey: SupabaseConfig.anonKey)
            }

            // Subscribe to our own now-playing channel for testing.
            // Later this becomes the *partner's* user ID.
            if let userID = UUID(uuidString: session.user.id) {
                await RealtimeNowPlayingClient.shared.subscribe(toUserID: userID)
            }

            // Kick off the lock-screen / Dynamic Island Live Activity.
            // While developing, "watched" = you. Once friending exists
            // we'll start with the partner's display name + user id.
            LiveActivityManager.shared.start(
                watchedName: session.user.display_name ?? session.user.spotify_id,
                watchedUserID: session.user.id,
                snapshot: SharedStore.loadNowPlaying()
            )
        } catch {
            print("[Auth] backend registration failed (non-fatal):", error.localizedDescription)
        }
    }

    // MARK: - Token Exchange + Refresh

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> SpotifyTokens {
        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": codeVerifier
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.ensureSuccess(response: response, data: data)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)

        return SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? "",
            tokenType: decoded.token_type,
            scope: decoded.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    private func refresh(using refreshToken: String) async throws -> SpotifyTokens {
        guard !refreshToken.isEmpty else { throw SpotifyAuthError.noRefreshToken }

        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SpotifyConfig.clientID
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.ensureSuccess(response: response, data: data)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)

        return SpotifyTokens(
            accessToken: decoded.access_token,
            // Spotify sometimes rotates the refresh token; fall back to existing if absent.
            refreshToken: decoded.refresh_token ?? refreshToken,
            tokenType: decoded.token_type,
            scope: decoded.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    // MARK: - URL Building

    private func buildAuthorizationURL(codeChallenge: String) -> URL? {
        var components = URLComponents(url: SpotifyConfig.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopeString),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        return components?.url
    }

    // MARK: - PKCE Helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(from verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64URLEncodedString()
    }

    // MARK: - HTTP Helpers

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAuthError.httpError(http.statusCode, body)
        }
    }
}

// MARK: - Errors

enum SpotifyAuthError: LocalizedError {
    case notAuthenticated
    case noRefreshToken
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Spotify."
        case .noRefreshToken: return "No refresh token available."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}

// MARK: - Presentation context

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the active foreground window.
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Base64URL helper

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        // RFC 3986 unreserved characters
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return allowed
    }()
}
