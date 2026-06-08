//
//  duo_syncApp.swift
//  duo-sync
//
//  Created by Kaitlyn Kwan on 5/19/26.
//

// commit again

import SwiftUI

@main
struct duo_syncApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    @StateObject private var authManager = SpotifyAuthManager()
    @StateObject private var nowPlaying: NowPlayingService

    init() {
        let auth = SpotifyAuthManager()
        _authManager = StateObject(wrappedValue: auth)
        _nowPlaying = StateObject(wrappedValue: NowPlayingService(auth: auth))
        print("Spotify Client ID loaded:", SpotifyConfig.clientID)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(nowPlaying)
                .onAppear {
                    // Hand the polling service to the AppDelegate so
                    // BG refresh + silent push handlers can call into it.
                    pushDelegate.nowPlaying = nowPlaying
                }
                .onChange(of: authManager.state) { _, newState in
                    if case .signedIn = newState {
                        nowPlaying.start()
                    } else {
                        nowPlaying.stop()
                        Task { await RealtimeNowPlayingClient.shared.unsubscribe() }
                    }
                }
        }
    }
}
