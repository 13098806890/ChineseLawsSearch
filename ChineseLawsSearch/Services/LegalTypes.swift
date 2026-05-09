//
//  LegalTypes.swift
//  ChineseLawsSearch
//
//  Shared data types used across LegalExpertService, LegalChatView, and ChatHistory.
//

import Foundation

// MARK: - Chat message

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id   = UUID()
    let role: Role
    var text: String             = ""
    var thinkSteps: [ThinkStep]  = []
    var citations: [RAGCitation] = []
    var subQuestions: [String]   = []
    var isClarifying: Bool       = false
    var subQuestionIndex: Int?   = nil
    var showSteps: Bool          = true
    var showCitations: Bool      = false
    var intent: MessageIntent?   = nil

    init(role: Role, text: String = "", isClarifying: Bool = false) {
        self.role = role
        self.text = text
        self.isClarifying = isClarifying
    }
}

// MARK: - Think step

struct ThinkStep: Identifiable, Equatable {
    let id      = UUID()
    let name:    String
    let content: String
    var articles: [RAGCitation] = []
    var isExpanded: Bool = false
}

// MARK: - Citation

struct RAGCitation: Identifiable, Equatable {
    let id             = UUID()
    let lawId:         Int
    let lawTitle:      String
    let articleNumber: String
    let articleNum:    Int?
    let category:      String
    let content:       String
    var tier: String { category == "司法解释" ? "司法解释" : "法律原文" }
}

// MARK: - Event stream

enum RAGEvent {
    case thinkStep(name: String, content: String)
    case thinkStepWithArticles(name: String, content: String, articles: [RAGCitation])
    case subQuestions([String])
    case token(String)
    case clarifyingQuestion(String)
    case expertsSelected([SubExpert])
}

// MARK: - Message intent

enum MessageIntent: String {
    case caseNarration = "case"
    case followUp      = "follow_up"
    case general       = "general"
    case lawLookup     = "law_lookup"
    case offTopic      = "off_topic"

    var label: String {
        switch self {
        case .caseNarration: return "案情分析"
        case .followUp:      return "追问"
        case .general:       return "法律知识"
        case .lawLookup:     return "法条查询"
        case .offTopic:      return "非法律问题"
        }
    }
}
