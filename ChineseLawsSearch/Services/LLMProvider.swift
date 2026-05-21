//
//  LLMProvider.swift
//  ChineseLawsSearch
//

import Foundation
import Combine

// MARK: - Error

enum LLMError: LocalizedError {
    case apiKeyMissing(String)
    case apiKeyInvalid(String)
    case insufficientBalance(String)
    case rateLimited
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing(let provider):
            return "\(provider) API Key 未配置，请在「设置」中填写。"
        case .apiKeyInvalid(let provider):
            return "\(provider) API Key 无效，请在「设置」中重新填写正确的 Key。"
        case .insufficientBalance(let provider):
            return "\(provider) 账户余额不足，请前往对应平台充值后重试。"
        case .rateLimited:
            return "请求过于频繁，请稍等片刻后再试。"
        case .serverError(let code, let msg):
            return "模型服务异常（\(code)）：\(msg)"
        }
    }
}

// MARK: - Protocol

protocol LLMProvider {
    var id: String { get }
    var displayName: String { get }
    var modelName: String { get }
    var keyURL: URL? { get }
    var keychainKey: String { get }
    var apiURL: URL { get }

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String
    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws
    func apiKey() throws -> String
}

extension LLMProvider {
    func apiKey() throws -> String {
        // API keys are stored device-local (not synced to iCloud).
        // Fall back to the synced store for keys saved by older app versions.
        let k = KeychainHelper.loadLocal(forKey: keychainKey)
            ?? KeychainHelper.load(forKey: keychainKey)
        guard let k, !k.isEmpty else {
            throw LLMError.apiKeyMissing(displayName)
        }
        return k
    }

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String {
        let data = try await openAIChat(url: apiURL, apiKey: try apiKey(), providerName: displayName,
                                        model: modelName, messages: messages,
                                        temperature: temperature, stream: false)
        return try extractOpenAIContent(data)
    }

    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws {
        let (bytes, response) = try await openAIStreamBytes(url: apiURL, apiKey: try apiKey(),
                                                            providerName: displayName, model: modelName,
                                                            messages: messages, temperature: temperature)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data()
            for try await chunk in bytes.lines { raw.append(contentsOf: (chunk + "\n").utf8) }
            throw LLMError.fromHTTP(statusCode: http.statusCode, data: raw, provider: displayName)
        }
        try await consumeSSELines(bytes, onToken: onToken)
    }
}

// MARK: - Token tracking

struct TokenUsage {
    var promptTokens:     Int
    var completionTokens: Int
    var total: Int { promptTokens + completionTokens }
}

@MainActor
final class TokenCounter: ObservableObject {
    static let shared = TokenCounter()
    @Published private(set) var session = TokenUsage(promptTokens: 0, completionTokens: 0)

    func record(_ usage: TokenUsage) { session.promptTokens += usage.promptTokens; session.completionTokens += usage.completionTokens }
    func reset() { session = TokenUsage(promptTokens: 0, completionTokens: 0) }
}

// MARK: - OpenAI-compatible helper (DeepSeek & Gemini share same wire format)

private func openAIChat(
    url: URL, apiKey: String, providerName: String,
    model: String, messages: [[String: Any]], temperature: Double, stream: Bool
) async throws -> Data {
    let body: [String: Any] = [
        "model": model, "stream": stream,
        "temperature": temperature,
        "messages": messages
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = stream ? 120 : 60
    let (data, response) = try await URLSession.shared.data(for: req)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw LLMError.fromHTTP(statusCode: http.statusCode, data: data, provider: providerName)
    }
    return data
}

private func openAIStreamBytes(
    url: URL, apiKey: String, providerName: String,
    model: String, messages: [[String: Any]], temperature: Double
) async throws -> (URLSession.AsyncBytes, URLResponse) {
    let body: [String: Any] = [
        "model": model, "stream": true,
        "stream_options": ["include_usage": true],
        "temperature": temperature,
        "messages": messages
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = 120
    return try await URLSession.shared.bytes(for: req)
}

private func extractOpenAIContent(_ data: Data) throws -> String {
    guard let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = obj["choices"] as? [[String: Any]],
          let msg     = choices.first?["message"] as? [String: Any],
          let content = msg["content"] as? String
    else { throw URLError(.badServerResponse) }
    if let usage    = obj["usage"] as? [String: Any],
       let prompt   = usage["prompt_tokens"]     as? Int,
       let complete = usage["completion_tokens"] as? Int {
        Task { @MainActor in TokenCounter.shared.record(TokenUsage(promptTokens: prompt, completionTokens: complete)) }
    }
    return content
}

private func consumeSSELines(_ bytes: URLSession.AsyncBytes, onToken: @escaping (String) -> Void) async throws {
    for try await line in bytes.lines {
        guard line.hasPrefix("data: ") else { continue }
        let json = String(line.dropFirst(6))
        guard json != "[DONE]",
              let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        // usage-only chunk (choices is empty or absent)
        if let usage    = obj["usage"] as? [String: Any],
           let prompt   = usage["prompt_tokens"]     as? Int,
           let complete = usage["completion_tokens"] as? Int {
            Task { @MainActor in TokenCounter.shared.record(TokenUsage(promptTokens: prompt, completionTokens: complete)) }
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let delta   = choices.first?["delta"] as? [String: Any],
              let token   = delta["content"] as? String
        else { continue }
        onToken(token)
    }
}

// MARK: - DeepSeek (user-key variant — reserved for future "bring your own key" feature)

// Not currently exposed in UI. App always uses BuiltinDeepSeekProvider.
// Re-enable DeepSeekProvider + GroqProvider + GeminiProvider + LLMProviderRegistry.current
// switching logic when user-key settings UI is added back.
struct DeepSeekProvider: LLMProvider {
    let id          = "deepseek"
    let displayName = "DeepSeek"
    let modelName   = "deepseek-chat"
    let keychainKey = "deepseek_api_key"
    let keyURL      = URL(string: "https://platform.deepseek.com/api_keys")
    let apiURL      = URL(string: "https://api.deepseek.com/chat/completions")!
}

// MARK: - BuiltinDeepSeekProvider（免费/付费 agent 使用，不存入 Keychain）

struct BuiltinDeepSeekProvider: LLMProvider {
    let id          = "builtin_deepseek"
    let displayName = "DeepSeek"
    let modelName   = "deepseek-chat"
    let keychainKey = ""
    let keyURL: URL? = nil
    let apiURL      = URL(string: "https://api.deepseek.com/chat/completions")!

    static var hasBuiltinKey: Bool { cachedKey != nil }

    private static let cachedKey: String? = {
        // Parts read from Info.plist (injected via Secrets.xcconfig at build time).
        // If the xcconfig wasn't applied, BKP1 will be absent and we fall back to nil.
        let info = Bundle.main.infoDictionary
        if let p1 = info?["BKP1"] as? String, !p1.isEmpty, !p1.hasPrefix("$"),
           let p2 = info?["BKP2"] as? String, !p2.isEmpty,
           let p3 = info?["BKP3"] as? String, !p3.isEmpty,
           let p4 = info?["BKP4"] as? String, !p4.isEmpty {
            return [p1, p2, p3, p4].joined()
        }
        return nil
    }()

    func apiKey() throws -> String {
        guard let k = Self.cachedKey else {
            throw LLMError.apiKeyMissing(displayName)
        }
        return k
    }
}

// MARK: - Groq (reserved for future multi-provider support)

// Not currently exposed in UI.
struct GroqProvider: LLMProvider {
    let id          = "groq"
    let displayName = "Groq（免费）"
    let modelName   = "llama-3.3-70b-versatile"
    let keychainKey = "groq_api_key"
    let keyURL      = URL(string: "https://console.groq.com/keys")
    let apiURL      = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
}

// Reserved for future use — not currently exposed in UI
struct GeminiProvider: LLMProvider {
    let id          = "gemini"
    let displayName = "Gemini"
    let modelName   = "gemini-2.0-flash"
    let keychainKey = "gemini_api_key"
    let keyURL      = URL(string: "https://aistudio.google.com/apikey")
    let apiURL      = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
}

// MARK: - Registry

enum LLMProviderRegistry {
    static let all: [any LLMProvider] = [
        GroqProvider(),
        GeminiProvider(),
        DeepSeekProvider()
    ]

    static func provider(id: String) -> (any LLMProvider)? {
        all.first { $0.id == id }
    }

    static var current: any LLMProvider {
        let saved = UserDefaults.standard.string(forKey: "selected_llm_provider") ?? "deepseek"
        // If DeepSeek is selected but no user key is configured, use the built-in key.
        if saved == "deepseek" {
            let userKey = KeychainHelper.loadLocal(forKey: "deepseek_api_key")
                ?? KeychainHelper.load(forKey: "deepseek_api_key")
                ?? ""
            if userKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return BuiltinDeepSeekProvider()
            }
        }
        return provider(id: saved) ?? BuiltinDeepSeekProvider()
    }

    /// Agent 功能专用 provider：始终使用内置 Key，不暴露给用户。
    static var agentProvider: any LLMProvider {
        BuiltinDeepSeekProvider()
    }
}

// MARK: - Error helper

extension LLMError {
    static func fromHTTP(statusCode: Int, data: Data, provider: String) -> LLMError {
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
        switch statusCode {
        case 401: return .apiKeyInvalid(provider)
        case 402: return .insufficientBalance(provider)
        case 429: return .rateLimited
        default:  return .serverError(statusCode, msg.isEmpty
                      ? HTTPURLResponse.localizedString(forStatusCode: statusCode) : msg)
        }
    }
}
