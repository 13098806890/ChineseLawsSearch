//
//  LLMProvider.swift
//  ChineseLawsSearch
//

import Foundation

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

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String
    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws
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
    return content
}

private func consumeSSELines(_ bytes: URLSession.AsyncBytes, onToken: @escaping (String) -> Void) async throws {
    for try await line in bytes.lines {
        guard line.hasPrefix("data: ") else { continue }
        let json = String(line.dropFirst(6))
        guard json != "[DONE]",
              let data    = json.data(using: .utf8),
              let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta   = choices.first?["delta"] as? [String: Any],
              let token   = delta["content"] as? String
        else { continue }
        onToken(token)
    }
}

// MARK: - DeepSeek

struct DeepSeekProvider: LLMProvider {
    let id          = "deepseek"
    let displayName = "DeepSeek"
    let modelName   = "deepseek-chat"
    let keychainKey = "deepseek_api_key"
    let keyURL      = URL(string: "https://platform.deepseek.com/api_keys")

    private var apiURL: URL { URL(string: "https://api.deepseek.com/chat/completions")! }

    private func key() throws -> String {
        guard let k = KeychainHelper.load(forKey: keychainKey), !k.isEmpty else {
            throw LLMError.apiKeyMissing(displayName)
        }
        return k
    }

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String {
        let data = try await openAIChat(url: apiURL, apiKey: try key(), providerName: displayName,
                                        model: modelName, messages: messages,
                                        temperature: temperature, stream: false)
        return try extractOpenAIContent(data)
    }

    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws {
        let (bytes, response) = try await openAIStreamBytes(url: apiURL, apiKey: try key(),
                                                            providerName: displayName, model: modelName,
                                                            messages: messages, temperature: temperature)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data(); for try await b in bytes { raw.append(b) }
            throw LLMError.fromHTTP(statusCode: http.statusCode, data: raw, provider: displayName)
        }
        try await consumeSSELines(bytes, onToken: onToken)
    }
}

// MARK: - Groq

struct GroqProvider: LLMProvider {
    let id          = "groq"
    let displayName = "Groq（免费）"
    let modelName   = "llama-3.3-70b-versatile"
    let keychainKey = "groq_api_key"
    let keyURL      = URL(string: "https://console.groq.com/keys")

    private var apiURL: URL { URL(string: "https://api.groq.com/openai/v1/chat/completions")! }

    private func key() throws -> String {
        guard let k = KeychainHelper.load(forKey: keychainKey), !k.isEmpty else {
            throw LLMError.apiKeyMissing(displayName)
        }
        return k
    }

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String {
        let data = try await openAIChat(url: apiURL, apiKey: try key(), providerName: displayName,
                                        model: modelName, messages: messages,
                                        temperature: temperature, stream: false)
        return try extractOpenAIContent(data)
    }

    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws {
        let (bytes, response) = try await openAIStreamBytes(url: apiURL, apiKey: try key(),
                                                            providerName: displayName, model: modelName,
                                                            messages: messages, temperature: temperature)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data(); for try await b in bytes { raw.append(b) }
            throw LLMError.fromHTTP(statusCode: http.statusCode, data: raw, provider: displayName)
        }
        try await consumeSSELines(bytes, onToken: onToken)
    }
}

// MARK: - Gemini (OpenAI-compatible endpoint)

struct GeminiProvider: LLMProvider {
    let id          = "gemini"
    let displayName = "Gemini"
    let modelName   = "gemini-2.0-flash"
    let keychainKey = "gemini_api_key"
    let keyURL      = URL(string: "https://aistudio.google.com/apikey")

    private var apiURL: URL { URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")! }

    private func key() throws -> String {
        guard let k = KeychainHelper.load(forKey: keychainKey), !k.isEmpty else {
            throw LLMError.apiKeyMissing(displayName)
        }
        return k
    }

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String {
        let data = try await openAIChat(url: apiURL, apiKey: try key(), providerName: displayName,
                                        model: modelName, messages: messages,
                                        temperature: temperature, stream: false)
        return try extractOpenAIContent(data)
    }

    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws {
        let (bytes, response) = try await openAIStreamBytes(url: apiURL, apiKey: try key(),
                                                            providerName: displayName, model: modelName,
                                                            messages: messages, temperature: temperature)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data(); for try await b in bytes { raw.append(b) }
            throw LLMError.fromHTTP(statusCode: http.statusCode, data: raw, provider: displayName)
        }
        try await consumeSSELines(bytes, onToken: onToken)
    }
}

// MARK: - Ollama (local)

struct OllamaProvider: LLMProvider {
    let id          = "ollama"
    let displayName = "Ollama（本地）"
    let modelName   = "qwen2.5:3b"
    let keychainKey = ""
    let keyURL: URL? = nil

    private var apiURL: URL { URL(string: "http://localhost:11434/api/chat")! }

    func chat(messages: [[String: Any]], temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": modelName, "stream": false,
            "options": ["temperature": temperature],
            "messages": messages
        ]
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg     = obj["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw URLError(.badServerResponse) }
        return content
    }

    func streamChat(messages: [[String: Any]], temperature: Double, onToken: @escaping (String) -> Void) async throws {
        let body: [String: Any] = [
            "model": modelName, "stream": true,
            "options": ["temperature": temperature],
            "messages": messages
        ]
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180
        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data  = line.data(using: .utf8),
                  let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg   = obj["message"] as? [String: Any],
                  let token = msg["content"] as? String
            else { continue }
            onToken(token)
        }
    }
}

// MARK: - Registry

enum LLMProviderRegistry {
    static let all: [any LLMProvider] = [
        GroqProvider(),
        GeminiProvider(),
        DeepSeekProvider(),
        OllamaProvider()
    ]

    static func provider(id: String) -> (any LLMProvider)? {
        all.first { $0.id == id }
    }

    static var current: any LLMProvider {
        let saved = UserDefaults.standard.string(forKey: "selected_llm_provider") ?? "groq"
        return provider(id: saved) ?? GroqProvider()
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
