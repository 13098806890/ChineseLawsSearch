//
//  ExpertModels.swift
//  ChineseLawsSearch
//

import Foundation

struct RequiredInfo {
    let field: String
    let question: String
    let regexHint: String
}

struct SubExpert {
    let name: String
    let domain: String
    let requiredInfo: [RequiredInfo]
    let lawTitles: [String]
    let chapterIdHints: [Int]
    let ftsDomains: [String]
    let ftsCategories: [String]
    let ftsKeywordsExtra: [String]
    let answerTemplate: String
}

struct ExpertGroup {
    let name: String
    let description: String
    let subExperts: [SubExpert]
    let routingKeywords: [String]
}
