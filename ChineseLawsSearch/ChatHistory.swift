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
}

// MARK: - Session

struct ChatSession: Identifiable, Codable {
    var id: UUID
    var title: String       // first user message truncated
    var mode: String        // "rag" | "expert"
    var createdAt: Date
    var updatedAt: Date
    var messages: [PersistedMessage]
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
