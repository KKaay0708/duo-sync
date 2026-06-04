//
//  DuoSyncWidgetBundle.swift
//  duo-sync-Widget
//
//  Entry point for the widget extension. Lists all widgets the
//  extension exposes.
//

import WidgetKit
import SwiftUI

@main
struct DuoSyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        NowPlayingLiveActivity()
    }
}
