//
//  AppColors.swift
//  ChineseLawsSearch
//

import SwiftUI
import UIKit

struct AppColors {
    static let shared = AppColors()

    let folderIcon: Color
    let tagIcon: Color
    let searchHighlight: Color
    let articleHighlight: Color
    let outgoingRef: UIColor
    let incomingRef: Color

    private init() {
        guard let url = Bundle.main.url(forResource: "AppColors", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else {
            // 默认值
            folderIcon      = .orange
            tagIcon         = .orange
            searchHighlight = .orange
            articleHighlight = .orange
            outgoingRef     = .systemOrange
            incomingRef     = .orange
            return
        }
        folderIcon       = Self.color(dict["folderIcon"],       fallback: .orange)
        tagIcon          = Self.color(dict["tagIcon"],          fallback: .orange)
        searchHighlight  = Self.color(dict["searchHighlight"],  fallback: .orange)
        articleHighlight = Self.color(dict["articleHighlight"], fallback: .orange)
        outgoingRef      = Self.uiColor(dict["outgoingRef"],    fallback: .systemOrange)
        incomingRef      = Self.color(dict["incomingRef"],      fallback: .orange)
    }

    private static func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex, let ui = UIColor(hex: hex) else { return fallback }
        return Color(ui)
    }

    private static func uiColor(_ hex: String?, fallback: UIColor) -> UIColor {
        guard let hex, let ui = UIColor(hex: hex) else { return fallback }
        return ui
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8)  & 0xFF) / 255,
            blue:  CGFloat( value        & 0xFF) / 255,
            alpha: 1
        )
    }
}
