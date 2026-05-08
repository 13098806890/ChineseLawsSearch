//
//  LegalRAGService.swift
//  ChineseLawsSearch
//

import Foundation

// MARK: - Public data types

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
    var intent: MessageIntent?   = nil  // set on assistant messages

    init(role: Role, text: String = "", isClarifying: Bool = false) {
        self.role = role
        self.text = text
        self.isClarifying = isClarifying
    }
}

struct ThinkStep: Identifiable, Equatable {
    let id    = UUID()
    let name:    String
    let content: String
    var articles: [RAGCitation] = []
    var isExpanded: Bool = false
}

struct RAGCitation: Identifiable, Equatable {
    let id            = UUID()
    let lawId:        Int
    let lawTitle:     String
    let articleNumber: String
    let articleNum:   Int?       // 用于跳转滚动定位
    let category:     String
    let content:      String
    var tier: String { category == "司法解释" ? "司法解释" : "法律原文" }
}

enum RAGEvent {
    case thinkStep(name: String, content: String)
    case thinkStepWithArticles(name: String, content: String, articles: [RAGCitation])
    case subQuestions([String])
    case token(String)
    case clarifyingQuestion(String)   // expert asking user for more info
    case expertsSelected([SubExpert]) // notifies ViewModel which experts were chosen
}

// MARK: - Message intent

enum MessageIntent: String {
    case caseNarration = "case"      // 陈述案情 → 完整专家流程
    case followUp      = "follow_up" // 追问 → 复用上次专家，携带 history
    case general       = "general"   // 法律知识 → LLM 决策路径
    case offTopic      = "off_topic" // 闲聊 → hardcoded 引导语

    var label: String {
        switch self {
        case .caseNarration: return "案情分析"
        case .followUp:      return "追问"
        case .general:       return "法律知识"
        case .offTopic:      return "非法律问题"
        }
    }
}

// MARK: - Service

final class LegalRAGService {
    static let shared = LegalRAGService()

    private let allDomains = [
        "宪法相关法", "民法典", "民法商法", "刑法",
        "行政法", "经济法", "社会法", "诉讼与非诉讼程序法"
    ]
    private let lawCategories    = ["法律", "宪法", "修正案", "法律解释", "监察法规"]
    private let interpCategories = ["司法解释"]

    // MARK: - Entry point

    func ask(question: String, onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {

        // Step 0: 拆分问题
        let subQs = await decomposeQuestion(question)
        onEvent(.thinkStep(name: "拆分问题",
                           content: subQs.isEmpty
                               ? "问题无需拆分，直接回答。"
                               : subQs.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")))
        if !subQs.isEmpty { onEvent(.subQuestions(subQs)) }

        // Step 1: 领域路由（基于原问题）
        let domains = await classifyDomains(question: question)
        onEvent(.thinkStep(name: "领域路由",
                           content: "相关领域：\(domains.joined(separator: "、"))"))

        // Step 2: 关键词提取（合并所有子问题）
        let allQuestions = subQs.isEmpty ? [question] : ([question] + subQs)
        var allKeywords: [String] = []
        var kwSet = Set<String>()
        for q in allQuestions {
            for kw in try await extractKeywords(question: q) where kwSet.insert(kw).inserted {
                allKeywords.append(kw)
            }
        }
        if allKeywords.isEmpty {
            onEvent(.token("未能从问题中提取到法律关键词，请尝试更具体地描述您的法律问题。"))
            return []
        }
        onEvent(.thinkStep(name: "关键词提取",
                           content: allKeywords.joined(separator: "、")))

        // Step 2.5: 别名扩展
        let expanded = expandKeywords(allKeywords)
        let hintLaws = DatabaseManager.shared.topicLawHints(for: expanded)
        let addedCount = expanded.count - allKeywords.count
        var expandDetail = addedCount > 0
            ? "扩展 +\(addedCount) 词：\(expanded.dropFirst(allKeywords.count).joined(separator: "、"))"
            : "无扩展词"
        if !hintLaws.isEmpty {
            expandDetail += "\n优先法律：\(hintLaws.joined(separator: "、"))"
        }
        onEvent(.thinkStep(name: "别名扩展", content: expandDetail))

        // Step 3+4: 分层检索
        var articles = searchLayered(keywords: expanded, domains: domains, hintLaws: hintLaws)
        if articles.laws.count + articles.interps.count <= 3 {
            articles = searchLayered(keywords: expanded, domains: allDomains, hintLaws: hintLaws)
        }
        let pinnedCount = (articles.laws + articles.interps).filter { $0.pinned }.count
        let retrievedCitations = (articles.laws + articles.interps).map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle, articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum, category: $0.category, content: $0.content)
        }
        onEvent(.thinkStepWithArticles(
            name: "检索条文",
            content: "找到 \(articles.laws.count) 条法律原文、\(articles.interps.count) 条司法解释（含 \(pinnedCount) 条优先命中）",
            articles: retrievedCitations))

        // Step 4.5: 相关性过滤
        let beforeTotal = articles.laws.count + articles.interps.count
        articles = await filterArticles(question: question, articles: articles)
        let afterTotal  = articles.laws.count + articles.interps.count
        onEvent(.thinkStep(name: "相关性过滤",
                           content: "保留 \(afterTotal) 条（过滤 \(beforeTotal - afterTotal) 条）"))

        // Step 5: 生成回答（流式）
        let maxCtx  = UserDefaults.standard.integer(forKey: "maxContextArticles")
        let context = buildContext(articles, max: maxCtx > 0 ? maxCtx : 20)
        guard !context.isEmpty else {
            onEvent(.token("未检索到相关条文，无法回答。"))
            return []
        }

        // 逐一回答子问题，或直接回答
        if subQs.isEmpty {
            let userMsg = "以下是检索到的法律条文：\n\n\(context)\n\n用户问题：\(question)"
            try await streamChat(system: answerPrompt, user: userMsg, onToken: { onEvent(.token($0)) })
        } else {
            for (i, sq) in subQs.enumerated() {
                if i > 0 { onEvent(.token("\n\n")) }
                onEvent(.token("**\(i+1). \(sq)**\n"))
                let userMsg = "以下是检索到的法律条文：\n\n\(context)\n\n请只回答这个子问题（简洁2-3句）：\(sq)"
                try await streamChat(system: answerPrompt, user: userMsg, onToken: { onEvent(.token($0)) })
            }
        }

        // Step 6: 参考法条筛选
        let allItems   = articles.laws + articles.interps
        let pinned     = allItems.filter { $0.pinned }
        let others     = allItems.filter { !$0.pinned }
        let maxCit     = UserDefaults.standard.integer(forKey: "maxCitations")
        let candidates = maxCit > 0 ? Array((pinned + others).prefix(maxCit)) : (pinned + others)
        let cited      = await filterCitations(question: question, candidates: candidates)
        onEvent(.thinkStep(name: "参考法条筛选",
                           content: "从 \(candidates.count) 条候选中筛出 \(cited.count) 条直接相关法条"))
        return cited.map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle, articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum, category: $0.category, content: $0.content)
        }
    }

    // MARK: - Step 0 — 拆分问题

    private func decomposeQuestion(_ question: String) async -> [String] {
        let prompt = """
        你是中国法律助手。判断用户的问题是否包含多个独立的法律子问题（如同时涉及请求权和诉讼程序，或多个不同法律关系）。
        如果问题简单或只有一个核心问题，输出空数组 []。
        如果可以拆分，输出2-4个子问题的JSON数组，每个子问题都需要包含详细的上下文。
        只输出JSON数组，不要其他内容。
        """
        guard let raw = try? await chat(system: prompt, user: "问题：\(question)"),
              let data = extractJSON(stripMarkdownFence(raw), open: "[", close: "]").data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String],
              arr.count >= 2
        else { return [] }
        return arr.filter { !$0.isEmpty }
    }

    // MARK: - Step 1 — 领域路由

    private func classifyDomains(question: String) async -> [String] {
        let prompt = """
        你是中国法律分类专家。从8个法律部门中排除与问题明显无关的部门。宁可多保留，不要错误排除。
        问题涉及"去哪个法院""如何起诉""诉讼请求""管辖" → 必须保留「诉讼与非诉讼程序法」
        只输出JSON：{"relevant":["部门1"],"excluded":["部门2"]}
        8个部门：宪法相关法、民法典、民法商法、刑法、行政法、经济法、社会法、诉讼与非诉讼程序法
        """
        guard let raw = try? await chat(system: prompt, user: "问题：\(question)"),
              let data = extractJSON(stripMarkdownFence(raw), open: "{", close: "}").data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
              let rel  = obj["relevant"], !rel.isEmpty
        else { return allDomains }
        return rel.filter { allDomains.contains($0) }
    }

    // MARK: - Step 2 — 关键词提取

    private func extractKeywords(question: String) async throws -> [String] {
        let prompt = """
        你是中国法律检索专家。从问题中提取适合检索法律条文的关键词。
        每个关键词2-6个汉字，法律专业术语，输出4-8个，从核心到次要排列。只输出JSON数组。
        """
        let raw  = try await chat(system: prompt, user: "问题：\(question)")
        let json = extractJSON(stripMarkdownFence(raw), open: "[", close: "]")
        guard let data = json.data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr.filter { !$0.isEmpty && $0.count >= 2 && $0.count <= 12 }
    }

    // MARK: - Step 2.5 — 别名扩展

    private func expandKeywords(_ keywords: [String]) -> [String] {
        var expanded = keywords
        var seen = Set(keywords)
        for kw in keywords {
            for t in DatabaseManager.shared.legalTerms(for: kw) where seen.insert(t).inserted { expanded.append(t) }
            for s in DatabaseManager.shared.synonyms(for: kw)    where seen.insert(s).inserted { expanded.append(s) }
        }
        return expanded
    }

    // MARK: - Step 3+4 — 分层检索

    private struct ArticleBag {
        var laws:    [DatabaseManager.RAGArticle] = []
        var interps: [DatabaseManager.RAGArticle] = []
    }

    private func searchLayered(keywords: [String], domains: [String], hintLaws: [String]) -> ArticleBag {
        let db = DatabaseManager.shared
        var seen = Set<Int>()
        var bag  = ArticleBag()

        func add(_ a: DatabaseManager.RAGArticle) {
            guard seen.insert(a.nodeId).inserted else { return }
            if a.category == "司法解释" { bag.interps.append(a) } else { bag.laws.append(a) }
        }

        if !hintLaws.isEmpty {
            let sorted = keywords
                .filter { $0.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count >= 3 }
                .sorted { db.ftsHitCount(keyword: $0) < db.ftsHitCount(keyword: $1) }
            for kw in sorted {
                for title in hintLaws {
                    db.ftsSearchInLaw(keyword: kw, lawTitle: title, categories: lawCategories + interpCategories).forEach { add($0) }
                }
            }
        }
        for kw in keywords { db.ftsSearch(keyword: kw, domains: domains, categories: lawCategories).forEach    { add($0) } }
        for kw in keywords { db.ftsSearch(keyword: kw, domains: domains, categories: interpCategories).forEach { add($0) } }
        return bag
    }

    // MARK: - Step 4.5 — 相关性过滤

    private func filterArticles(question: String, articles: ArticleBag) async -> ArticleBag {
        let filterPrompt = """
        你是中国法律审核专家。逐条判断每条法律条文是否与用户问题直接相关。
        对每条只回答 Y 或 N。宁可多保留，不要错误排除。
        输出格式每行：0: Y    不要其他内容。
        """
        let pinned   = (articles.laws + articles.interps).filter {  $0.pinned }
        let toFilter = (articles.laws + articles.interps).filter { !$0.pinned }
        var kept     = pinned

        for start in stride(from: 0, to: toFilter.count, by: 8) {
            let batch    = Array(toFilter[start ..< min(start+8, toFilter.count)])
            let numbered = batch.enumerated().map { "[\($0)] 《\($1.lawTitle)》\($1.articleNumber)：\(String($1.content.prefix(150)))" }.joined(separator: "\n")
            guard let raw = try? await chat(system: filterPrompt, user: "用户问题：\(question)\n\n\(numbered)") else { kept += batch; continue }
            var v: [Int: Bool] = [:]
            for line in raw.split(separator: "\n") {
                let p = line.split(separator: ":", maxSplits: 1)
                if p.count == 2, let idx = Int(p[0].trimmingCharacters(in: .whitespaces)) {
                    v[idx] = String(p[1]).trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("Y")
                }
            }
            kept += batch.enumerated().compactMap { i, a in v[i] == false ? nil : a }
        }

        if kept.isEmpty { kept = articles.laws + articles.interps }
        let lawIds = Set(articles.laws.map { $0.nodeId })
        return ArticleBag(laws: kept.filter { lawIds.contains($0.nodeId) },
                          interps: kept.filter { !lawIds.contains($0.nodeId) })
    }

    // MARK: - Build context

    private func buildContext(_ articles: ArticleBag, max: Int = 20) -> String {
        var seen = Set<Int>()
        var deduped: [DatabaseManager.RAGArticle] = []
        let all = articles.laws + articles.interps
        for a in (all.filter { $0.pinned } + all.filter { !$0.pinned }) {
            if seen.insert(a.nodeId).inserted { deduped.append(a) }
        }
        let sel     = Array(deduped.prefix(max))
        let laws    = sel.filter { $0.category != "司法解释" }
        let interps = sel.filter { $0.category == "司法解释" }
        var parts: [String] = []
        if !laws.isEmpty    { parts.append("【法律原文】");  parts += laws.map    { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(500)))" } }
        if !interps.isEmpty { parts.append("\n【司法解释】"); parts += interps.map { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(500)))" } }
        return parts.joined(separator: "\n")
    }

    // MARK: - Step 6 — 参考法条筛选

    private func filterCitations(question: String, candidates: [DatabaseManager.RAGArticle]) async -> [DatabaseManager.RAGArticle] {
        let prompt = """
        你是中国法律助手。判断以下法律条文是否应作为参考法条展示给用户。
        Y：条文规定用户可主张的权利/赔偿/合同解除权，或规定对方义务/违约后果。
        N：行政监管要求、定义性条款、与用户问题无直接关系的条文。
        只输出 Y 或 N。
        """
        var kept: [DatabaseManager.RAGArticle] = []
        for a in candidates {
            let user = "用户问题：\(question)\n\n法律条文：《\(a.lawTitle)》\(a.articleNumber)：\(String(a.content.prefix(300)))"
            let v = (try? await chat(system: prompt, user: user))?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "Y"
            if v.hasPrefix("Y") { kept.append(a) }
        }
        return kept
    }

    // MARK: - LLM helpers

    func chat(system: String, user: String) async throws -> String {
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user",   "content": user]
        ]
        return try await LLMProviderRegistry.current.chat(messages: messages, temperature: 0.05)
    }

    private func streamChat(system: String, user: String, onToken: @escaping (String) -> Void) async throws {
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user",   "content": user]
        ]
        try await LLMProviderRegistry.current.streamChat(messages: messages, temperature: 0.1, onToken: onToken)
    }

    // MARK: - Answer prompt

    private var answerPrompt: String { """
    你是中国法律助手。严格根据提供的法律条文回答问题。
    只输出结论文字，不要标题，不要法条列表。语言通俗易懂，可提及具体赔偿倍数。
    不得出现"依据第X条"等引用格式。
    严禁使用任何Markdown格式：不得使用**加粗**、#标题、-列表符号、---分隔线等。用中文顿号、书名号、序号（一、二、三）代替。

    诉讼通用知识（无需法条支撑）：
    - 合同纠纷：被告住所地或合同履行地法院
    - 房屋租赁：房屋所在地法院（不动产专属管辖）
    - 劳动争议：先仲裁，再起诉
    - 侵权：侵权行为地或被告住所地法院
    - 离婚：被告住所地法院
    - 食品安全索赔：价款十倍赔偿金（不足1000元按1000元计）
    - 消费欺诈：价款三倍赔偿金（不足500元按500元计）
    - 诉讼费：财产类1万以下50元，败诉方承担
    """ }

    // MARK: - Util

    private func stripMarkdownFence(_ s: String) -> String {
        // DeepSeek 等模型有时会把 JSON 包在 ```json ... ``` 里
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSON(_ s: String, open: String, close: String) -> String {
        guard let a = s.range(of: open)?.lowerBound,
              let b = s.range(of: close, options: .backwards)?.upperBound
        else { return s }
        return String(s[a ..< b])
    }
}
