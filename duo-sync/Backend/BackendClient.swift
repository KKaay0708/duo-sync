//
//  BackendClient.swift
//  duo-sync
//
//  Talks to the duo-sync backend.  After Spotify OAuth completes on
//  device, the iOS app POSTs the Spotify tokens to /auth/spotify and
//  receives a session JWT in return. All subsequent backend calls
//  carry that JWT in the Authorization header.
//

import Foundation

// MARK: - Configuration

enum BackendConfig {
    /// Base URL of the duo-sync backend.
    /// During local dev: "http://localhost:8000".
    /// In production: your Railway URL, e.g. "https://duo-sync.up.railway.app".
    static let baseURL: URL = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           let url = URL(string: s) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }()
}

// MARK: - Models

struct BackendUser: Codable, Equatable {
    let id: String
    let spotify_id: String
    let display_name: String?
    let email: String?
    let avatar_url: String?
    let created_at: String
}

struct BackendSession: Codable, Equatable {
    let session_token: String
    let user: BackendUser
}

struct BackendSpotifyAuthRequest: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let scope: String?
}

struct BackendDeviceTokenRequest: Codable {
    let apns_token: String
}

// MARK: - Errors

enum BackendError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from backend"
        case .http(let code, let body): return "Backend HTTP \(code): \(body)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Client

actor BackendClient {
    static let shared = BackendClient()

    private let session: URLSession = .shared
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let sessionTokenKey = "duo-sync.backend.session.v1"

    // MARK: Session storage

    var sessionToken: String? {
        guard let data = KeychainHelper.shared.read(for: sessionTokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveSessionToken(_ token: String) {
        if let data = token.data(using: .utf8) {
            try? KeychainHelper.shared.save(data, for: sessionTokenKey)
        }
    }

    func clearSession() {
        KeychainHelper.shared.delete(for: sessionTokenKey)
    }

    // MARK: Endpoints

    /// POST /auth/spotify — exchanges Spotify PKCE tokens for a backend session.
    @discardableResult
    func signInWithSpotify(tokens: SpotifyTokens) async throws -> BackendSession {
        let secondsRemaining = max(60, Int(tokens.expiresAt.timeIntervalSinceNow))
        let body = BackendSpotifyAuthRequest(
            access_token: tokens.accessToken,
            refresh_token: tokens.refreshToken,
            expires_in: secondsRemaining,
            scope: tokens.scope
        )
        let session: BackendSession = try await post("/auth/spotify", body: body, requiresAuth: false)
        saveSessionToken(session.session_token)
        return session
    }

    /// GET /me — returns the current authed user.
    func fetchMe() async throws -> BackendUser {
        try await get("/me")
    }

    /// POST /me/device-token — registers this device for APNs silent push.
    func registerDeviceToken(_ apnsToken: String) async throws {
        let body = BackendDeviceTokenRequest(apns_token: apnsToken)
        let _: EmptyResponse = try await post("/me/device-token", body: body, requiresAuth: true, allowEmpty: true)
    }

    // MARK: Generic HTTP

    private struct EmptyResponse: Decodable {}

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: Optional<Bool>.none, requiresAuth: true, allowEmpty: false)
    }

    private func post<B: Encodable, T: Decodable>(
        _ path: String,
        body: B,
        requiresAuth: Bool,
        allowEmpty: Bool = false
    ) async throws -> T {
        try await request(path: path, method: "POST", body: body, requiresAuth: requiresAuth, allowEmpty: allowEmpty)
    }

    private func request<B: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: B?,
        requiresAuth: Bool,
        allowEmpty: Bool
    ) async throws -> T {
        let url = BackendConfig.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth {
            guard let token = sessionToken else {
                throw BackendError.http(401, "No backend session")
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw BackendError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw BackendError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        if allowEmpty, data.isEmpty {
            // Caller declared T = EmptyResponse — produce one.
            return try decoder.decode(T.self, from: Data("{}".utf8))
        }
        return try decoder.decode(T.self, from: data)
    }
}
