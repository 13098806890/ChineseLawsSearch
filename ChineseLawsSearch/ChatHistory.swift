//
//  ChatHistory.swift
//  ChineseLawsSearch
//

import Foundation
import Combine

// MARK: - Codable mirror types

struct PersistedThinkStep: Codable {
    let name: String
    let content: String
    var articles: [PersistedCitation]

    init(name: String, content: String, articles: [PersistedCitation] = []) {
        self.name = name; self.content = content; self.articles = articles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name     = try c.decode(String.self, forKey: .name)
        content  = try c.decode(String.self, forKey: .content)
        articles = (try? c.decodeIfPresent([PersistedCitation].self, forKey: .articles)) ?? []
    }
}

struct PersistedCitation: Codable {
    let lawId: Int
    let lawTitle: String
    let articleNumber: String
    let articleNum: Int?
    let category: String
    let content: String
}

struct PersistedMessage: Codable {
    let role: String        // "user" | "assistant"
    var text: String
    var thinkSteps: [PersistedThinkStep]
    var citations: [PersistedCitation]
    var subQuestions: [String]
    var isClarifying: Bool

    init(role: String, text: String, thinkSteps: [PersistedThinkStep] = [],
         citations: [PersistedCitation] = [], subQuestions: [String] = [],
         isClarifying: Bool = false) {
        self.role = role; self.text = text; self.thinkSteps = thinkSteps
        self.citations = citations; self.subQuestions = subQuestions
        self.isClarifying = isClarifying
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role         = try c.decode(String.self, forKey: .role)
        text         = try c.decode(String.self, forKey: .text)
        thinkSteps   = (try? c.decodeIfPresent([PersistedThinkStep].self, forKey: .thinkSteps)) ?? []
        citations    = (try? c.decodeIfPresent([PersistedCitation].self, forKey: .citations)) ?? []
        subQuestions = (try? c.decodeIfPresent([String].self, forKey: .subQuestions)) ?? []
        isClarifying = (try? c.decodeIfPresent(Bool.self, forKey: .isClarifying)) ?? false
    }
}

// MARK: - Session

struct ChatSession: Identifiable, Codable {
    var id: UUID
    var title: String       // first user message truncated
    var mode: String        // "rag" | "expert"
    var createdAt: Date
    var updatedAt: Date
    var messages: [PersistedMessage]

    // 专家追问上下文（按 name 存储，loadSession 时反查 SubExpert）
    var selectedExpertNames: [String]
    var pendingFacts: [String: String]
    var isAwaitingClarification: Bool
    var followUpRound: Int

    // Token 累计统计
    var totalPromptTokens: Int
    var totalCompletionTokens: Int

    init(id: UUID, title: String, mode: String, createdAt: Date, updatedAt: Date,
         messages: [PersistedMessage],
         selectedExpertNames: [String] = [],
         pendingFacts: [String: String] = [:],
         isAwaitingClarification: Bool = false,
         followUpRound: Int = 0,
         totalPromptTokens: Int = 0,
         totalCompletionTokens: Int = 0) {
        self.id = id; self.title = title; self.mode = mode
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.messages = messages
        self.selectedExpertNames = selectedExpertNames
        self.pendingFacts = pendingFacts
        self.isAwaitingClarification = isAwaitingClarification
        self.followUpRound = followUpRound
        self.totalPromptTokens = totalPromptTokens
        self.totalCompletionTokens = totalCompletionTokens
    }
}

// MARK: - Store

final class ChatHistoryStore: ObservableObject {
    @Published var sessions: [ChatSession] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("chat_history.json")
    }()

    init() { load() }

    func save(_ session: ChatSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persist()
    }

    func delete(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
