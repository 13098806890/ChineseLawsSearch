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
    var gazetteCitations: [GazetteCitation] = []
    var subQuestions: [String]   = []
    var isClarifying: Bool       = false
    var subQuestionIndex: Int?   = nil
    var showSteps: Bool               = true
    var showCitations: Bool           = false
    var showGazetteCitations: Bool    = false
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

// MARK: - Gongbao citation (公报案例引用)

struct GazetteCitation: Identifiable, Codable, Equatable {
    var id: Int           { docId }
    let docId: Int
    let source: String
    let title: String
    let rulingGist: String
    let strategy: String        // "fts" | "keywords" | "lawlinks" | "note"
    let relevanceReason: String // LLM 给的一句话原因（未经筛选时为空）
}

// MARK: - Event stream

enum RAGEvent {
    case thinkStep(name: String, content: String)
    case thinkStepWithArticles(name: String, content: String, articles: [RAGCitation])
    case subQuestions([String])
    case token(String)
    case clarifyingQuestion(String)
    case expertsSelected([SubExpert])
    case gazetteCitations([GazetteCitation])
}

// MARK: - Message intent

enum MessageIntent: String {
    case legalQuery = "legal_query"
    case followUp   = "follow_up"
    case offTopic   = "off_topic"

    var label: String {
        switch self {
        case .legalQuery: return "法律咨询"
        case .followUp:   return "追问"
        case .offTopic:   return "非法律问题"
        }
    }
}

// MARK: - Query mode (resolved after intent = legalQuery)

enum QueryMode: String {
    case caseAnalysis      = "case"       // 案情分析：有具体事实，需追问，给策略建议
    case legalAdvisory     = "advisory"   // 法律咨询：假设场景，给一般性权利义务结论
    case conceptAndStatute = "statute"    // 概念/法条：解释定义或检索原文，不评价案情
    case gongbaoSearch     = "gongbao"   // 公报案例检索：直接查指导案例/裁判文书/司法文件

    var label: String {
        switch self {
        case .caseAnalysis:      return "案情分析"
        case .legalAdvisory:     return "法律咨询"
        case .conceptAndStatute: return "法条检索"
        case .gongbaoSearch:     return "公报案例检索"
        }
    }
}
