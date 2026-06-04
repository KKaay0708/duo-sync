//
//  SpotifyAPIClient.swift
//  duo-sync
//
//  Thin network manager around the Spotify Web API.
//  - Uses `SpotifyAuthManager.validAccessToken()` so every request is
//    transparently refreshed when needed.
//  - Provides a small typed surface (currentUser, currentlyPlaying, etc.).
//  - Extend by adding more endpoints in the `Endpoints` section.
//

import Foundation

// MARK: - Errors

enum SpotifyAPIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Spotify URL"
        case .http(let code, let body): return "Spotify HTTP \(code): \(body)"
        case .decoding(let error): return "Decoding failed: \(error.localizedDescription)"
        case .transport(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Common Models

struct SpotifyUser: Decodable, Identifiable, Sendable {
    let id: String
    let display_name: String?
    let email: String?
    let images: [SpotifyImage]?
}

struct SpotifyImage: Decodable, Hashable, Sendable {
    let url: String
    let height: Int?
    let width: Int?
}

struct SpotifyArtist: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct SpotifyAlbum: Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let images: [SpotifyImage]
}

struct SpotifyTrack: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let duration_ms: Int
    let uri: String
}

struct CurrentlyPlaying: Decodable, Sendable {
    let is_playing: Bool
    let progress_ms: Int?
    let item: SpotifyTrack?
}

struct PagedResponse<T: Decodable>: Decodable {
    let items: [T]
    let next: String?
    let total: Int?
}

extension PagedResponse: Sendable where T: Sendable {}

// MARK: - Client

final class SpotifyAPIClient: @unchecked Sendable {

    private let auth: SpotifyAuthManager
    private let session: URLSession
    private let decoder: JSONDecoder

    init(auth: SpotifyAuthManager, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Endpoints

    func currentUser() async throws -> SpotifyUser {
        try await get("/me")
    }

    func currentlyPlaying() async throws -> CurrentlyPlaying? {
        // /me/player/currently-playing returns 204 No Content if nothing is playing.
        let (data, status) = try await request(path: "/me/player/currently-playing", method: "GET")
        print("[SpotifyAPI] currently-playing -> HTTP \(status), \(data.count) bytes")
        if status == 204 {
            print("[SpotifyAPI] 204 = no active Spotify Connect session")
            return nil
        }
        // Log first chunk of body for debugging
        if data.count > 0, let preview = String(data: data.prefix(200), encoding: .utf8) {
            print("[SpotifyAPI] body preview: \(preview)")
        }
        let decoded = try decode(CurrentlyPlaying.self, from: data)
        if decoded.item == nil {
            print("[SpotifyAPI] response was 200 but item=null (ads playing? local file?)")
        }
        return decoded
    }

    /// Fallback: /me/player returns broader player state. Sometimes returns
    /// data when /me/player/currently-playing doesn't. Useful for diagnosing.
    func playerState() async throws -> Data {
        let (data, status) = try await request(path: "/me/player", method: "GET")
        print("[SpotifyAPI] player -> HTTP \(status), \(data.count) bytes")
        return data
    }

    func topTracks(limit: Int = 20, timeRange: String = "medium_term") async throws -> PagedResponse<SpotifyTrack> {
        try await get("/me/top/tracks", query: [
            "limit": String(limit),
            "time_range": timeRange
        ])
    }

    func recentlyPlayed(limit: Int = 20) async throws -> Data {
        // Returns a PlayHistoryObject paged response; keep as raw Data so callers
        // can define their own model if/when needed.
        let (data, _) = try await request(path: "/me/player/recently-played", method: "GET", query: ["limit": String(limit)])
        return data
    }

    // MARK: - Generic helpers (exposed for custom calls)

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let (data, _) = try await request(path: path, method: "GET", query: query)
        return try decode(T.self, from: data)
    }

    func put(_ path: String, body: Data? = nil) async throws {
        _ = try await request(path: path, method: "PUT", body: body)
    }

    func post<T: Decodable>(_ path: String, body: Data? = nil) async throws -> T {
        let (data, _) = try await request(path: path, method: "POST", body: body)
        return try decode(T.self, from: data)
    }

    // MARK: - Core request

    @discardableResult
    private func request(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, Int) {
        let token = try await auth.validAccessToken()

        var components = URLComponents(
            url: SpotifyConfig.webAPIBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw SpotifyAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SpotifyAPIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAPIError.http(status, body)
        }
        return (data, status)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }
}

