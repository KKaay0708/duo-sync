//
//  HomeView.swift
//  duo-sync
//
//  Empty home screen shown after sign-in. The top-right shows the
//  user's profile (avatar + display name) which opens a menu with
//  a Log out action.
//

import SwiftUI
import WidgetKit

struct HomeView: View {
    @EnvironmentObject private var auth: SpotifyAuthManager
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NowPlayingCard(snapshot: nowPlaying.snapshot)
                        .padding(.horizontal)
                        .padding(.top, 12)
                    WidgetDebugCard()
                        .padding(.horizontal)
                    Spacer(minLength: 0)
                }
            }
            .refreshable { await nowPlaying.refreshNow() }
            .navigationTitle("duo-sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileMenu()
                }
            }
        }
    }
}

// MARK: - Widget + Live Activity debug card

private struct WidgetDebugCard: View {
    @EnvironmentObject private var auth: SpotifyAuthManager
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @StateObject private var activityManager = LiveActivityManager.shared
    @State private var status: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WIDGET + LIVE ACTIVITY DEBUG")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Reload widget", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)

                if activityManager.isActive {
                    Button(role: .destructive) {
                        LiveActivityManager.shared.end()
                    } label: {
                        Label("End Live Activity", systemImage: "stop.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        startActivity()
                    } label: {
                        Label("Start Live Activity", systemImage: "play.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func startActivity() {
        let name = auth.profile?.displayName ?? "you"
        let id = SharedStore.loadWatchedUserID() ?? auth.profile?.id ?? "unknown"
        LiveActivityManager.shared.start(
            watchedName: name,
            watchedUserID: id,
            snapshot: nowPlaying.snapshot ?? SharedStore.loadNowPlaying()
        )
    }

    @MainActor
    private func reload() async {
        let userID = SharedStore.loadWatchedUserID() ?? "<none>"
        let creds = SharedStore.loadSupabaseCredentials()
        let urlSummary = creds.map { String($0.url.prefix(40)) } ?? "<none>"
        let keySummary = creds.map { String($0.anonKey.prefix(8)) + "…" } ?? "<none>"
        let lastSnap = SharedStore.loadNowPlaying().map { "\($0.trackName) — \($0.artistName)" } ?? "<none>"
        let activityState = activityManager.isActive ? "running" : "stopped"

        WidgetCenter.shared.reloadAllTimelines()

        status = """
        watchedUserID: \(userID)
        supabase URL: \(urlSummary)
        supabase key: \(keySummary)
        last snapshot: \(lastSnap)
        live activity: \(activityState)
        sent reloadAllTimelines() ✓
        """
    }
}

// MARK: - Now playing card

private struct NowPlayingCard: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        HStack(spacing: 14) {
            artwork
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot?.isPlaying == true ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(snapshot?.isPlaying == true ? "NOW PLAYING" : "PAUSED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.secondary)

                Text(snapshot?.trackName ?? "Nothing playing")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(snapshot?.artistName ?? "Start Spotify to sync")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = snapshot?.albumArtURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Profile menu

private struct ProfileMenu: View {
    @EnvironmentObject private var auth: SpotifyAuthManager

    var body: some View {
        Menu {
            if let profile = auth.profile {
                Text(profile.displayName)
                if auth.isGuest {
                    Text("Guest mode")
                }
                Divider()
            }
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 8) {
                ProfileAvatar(url: auth.profile?.avatarURL)
                Text(auth.profile?.displayName ?? "Profile")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(.secondarySystemBackground))
            )
        }
    }
}

private struct ProfileAvatar: View {
    let url: URL?

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemBackground))
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let auth = SpotifyAuthManager()
    auth.signInAsGuest()
    return HomeView().environmentObject(auth)
}
