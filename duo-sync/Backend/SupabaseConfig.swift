//
//  SupabaseConfig.swift
//  duo-sync
//
//  Supabase project URL + anonymous public API key used by the iOS
//  Realtime client. Both are safe to ship — the anon key only grants
//  whatever Row Level Security policies allow.
//
//  Values are read from the auto-generated Info.plist (set via
//  Config/Secrets.xcconfig) with hardcoded fallbacks for convenience.
//

import Foundation

enum SupabaseConfig {
    // MARK: - Project credentials
    //
    // Find these in Supabase → your project → Settings → API:
    //   - "Project URL"   → SUPABASE_URL
    //   - anon "public" API key → SUPABASE_ANON_KEY
    //
    // Then add to Config/Secrets.xcconfig:
    //   SUPABASE_URL = https://YOUR_REF.supabase.co
    //   SUPABASE_ANON_KEY = eyJhbGciOi...
    //   INFOPLIST_KEY_SupabaseURL = $(SUPABASE_URL)
    //   INFOPLIST_KEY_SupabaseAnonKey = $(SUPABASE_ANON_KEY)
    private static let hardcodedURL: String = ""        // optional fallback
    private static let hardcodedAnonKey: String = ""    // optional fallback

    static let url: URL? = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return URL(string: hardcodedURL)
    }()

    static let anonKey: String = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
           !s.isEmpty {
            return s
        }
        return hardcodedAnonKey
    }()

    static var isConfigured: Bool {
        url != nil && !anonKey.isEmpty
    }
}
