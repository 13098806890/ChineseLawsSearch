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
    var gazetteCitations: [GazetteCitation]

    init(name: String, content: String, articles: [PersistedCitation] = [], gazetteCitations: [GazetteCitation] = []) {
        self.name = name; self.content = content; self.articles = articles; self.gazetteCitations = gazetteCitations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name             = try c.decode(String.self, forKey: .name)
        content          = try c.decode(String.self, forKey: .content)
        articles         = (try? c.decodeIfPresent([PersistedCitation].self, forKey: .articles)) ?? []
        gazetteCitations = (try? c.decodeIfPresent([GazetteCitation].self, forKey: .gazetteCitations)) ?? []
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
    var gazetteCitations: [GazetteCitation]

    init(role: String, text: String, thinkSteps: [PersistedThinkStep] = [],
         citations: [PersistedCitation] = [], subQuestions: [String] = [],
         isClarifying: Bool = false, gazetteCitations: [GazetteCitation] = []) {
        self.role = role; self.text = text; self.thinkSteps = thinkSteps
        self.citations = citations; self.subQuestions = subQuestions
        self.isClarifying = isClarifying; self.gazetteCitations = gazetteCitations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role             = try c.decode(String.self, forKey: .role)
        text             = try c.decode(String.self, forKey: .text)
        thinkSteps       = (try? c.decodeIfPresent([PersistedThinkStep].self, forKey: .thinkSteps)) ?? []
        citations        = (try? c.decodeIfPresent([PersistedCitation].self, forKey: .citations)) ?? []
        subQuestions     = (try? c.decodeIfPresent([String].self, forKey: .subQuestions)) ?? []
        isClarifying     = (try? c.decodeIfPresent(Bool.self, forKey: .isClarifying)) ?? false
        gazetteCitations = (try? c.decodeIfPresent([GazetteCitation].self, forKey: .gazetteCitations)) ?? []
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
    var lastQueryMode: String?   // QueryMode.rawValue，追问时恢复

    // Token 累计统计
    var totalPromptTokens: Int
    var totalCompletionTokens: Int

    init(id: UUID, title: String, mode: String, createdAt: Date, updatedAt: Date,
         messages: [PersistedMessage],
         selectedExpertNames: [String] = [],
         pendingFacts: [String: String] = [:],
         isAwaitingClarification: Bool = false,
         followUpRound: Int = 0,
         lastQueryMode: String? = nil,
         totalPromptTokens: Int = 0,
         totalCompletionTokens: Int = 0) {
        self.id = id; self.title = title; self.mode = mode
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.messages = messages
        self.selectedExpertNames = selectedExpertNames
        self.pendingFacts = pendingFacts
        self.isAwaitingClarification = isAwaitingClarification
        self.followUpRound = followUpRound
        self.lastQueryMode = lastQueryMode
        self.totalPromptTokens = totalPromptTokens
        self.totalCompletionTokens = totalCompletionTokens
    }
}

// MARK: - Persist actor (serializes all disk I/O, preventing concurrent-write races)

private actor PersistActor {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
    func read(from url: URL) -> Data? {
        try? Data(contentsOf: url)
    }
}

// MARK: - Store

final class ChatHistoryStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var isLoading: Bool = false

    private static let fileName    = "chat_history.json"
    /// Keep at most this many sessions to bound storage and memory.
    private static let maxSessions = 200

    /// Resolved once and cached — avoids repeated FileManager calls on every read/write.
    private lazy var fileURL: URL = {
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

    private let persistActor = PersistActor()
    private var metadataQuery: NSMetadataQuery?
    private var metadataObserver: NSObjectProtocol?
    /// Debounce iCloud update notifications to avoid hammering disk on rapid sync events.
    private var reloadWorkItem: DispatchWorkItem?

    init() {
        startICloudQuery()
        loadAsync()
    }

    deinit {
        metadataQuery?.stop()
        if let obs = metadataObserver { NotificationCenter.default.removeObserver(obs) }
    }

    @MainActor
    func save(_ session: ChatSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
            // Prune oldest sessions beyond the cap
            if sessions.count > Self.maxSessions {
                sessions = Array(sessions.prefix(Self.maxSessions))
            }
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
        let actor = persistActor
        Task.detached(priority: .userInitiated) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            let data = await actor.read(from: url)
            var decoded: [ChatSession] = []
            if let d = data {
                do {
                    decoded = try JSONDecoder().decode([ChatSession].self, from: d)
                } catch {
                    print("[ChatHistory] JSON decode failed: \(error). Moving corrupted file to backup.")
                    let backupURL = url.deletingLastPathComponent()
                        .appendingPathComponent("sessions_backup.json")
                    try? FileManager.default.removeItem(at: backupURL)
                    try? FileManager.default.moveItem(at: url, to: backupURL)
                    decoded = []
                }
            }
            let result = decoded
            await MainActor.run {
                self.sessions = result
                self.isLoading = false
            }
        }
    }

    /// 序列化写文件，通过 PersistActor 保证同一时刻只有一个写操作。
    private func persistAsync() {
        let snapshot = sessions
        let url = fileURL
        let actor = persistActor
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? await actor.write(data, to: url)
        }
    }

    // Watch for iCloud updates to the file and reload when it changes remotely.
    private func startICloudQuery() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, Self.fileName)
        metadataObserver = NotificationCenter.default.addObserver(
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
