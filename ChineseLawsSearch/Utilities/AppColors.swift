//
//  AppColors.swift
//  ChineseLawsSearch
//

import SwiftUI

struct AppColors {
    static let shared = AppColors()

    let folderIcon: Color
    let tagIcon: Color
    let searchHighlight: Color
    let articleHighlight: Color
    let outgoingRef: Color
    let incomingRef: Color

    private init() {
        guard let url = Bundle.main.url(forResource: "AppColors", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else {
            folderIcon       = .orange
            tagIcon          = .orange
            searchHighlight  = .orange
            articleHighlight = .orange
            outgoingRef      = .orange
            incomingRef      = .orange
            return
        }
        folderIcon       = Self.color(dict["folderIcon"],       fallback: .orange)
        tagIcon          = Self.color(dict["tagIcon"],          fallback: .orange)
        searchHighlight  = Self.color(dict["searchHighlight"],  fallback: .orange)
        articleHighlight = Self.color(dict["articleHighlight"], fallback: .orange)
        outgoingRef      = Self.color(dict["outgoingRef"],      fallback: .orange)
        incomingRef      = Self.color(dict["incomingRef"],      fallback: .orange)
    }

    private static func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex else { return fallback }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return fallback }
        return Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

// MARK: - Formatting utilities

/// Format a token count for display: numbers ≥ 1000 are shown as "x.xk".
func formatTokens(_ n: Int) -> String {
    n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
}
