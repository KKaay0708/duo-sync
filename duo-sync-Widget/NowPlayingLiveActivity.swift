//
//  NowPlayingLiveActivity.swift
//  duo-sync-Widget
//
//  Live Activity for the duo-sync now-playing feed. Renders three views:
//    1) Lock screen / banner — the big card you see when phone is locked
//    2) Dynamic Island compact (leading + trailing chips)
//    3) Dynamic Island expanded (rich card when long-pressed)
//    4) Dynamic Island minimal (when multiple activities collapse)
//
//  Activities are exempt from WidgetKit's timeline refresh budget, so
//  each `Activity.update()` from the main app renders immediately.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            // Lock screen / banner
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(white: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded: shown when user long-presses the island.
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedArt(url: context.state.albumArtURL)
                        .frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayBadge(isPlaying: context.state.isPlaying)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.watchedName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.trackName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(context.state.artistName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveProgressBar(state: context.state)
                        .frame(height: 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.trackName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Lock-screen card

private struct LockScreenView: View {
    let attributes: NowPlayingActivityAttributes
    let state: NowPlayingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ExpandedArt(url: state.albumArtURL)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(attributes.watchedName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PlayBadge(isPlaying: state.isPlaying)
                }
                Text(state.trackName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(state.artistName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                LiveProgressBar(state: state)
                    .frame(height: 4)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Subviews

private struct ExpandedArt: View {
    let url: URL?

    var body: some View {
        Group {
            if let url = url, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.25))
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PlayBadge: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 9, weight: .bold))
            Text(isPlaying ? "LIVE" : "PAUSED")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(isPlaying ? Color.green : Color.gray)
        )
    }
}

/// Progress bar that animates locally using the timer text style so
/// the bar moves smoothly between explicit Activity.update() calls.
private struct LiveProgressBar: View {
    let state: NowPlayingActivityAttributes.ContentState

    private var fraction: Double {
        guard let p = state.progressMs, let d = state.durationMs, d > 0 else { return 0 }
        return min(1, max(0, Double(p) / Double(d)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(Color.primary).frame(width: geo.size.width * fraction)
            }
        }
    }
}
