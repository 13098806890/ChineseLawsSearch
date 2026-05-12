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
    @Published var isLoading: Bool = false

    private static let fileName = "chat_history.json"

    /// 计算一次并缓存，避免每次调用 FileManager.url(forUbiquityContainerIdentifier:)
    private let fileURL: URL = {
        if let ubiq = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") {
            if !FileManager.default.fileExists(atPath: ubiq.path) {
                try? FileManager.default.createDirectory(at: ubiq, withIntermediateDirectories: true)
            }
            return ubiq.appendingPathComponent(ChatHistoryStore.fileName)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(ChatHistoryStore.fileName)
    }()

    private var metadataQuery: NSMetadataQuery?
    /// Debounce iCloud update notifications to avoid hammering disk on rapid sync events.
    private var reloadWorkItem: DispatchWorkItem?

    init() {
        startICloudQuery()
        loadAsync()
    }

    func save(_ session: ChatSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persistAsync()
    }

    func delete(id: UUID) {
        sessions.removeAll { $0.id == id }
        persistAsync()
    }

    private func loadAsync() {
        isLoading = true
        let url = fileURL
        Task.detached(priority: .userInitiated) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            let decoded = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode([ChatSession].self, from: $0) }
                ?? []
            await MainActor.run {
                self.sessions = decoded
                self.isLoading = false
            }
        }
    }

    /// 异步序列化 + 写文件，不阻塞主线程。
    private func persistAsync() {
        let snapshot = sessions
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // Watch for iCloud updates to the file and reload when it changes remotely.
    private func startICloudQuery() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, Self.fileName)
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: q,
            queue: .main
        ) { [weak self] _ in
            // Debounce: ignore rapid successive iCloud metadata events
            self?.reloadWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.loadAsync() }
            self?.reloadWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }
        q.start()
        metadataQuery = q
    }
}
