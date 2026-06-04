//
//  ContentView.swift
//  duo-sync
//
//  Created by Kaitlyn Kwan on 5/19/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: SpotifyAuthManager

    var body: some View {
        Group {
            switch auth.state {
            case .signedIn:
                HomeView()
            default:
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
    }
}

#Preview("Signed Out") {
    ContentView()
        .environmentObject(SpotifyAuthManager())
}

#Preview("Signed In (guest)") {
    let auth = SpotifyAuthManager()
    auth.signInAsGuest()
    return ContentView().environmentObject(auth)
}
