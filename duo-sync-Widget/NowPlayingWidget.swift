//
//  NowPlayingWidget.swift
//  duo-sync-Widget
//
//  Home Screen widget that reads the latest NowPlayingSnapshot
//  from the App Group and renders track + artist + album art.
//
//  The main app calls WidgetCenter.shared.reloadAllTimelines()
//  whenever it polls Spotify, which prompts the system to ask
//  for a new timeline here.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let snap = SharedStore.loadNowPlaying() ?? .preview
        completion(NowPlayingEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        print("[Widget] getTimeline called by iOS — family=\(context.family) preview=\(context.isPreview)")
        Task {
            // 1) Pull a fresh snapshot from Supabase REST. Runs inside
            //    the widget extension process — works even when the
            //    main iOS app is fully closed.
            let remote = await SupabaseFetcher.fetchWatchedSnapshot()

            // 2) Fall back to whatever the main app last wrote into
            //    the App Group if the network call returned nothing.
            let base = remote ?? SharedStore.loadNowPlaying() ?? .placeholder
            print("[Widget] using snapshot source: \(remote != nil ? "Supabase REST" : "App Group cache")")

            // 3) Persist the fresh snapshot so subsequent renders pick it up.
            if let remote = remote {
                SharedStore.saveNowPlaying(remote)
            }

            // 4) Build multi-entry timeline so the progress bar keeps
            //    moving between system refreshes.
            let entries = Self.makeTickingEntries(base: base, count: 16, stepSeconds: 15)
            // Ask iOS to refresh us again in 5 min. iOS may run sooner
            // or later based on its widget budget — for the same
            // widget, expect ~15-60 min in practice on a free account.
            let next = Date().addingTimeInterval(5 * 60)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    /// Builds `count` entries spaced `stepSeconds` apart, with the
    /// snapshot's `progressMs` advanced on each step. iOS will roll
    /// from one entry to the next at the scheduled time without a
    /// new poll, so the progress bar visibly advances every step.
    private static func makeTickingEntries(
        base: NowPlayingSnapshot,
        count: Int,
        stepSeconds: Int
    ) -> [NowPlayingEntry] {
        let now = Date()
        var entries: [NowPlayingEntry] = []
        let stepMs = stepSeconds * 1000

        for i in 0..<count {
            let date = now.addingTimeInterval(TimeInterval(i * stepSeconds))
            var snap = base
            if base.isPlaying, let p = base.progressMs, let d = base.durationMs, d > 0 {
                let advanced = p + i * stepMs
                snap.progressMs = min(advanced, d)
            }
            entries.append(NowPlayingEntry(date: date, snapshot: snap))
        }
        return entries
    }
}

// MARK: - Widget

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows what you're currently listening to on Spotify.")
        .supportedFamilies([
            // Home Screen
            .systemSmall, .systemMedium,
            // Lock Screen
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

// MARK: - Views

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        switch family {
        case .systemSmall:           SmallView(snapshot: entry.snapshot)
        case .systemMedium:          MediumView(snapshot: entry.snapshot)
        case .accessoryInline:       InlineAccessoryView(snapshot: entry.snapshot)
        case .accessoryCircular:     CircularAccessoryView(snapshot: entry.snapshot)
        case .accessoryRectangular:  RectangularAccessoryView(snapshot: entry.snapshot)
        default:                     MediumView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Lock Screen accessory views

/// Single-line text shown above the clock on the lock screen.
private struct InlineAccessoryView: View {
    let snapshot: NowPlayingSnapshot

    var body: some View {
        let prefix = snapshot.isPlaying ? "♫" : "❚❚"
        if snapshot.trackName == "Nothing playing" {
            Text("\(prefix) duo-sync")
        } else {
            Text("\(prefix) \(snapshot.trackName) — \(snapshot.artistName)")
        }
    }
}

/// Small circular complication. Shows play/pause icon over a progress ring.
private struct CircularAccessoryView: View {
    let snapshot: NowPlayingSnapshot

    private var fraction: Double {
        guard let p = snapshot.progressMs, let d = snapshot.durationMs, d > 0 else { return 0 }
        return min(1, max(0, Double(p) / Double(d)))
    }

    var body: some View {
        ZStack {
            // Progress ring around the edge of the complication
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: snapshot.isPlaying ? "music.note" : "pause.fill")
                .font(.system(size: 18, weight: .bold))
                .widgetAccentable()
        }
        .padding(2)
    }
}

/// Wide rectangular complication. Track + artist + a small play indicator.
private struct RectangularAccessoryView: View {
    let snapshot: NowPlayingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .widgetAccentable()
                Text(snapshot.isPlaying ? "Now playing" : "Paused")
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
            }
            Text(snapshot.trackName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(snapshot.artistName)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmallView: View {
    let snapshot: NowPlayingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumArt(url: snapshot.albumArtURL)
                .frame(width: 56, height: 56)
            Text(snapshot.trackName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            Text(snapshot.artistName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            PlayStateBadge(isPlaying: snapshot.isPlaying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumView: View {
    let snapshot: NowPlayingSnapshot

    var body: some View {
        HStack(spacing: 12) {
            AlbumArt(url: snapshot.albumArtURL)
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                PlayStateBadge(isPlaying: snapshot.isPlaying)
                Text(snapshot.trackName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                Text(snapshot.artistName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !snapshot.albumName.isEmpty {
                    Text(snapshot.albumName)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                ProgressBar(progress: snapshot.progressMs, duration: snapshot.durationMs)
                    .frame(height: 4)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Subviews

private struct AlbumArt: View {
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

private struct PlayStateBadge: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 9, weight: .bold))
            Text(isPlaying ? "PLAYING" : "PAUSED")
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

private struct ProgressBar: View {
    let progress: Int?
    let duration: Int?

    private var fraction: Double {
        guard let p = progress, let d = duration, d > 0 else { return 0 }
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

// MARK: - Preview

#Preview(as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: Date(), snapshot: .preview)
    NowPlayingEntry(date: Date(), snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: Date(), snapshot: .preview)
}

#Preview(as: .accessoryInline) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: Date(), snapshot: .preview)
    NowPlayingEntry(date: Date(), snapshot: .placeholder)
}

#Preview(as: .accessoryCircular) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: Date(), snapshot: .preview)
}

#Preview(as: .accessoryRectangular) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: Date(), snapshot: .preview)
}
