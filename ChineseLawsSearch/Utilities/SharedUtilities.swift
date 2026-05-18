//
//  SharedUtilities.swift
//  ChineseLawsSearch
//
//  Shared utilities used across multiple views/services.
//

import SwiftUI
import RegexBuilder

// MARK: - Gazette source display name

private func _sourceDisplayName(_ source: String) -> String {
    switch source {
    case "al":     return "指导案例"
    case "sfwj":   return "司法文件"
    case "cpwsxd": return "裁判文书"
    default:       return source
    }
}

extension GazetteDoc {
    var sourceDisplayName: String { _sourceDisplayName(source) }
}

extension GazetteCitation {
    var sourceDisplayName: String { _sourceDisplayName(source) }
}

// MARK: - Article reference regex (shared between LegalChatView and LegalChatViewModel)

enum ArticleRefPattern {
    /// Matches 《LawTitle》[optional space]第X条  (title 2-90 chars)
    static let regex = try! NSRegularExpression(
        pattern: #"《([^》]{2,90})》\s*(第[一二三四五六七八九十百千零\d]+条)"#
    )
}

// MARK: - Text highlighting (shared between TOCView and SearchView)

/// Highlights all occurrences of `query` in `text` with bold + `highlightColor`.
/// Supports Chinese/Arabic number variants via `DatabaseManager.numberVariant`.
func highlightedText(_ text: String,
                     query: String,
                     baseFont: Font = .body,
                     highlightColor: Color = AppColors.shared.searchHighlight) -> Text {
    guard !query.isEmpty else { return Text(text).font(baseFont) }

    let keywords = [query, DatabaseManager.numberVariant(of: query)]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

    var ranges: [Range<String.Index>] = []
    for kw in keywords {
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex,
              let r = text.range(of: kw, options: .caseInsensitive, range: searchFrom..<text.endIndex) {
            ranges.append(r)
            searchFrom = r.upperBound
        }
    }
    guard !ranges.isEmpty else { return Text(text).font(baseFont) }

    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    var merged: [Range<String.Index>] = []
    for r in sorted {
        if let last = merged.last, last.upperBound >= r.lowerBound {
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
        } else {
            merged.append(r)
        }
    }

    var attributed = AttributedString(text)
    for r in merged {
        guard let attrRange = Range(r, in: attributed) else { continue }
        attributed[attrRange].foregroundColor = highlightColor
        attributed[attrRange].font = baseFont.bold()
    }
    return Text(attributed).font(baseFont)
}
