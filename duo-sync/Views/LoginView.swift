//
//  LoginView.swift
//  duo-sync
//
//  Home/login screen matching the sketch:
//    - "duo-sync" title
//    - music note icon inside a circle
//    - "log in with Spotify" button
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: SpotifyAuthManager

    var body: some View {
        VStack {
            Spacer()

            // Title
            Text("duo-sync")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer().frame(height: 32)

            // Music note inside a circle
            ZStack {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 3)
                    .frame(width: 180, height: 180)
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Status / error messaging
            statusMessage
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            // Log in button
            Button(action: { auth.signIn() }) {
                HStack(spacing: 12) {
                    Image(systemName: "wifi")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Log in with Spotify")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.spotifyGreen)
                )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .disabled(isAuthorizing)
            .opacity(isAuthorizing ? 0.6 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var isAuthorizing: Bool {
        if case .authorizing = auth.state { return true }
        return false
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch auth.state {
        case .authorizing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Connecting to Spotify…").foregroundStyle(.secondary)
            }
        case .error(let message):
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
                .font(.footnote)
        default:
            EmptyView()
        }
    }
}

private extension Color {
    /// Spotify brand green.
    static let spotifyGreen = Color(red: 0.114, green: 0.725, blue: 0.329)
}

#Preview {
    LoginView()
        .environmentObject(SpotifyAuthManager())
}
