//
//  LegalRAGService.swift
//  ChineseLawsSearch
//
//  多步 RAG pipeline，对应 Python test_rag.py 的逻辑。
//  调用本地 Ollama（http://localhost:11434）。
//

import Foundation

// MARK: - Data types

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var citations: [RAGCitation] = []
}

struct RAGCitation: Identifiable, Equatable {
    let id = UUID()
    let lawTitle: String
    let articleNumber: String
    let category: String
    let content: String
    var tier: String { category == "司法解释" ? "司法解释" : "法律原文" }
}

// MARK: - Service

@MainActor
final class LegalRAGService: ObservableObject {
    static let shared = LegalRAGService()

    private let ollamaURL = URL(string: "http://localhost:11434/api/chat")!
    private let model = "qwen2.5:3b"

    private let allDomains = [
        "宪法相关法", "民法典", "民法商法", "刑法",
        "行政法", "经济法", "社会法", "诉讼与非诉讼程序法"
    ]
    private let lawCategories    = ["法律", "宪法", "修正案", "法律解释", "监察法规"]
    private let interpCategories = ["司法解释"]

    // MARK: Public entry point

    func ask(question: String, onToken: @escaping (String) -> Void) async throws -> [RAGCitation] {
        // Step 1: 分类路由
        let domains = await classifyDomains(question: question)

        // Step 2: 关键词提取
        var keywords = await extractKeywords(question: question)
        guard !keywords.isEmpty else {
            onToken("无法提取关键词，请换一种方式提问。")
            return []
        }

        // Step 2.5: 别名扩展 + topic hints
        let expanded = expandKeywords(keywords)
        let hintLaws = DatabaseManager.shared.topicLawHints(for: expanded)

        // Step 3+4: 分层检索
        var articles = searchLayered(keywords: expanded, domains: domains, hintLaws: hintLaws)

        // 兜底：结果太少则全域重搜
        let total = articles.laws.count + articles.interps.count
        if total <= 3 {
            articles = searchLayered(keywords: expanded, domains: allDomains, hintLaws: hintLaws)
        }

        // Step 4.5: 相关性过滤（pinned 跳过）
        articles = await filterArticles(question: question, articles: articles)

        // Step 5: 生成回答（流式）
        let context = buildContext(articles)
        guard !context.isEmpty else {
            onToken("未检索到相关条文，无法回答。")
            return []
        }

        let userMsg = "以下是检索到的法律条文：\n\n\(context)\n\n用户问题：\(question)"
        try await streamChat(system: answerPrompt, user: userMsg, onToken: onToken)

        // Step 6: 参考法条筛选
        let allItems = articles.laws + articles.interps
        let pinned   = allItems.filter { $0.pinned }
        let others   = allItems.filter { !$0.pinned }
        let candidates = Array((pinned + others).prefix(10))
        let cited = await filterCitations(question: question, candidates: candidates)
        return cited.map {
            RAGCitation(lawTitle: $0.lawTitle, articleNumber: $0.articleNumber,
                        category: $0.category, content: $0.content)
        }
    }

    // MARK: Step 1 — 分类路由

    private func classifyDomains(question: String) async -> [String] {
        let prompt = """
        你是中国法律分类专家。从8个法律部门中排除与问题明显无关的部门。

        8个部门：宪法相关法、民法典、民法商法、刑法、行政法、经济法、社会法、诉讼与非诉讼程序法

        规则：
        - 宁可多保留，不要错误排除
        - 问题涉及"去哪个法院""如何起诉""诉讼请求""管辖" → 必须保留「诉讼与非诉讼程序法」

        只输出 JSON：{"relevant":["部门1","部门2"],"excluded":["部门3"]}
        """
        guard let raw = try? await chat(system: prompt, user: "问题：\(question)"),
              let data = extractJSON(raw, open: "{", close: "}").data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
              let relevant = obj["relevant"], !relevant.isEmpty
        else { return allDomains }
        return relevant.filter { allDomains.contains($0) }
    }

    // MARK: Step 2 — 关键词提取

    private func extractKeywords(question: String) async -> [String] {
        let prompt = """
        你是中国法律检索专家。从问题中提取适合检索法律条文的关键词。
        要求：每个关键词2-6个汉字，法律专业术语，输出4-8个，从核心到次要排列。
        只输出JSON数组，不要其他内容。
        """
        guard let raw = try? await chat(system: prompt, user: "问题：\(question)"),
              let data = extractJSON(raw, open: "[", close: "]").data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr.filter { $0.count >= 2 && $0.count <= 8 }
    }

    // MARK: Step 2.5 — 别名扩展

    private func expandKeywords(_ keywords: [String]) -> [String] {
        var expanded = keywords
        var seen = Set(keywords)
        for kw in keywords {
            for term in DatabaseManager.shared.legalTerms(for: kw) where seen.insert(term).inserted {
                expanded.append(term)
            }
            for syn in DatabaseManager.shared.synonyms(for: kw) where seen.insert(syn).inserted {
                expanded.append(syn)
            }
        }
        return expanded
    }

    // MARK: Step 3+4 — 分层检索

    private struct ArticleBag {
        var laws:   [DatabaseManager.RAGArticle] = []
        var interps: [DatabaseManager.RAGArticle] = []
    }

    private func searchLayered(keywords: [String], domains: [String],
                                hintLaws: [String]) -> ArticleBag {
        let db = DatabaseManager.shared
        var seen = Set<Int>()
        var bag  = ArticleBag()

        func addToBag(_ a: DatabaseManager.RAGArticle) {
            guard seen.insert(a.nodeId).inserted else { return }
            if a.category == "司法解释" { bag.interps.append(a) }
            else { bag.laws.append(a) }
        }

        // hint laws — 关键词按 FTS 命中数升序（精确词优先）
        if !hintLaws.isEmpty {
            let sorted = keywords
                .filter { kw in kw.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count >= 3 }
                .sorted { db.ftsHitCount(keyword: $0) < db.ftsHitCount(keyword: $1) }
            for kw in sorted {
                for title in hintLaws {
                    for a in db.ftsSearchInLaw(keyword: kw, lawTitle: title,
                                               categories: lawCategories + interpCategories) {
                        addToBag(a)
                    }
                }
            }
        }

        // 普通检索
        for kw in keywords {
            for a in db.ftsSearch(keyword: kw, domains: domains, categories: lawCategories) {
                addToBag(a)
            }
        }
        for kw in keywords {
            for a in db.ftsSearch(keyword: kw, domains: domains, categories: interpCategories) {
                addToBag(a)
            }
        }
        return bag
    }

    // MARK: Step 4.5 — 相关性过滤

    private func filterArticles(question: String, articles: ArticleBag) async -> ArticleBag {
        let filterPrompt = """
        你是中国法律审核专家。逐条判断每条法律条文是否与用户问题直接相关。
        对每条条文只回答 Y（相关）或 N（不相关）。宁可多保留，不要错误排除。
        输出格式每行：0: Y
        不要其他内容。
        """
        let pinned     = (articles.laws + articles.interps).filter { $0.pinned }
        let toFilter   = (articles.laws + articles.interps).filter { !$0.pinned }
        var kept       = pinned
        let keptIds    = Set(pinned.map { $0.nodeId })

        let batchSize  = 8
        for start in stride(from: 0, to: toFilter.count, by: batchSize) {
            let batch   = Array(toFilter[start ..< min(start + batchSize, toFilter.count)])
            let numbered = batch.enumerated().map { i, a in
                "[\(i)] 《\(a.lawTitle)》\(a.articleNumber)：\(String(a.content.prefix(150)))"
            }.joined(separator: "\n")
            let user = "用户问题：\(question)\n\n法律条文列表：\n\(numbered)"
            guard let raw = try? await chat(system: filterPrompt, user: user) else {
                kept += batch; continue
            }
            var verdicts: [Int: Bool] = [:]
            for line in raw.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, let idx = Int(parts[0].trimmingCharacters(in: CharacterSet.whitespaces)) {
                    verdicts[idx] = String(parts[1]).trimmingCharacters(in: CharacterSet.whitespaces).uppercased().hasPrefix("Y")
                }
            }
            kept += batch.enumerated().compactMap { i, a in verdicts[i] == false ? nil : a }
        }

        if kept.isEmpty { kept = articles.laws + articles.interps }
        let lawIds = Set(articles.laws.map { $0.nodeId })
        return ArticleBag(
            laws:   kept.filter { lawIds.contains($0.nodeId) },
            interps: kept.filter { !lawIds.contains($0.nodeId) }
        )
    }

    // MARK: Build context

    private func buildContext(_ articles: ArticleBag, max: Int = 20) -> String {
        let all = (articles.laws + articles.interps)
        var seen = Set<Int>()
        var deduped: [DatabaseManager.RAGArticle] = []
        let pinned = all.filter { $0.pinned }
        let others = all.filter { !$0.pinned }
        for a in pinned + others {
            if seen.insert(a.nodeId).inserted { deduped.append(a) }
        }
        let selected = Array(deduped.prefix(max))
        let lawItems   = selected.filter { $0.category != "司法解释" }
        let interpItems = selected.filter { $0.category == "司法解释" }

        var parts: [String] = []
        if !lawItems.isEmpty {
            parts.append("【法律原文】")
            parts += lawItems.map { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(500)))" }
        }
        if !interpItems.isEmpty {
            parts.append("\n【司法解释】")
            parts += interpItems.map { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(500)))" }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: Step 6 — 参考法条筛选

    private func filterCitations(question: String,
                                  candidates: [DatabaseManager.RAGArticle]) async -> [DatabaseManager.RAGArticle] {
        let citePrompt = """
        你是中国法律助手。判断以下法律条文是否应作为参考法条展示给用户。
        只有当该条文直接支撑结论或用户可据此行动时，才回答 Y。
        Y：条文规定用户可主张的权利/赔偿/合同解除权，或规定对方义务/违约后果。
        N：行政监管要求、定义性条款、与用户问题无直接关系的条文。
        只输出 Y 或 N，不要其他内容。
        """
        var kept: [DatabaseManager.RAGArticle] = []
        for a in candidates {
            let user = "用户问题：\(question)\n\n法律条文：《\(a.lawTitle)》\(a.articleNumber)：\(String(a.content.prefix(300)))"
            let verdict = (try? await chat(system: citePrompt, user: user))?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "Y"
            if verdict.hasPrefix("Y") { kept.append(a) }
        }
        return kept
    }

    // MARK: Ollama helpers

    private func chat(system: String, user: String) async throws -> String {
        let body: [String: Any] = [
            "model": model, "stream": false,
            "options": ["temperature": 0.05],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user],
            ]
        ]
        var req = URLRequest(url: ollamaURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw URLError(.badServerResponse) }
        return content
    }

    private func streamChat(system: String, user: String, onToken: @escaping (String) -> Void) async throws {
        let body: [String: Any] = [
            "model": model, "stream": true,
            "options": ["temperature": 0.1],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user],
            ]
        ]
        var req = URLRequest(url: ollamaURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180

        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg  = obj["message"] as? [String: Any],
                  let token = msg["content"] as? String
            else { continue }
            onToken(token)
        }
    }

    // MARK: Prompts

    private var answerPrompt: String { """
    你是中国法律助手。严格根据提供的法律条文回答问题。

    只输出结论文字，不要加"【结论】"标题，不要输出任何法条。
    用2-5句话直接回答用户问题，说明当事人的权利和可采取的行动。语言通俗易懂。
    若用户问了多个问题，每个都要回答。可以提及具体赔偿倍数（如十倍、三倍）。
    不得出现"依据第X条"等引用格式。

    ---
    诉讼相关通用知识（无需法条支撑，直接使用）：

    【管辖法院】
    - 合同纠纷：被告住所地 或 合同履行地 法院
    - 房屋租赁纠纷：房屋所在地法院（不动产专属管辖）
    - 劳动争议：先申请劳动仲裁，再向劳动关系所在地法院起诉
    - 侵权纠纷：侵权行为地 或 被告住所地 法院
    - 离婚诉讼：被告住所地法院；被告下落不明时原告住所地法院

    【诉讼请求模板】
    - 返还金钱：请求判令被告返还[押金/货款/工资]XX元
    - 解除合同：请求判令解除[租赁/劳动/买卖]合同
    - 赔偿损失：请求判令被告赔偿[经济损失/违约金]XX元
    - 食品安全索赔：请求判令被告支付价款十倍赔偿金（食品安全法第148条；不足1000元按1000元计）
    - 消费欺诈索赔：请求判令被告支付价款三倍赔偿金（消费者权益保护法第55条；不足500元按500元计）

    【诉讼费用】
    - 财产类案件按标的额阶梯收费，1万元以下收50元
    - 一般由败诉方承担
    """ }

    // MARK: Util

    private func extractJSON(_ s: String, open: String, close: String) -> String {
        guard let start = s.range(of: open)?.lowerBound,
              let end   = s.range(of: close, options: .backwards)?.upperBound
        else { return s }
        return String(s[start ..< end])
    }
}
