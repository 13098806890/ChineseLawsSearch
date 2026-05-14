//
//  LegalExpertService.swift
//  ChineseLawsSearch
//
//  多层专家协作法律问答系统（iOS 版）
//  架构：Coordinator → Expert Groups → Sub-experts
//

import Foundation

// MARK: - Article bag (internal)

private struct ArticleBag {
    var articles: [DatabaseManager.RAGArticle] = []
}

// MARK: - Service

final class LegalExpertService {
    static let shared = LegalExpertService()

    /// 用户公报笔记字典（docId字符串 → 笔记文本），由 ViewModel 在每次 send() 时从 MainActor 写入
    var gazetteNotes: [String: String] = [:]

    // MARK: - Quality settings (mirrors UserStore computed properties)
    // Reads chatQualityMode from UserDefaults (the same key @AppStorage uses)
    // so LegalExpertService always sees the latest user preference without
    // coupling to UserStore directly.
    private var qualityMode: String {
        UserDefaults.standard.string(forKey: "chatQualityMode") ?? "standard"
    }
    private var maxContextArticles: Int {
        switch qualityMode {
        case "economy":  return 15
        case "detailed": return 0
        default:         return 40
        }
    }
    private var maxCitationsLimit: Int {
        switch qualityMode {
        case "economy":  return 5
        case "detailed": return 0
        default:         return 80
        }
    }

    /// Result of decomposing a multi-question input.
    struct DecomposedQuestion {
        let preamble:  String    // shared factual context (empty if none)
        let questions: [String]  // individual questions (empty = no split needed)
    }

    // MARK: - Public entry point

    // MARK: - Mod 1: Unified intent + mode classification (single LLM call)

    /// Classify intent AND query mode in one LLM call.
    /// Returns (.offTopic, nil), (.followUp, nil), or (.legalQuery, QueryMode?)
    func classifyIntentAndMode(message: String,
                               history: [(user: String, assistant: String)]) async -> (MessageIntent, QueryMode?) {
        // Fast-path: pure greeting/chat with no factual content
        let obviousOffTopic = ["你好", "hello", "hi", "谢谢", "再见", "bye", "👋"]
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if history.isEmpty && message.count < 8 && obviousOffTopic.contains(where: { trimmed.hasPrefix($0) }) {
            return (.offTopic, nil)
        }

        let recentHistory = history.suffix(2)
            .map { "用户：\($0.user)\n助手：\($0.assistant.prefix(100))" }
            .joined(separator: "\n---\n")
        let historySection = recentHistory.isEmpty ? "（无历史对话）" : recentHistory

        let system = """
        你是意图分类器。判断用户消息属于以下哪种类型，输出JSON（严格格式，不要其他内容）。

        类型说明：
        - "legal_query"：一切与法律相关的问题，包括：陈述具体纠纷事实、询问法律概念、查询法条规定、询问权利义务、法律知识提问等。**任何涉及人与人之间矛盾、生活纠纷、权益问题、法律规定的内容都属于此类**。即使措辞非常口语化（"邻居每天放很大声音"、"老板不给我发工资"），只要描述了某种困扰、纠纷、权益受损或他人侵害，也判定为 legal_query。
        - "follow_up"：基于历史对话中已有的具体案情继续追问，如"那我应该去哪个法院"、"这种情况能否申请保全"。必须以历史对话中存在明确具体案情为前提。
        - "off_topic"：**仅限**纯粹的问候、闲聊、与任何法律/权益/纠纷完全无关的内容（如"今天天气真好"、"你会唱歌吗"、"你叫什么"），以及询问 app 使用方式等功能性问题。

        当 intent = "legal_query" 时，同时判断问题模式，输出 mode 字段：
        - "case"：用户陈述了具体的事实情况（时间、地点、人物、发生了什么），需要分析其权利义务、胜诉可能或维权策略
        - "advisory"：用户询问某类情景下的权利义务，有假设场景但无具体案情事实
        - "statute"：用户询问法律概念定义、某罪/某权利的构成要件，或要求查找/列举某主题相关法条原文
        - "gongbao"：用户明确要找案例、判决、公报文书，问句中含有"案例"、"判决"、"指导案例"、"裁判文书"、"司法文件"、"法院怎么判"、"实践中"、"有没有案例"、"案例检索"等表达

        输出格式（严格JSON，不要其他内容）：
        {"intent": "legal_query", "mode": "case"}
        {"intent": "legal_query", "mode": "gongbao"}
        {"intent": "off_topic"}
        {"intent": "follow_up"}

        注意：
        - 对不确定的情况，宁可判定为 "legal_query"，不要轻易判定为 "off_topic"
        - "follow_up" 必须以历史对话中存在明确具体案情为前提；若历史无案情，判定为 "legal_query"
        - 有历史对话时，如果用户引入了与之前完全不同的新问题，判定为 "legal_query"
        """
        let user = "历史对话：\n\(historySection)\n\n当前消息：\(message)"

        guard let raw  = try? await chat(system: system, user: user),
              let data = extractJSON(raw, open: "{", close: "}").data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let intentStr = obj["intent"] as? String,
              let intent = MessageIntent(rawValue: intentStr)
        else {
            return (history.isEmpty ? .legalQuery : .followUp, nil)
        }

        if intent == .followUp {
            return (.followUp, nil)
        }
        if intent == .offTopic {
            return (.offTopic, nil)
        }
        // legal_query: extract mode
        let modeStr = obj["mode"] as? String
        let mode = modeStr.flatMap { QueryMode(rawValue: $0) }
        return (.legalQuery, mode)
    }

    /// Unified entry point for all legal queries.
    /// If preClassifiedMode is provided (always the case from the hot path), uses it directly.
    func askLegalQuery(question: String,
                       conversationHistory: [(user: String, assistant: String)],
                       knownFacts: [String: String],
                       followUpRound: Int,
                       maxFollowUpRounds: Int,
                       preClassifiedMode: QueryMode? = nil,
                       onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> ([RAGCitation], QueryMode) {
        let mode = preClassifiedMode ?? .legalAdvisory
        onEvent(.thinkStep(name: "问题模式", content: mode.label))

        switch mode {
        case .caseAnalysis:
            // Decompose multi-issue questions before routing (regex fast-path + LLM fallback)
            let decomposed = await decomposeQuestion(question)
            let subQs = decomposed.questions   // empty = single question, no split needed
            if !subQs.isEmpty {
                onEvent(.thinkStep(name: "拆分问题",
                                   content: subQs.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")))
                onEvent(.subQuestions(subQs))
            }
            let citations = try await runPipeline(
                question: question, factContext: decomposed.preamble, subQs: subQs,
                conversationHistory: conversationHistory, knownFacts: knownFacts,
                followUpRound: followUpRound, maxFollowUpRounds: maxFollowUpRounds,
                onEvent: onEvent)
            return (citations, mode)

        case .legalAdvisory:
            let citations = try await runPipelineWithMode(
                question: question, mode: .legalAdvisory,
                conversationHistory: conversationHistory, onEvent: onEvent)
            return (citations, mode)

        case .conceptAndStatute:
            let citations = try await runPipelineWithMode(
                question: question, mode: .conceptAndStatute,
                conversationHistory: conversationHistory, onEvent: onEvent)
            return (citations, mode)

        case .gongbaoSearch:
            try await askGongbaoSearch(question: question, onEvent: onEvent)
            return ([], mode)
        }
    }

    /// Run expert pipeline for advisory or statute mode (no clarifying questions).
    private func runPipelineWithMode(question: String,
                                     mode: QueryMode,
                                     conversationHistory: [(user: String, assistant: String)] = [],
                                     onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> [RAGCitation] {
        let analysis = await characterizeAndRoute(question: question, knownFacts: [:], conversationHistory: conversationHistory)
        onEvent(.thinkStep(name: "法律定性", content: analysis.characterization))
        onEvent(.thinkStep(name: "细分专家", content: analysis.experts.isEmpty ? "综合顾问" : analysis.experts.map { $0.name }.joined(separator: "、")))
        onEvent(.expertsSelected(analysis.experts))

        let db = DatabaseManager.shared
        var expertArticles: [String: [DatabaseManager.RAGArticle]] = [:]
        var expertAnswers:  [String: String] = [:]

        let effectiveExperts = analysis.experts.isEmpty
            ? [SubExpert(name: "综合法律顾问", domain: "综合", requiredInfo: [],
                         lawTitles: [], chapterIdHints: [],
                         ftsDomains: ["宪法相关法","民法典","民法商法","刑法","行政法","经济法","社会法","诉讼与非诉讼程序法"],
                         ftsCategories: ["法律","宪法","修正案","法律解释","司法解释","行政法规","监察法规"],
                         ftsKeywordsExtra: [], answerTemplate: "你是中国法律专家。")]
            : analysis.experts

        // Mod 3: concurrent expert retrieval + analysis
        let isStatute = (mode == .conceptAndStatute)
        try await withThrowingTaskGroup(of: (String, [DatabaseManager.RAGArticle], String).self) { group in
            for expert in effectiveExperts {
                group.addTask { [self] in
                    var articles: [DatabaseManager.RAGArticle]
                    if isStatute {
                        // Mod 3: each expert has its own seenIds (no shared state)
                        articles = try await self.lookupArticlesWithExpert(expert: expert, question: question, db: db)
                    } else {
                        // Mod 4: filterArticles removed; expert self-filters via prompt
                        articles = self.retrieveForExpert(expert: expert, question: question, facts: [:])
                        articles = self.expandReferences(articles: articles)
                    }
                    let answer = try await self.analyzeWithExpertMode(expert: expert, question: question, articles: articles, mode: mode)
                    return (expert.name, articles, answer)
                }
            }
            for try await (name, arts, ans) in group {
                expertArticles[name] = arts
                expertAnswers[name] = ans
            }
        }

        let totalCount = expertArticles.values.map { $0.count }.reduce(0, +)
        let allForDisplay = deduplicateArticles(expertArticles).map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle, articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum, category: $0.category, content: $0.content)
        }
        onEvent(.thinkStepWithArticles(name: "专家检索", content: "共 \(totalCount) 条", articles: allForDisplay))

        // Coordinator 最终回答 + 引用提取（共用函数）
        let allArticlesFlat = deduplicateArticles(expertArticles)
        return try await runCoordinatorStage(
            question: question, subQs: [],
            groupAnswers: expertAnswers, allArticlesFlat: allArticlesFlat,
            systemPrompt: coordinatorSystemPromptForMode(mode), onEvent: onEvent)
    }

    /// Expert analysis prompt tailored to query mode.
    private func analyzeWithExpertMode(expert: SubExpert, question: String,
                                       articles: [DatabaseManager.RAGArticle],
                                       mode: QueryMode) async throws -> String {
        let artText = articles.prefix(maxContextArticles > 0 ? maxContextArticles : articles.count)
            .map { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(400)))" }
            .joined(separator: "\n")

        let modeInstruction: String
        switch mode {
        case .legalAdvisory:
            modeInstruction = """
            用户询问的是一类情景下的权利义务，无具体案情。请：
            1. 给出该情景下的一般性法律结论（法律怎么规定）
            2. 说明主要例外或特殊情形
            3. 引用相关法条编号作为依据
            4. 语气客观，不预设用户立场
            不要追问，不要要求用户提供具体案情。
            """
        case .conceptAndStatute:
            modeInstruction = """
            用户询问的是法律概念或具体法条。请：
            - 若是概念：给出准确定义、构成要件、与相近概念的区别，引用相关条文
            - 若是法条查询：直接引用原文，按条文顺序呈现，加简要说明
            只陈述法律规定，不发表主观评价，不推测案情。
            """
        case .caseAnalysis:
            modeInstruction = ""  // handled by existing analyzeWithExpert
        case .gongbaoSearch:
            modeInstruction = ""  // gongbaoSearch doesn't go through expert analysis
        }

        // Mod 4: add self-filter instruction
        let systemPrompt = """
        你是【\(expert.name)】，专精领域：\(expert.domain)。
        \(modeInstruction)
        【严格限制】只能引用以下提供的法条，不得引用未在列表中的条文。
        【重要】如果提供的法条与问题不直接相关，明确说明"现有法条不足以回答此问题"，不得凭记忆编造条文编号或内容。
        如果提供的法条中只有部分与问题直接相关，只引用相关的，忽略无关条文，不要为了引用而引用。
        严禁使用Markdown格式。
        """
        return (try? await chat(system: systemPrompt,
                                user: "相关法条：\n\(artText)\n\n问题：\(question)")) ?? {
            #if DEBUG
            print("[LegalExpertService] analyzeWithExpertMode LLM error (expert: \(expert.name))")
            #endif
            return ""
        }()
    }

    /// Coordinator system prompt tailored to query mode.
    private func coordinatorSystemPromptForMode(_ mode: QueryMode) -> String {
        switch mode {
        case .legalAdvisory:
            return """
            你是中国法律综合顾问。将专家分析整合为最终回答。
            原则：
            - 给出该类情景下的一般性法律结论，说明主要例外情形
            - 客观中立，不预设用户是哪方当事人
            - 引用条文编号（如"依据第X条"），不在末尾单独列清单
            - 若有多个专家组，用中文序号（一、二、三）分段，每段开头说明针对哪个法律问题
            - 总长度300-600字
            严禁Markdown格式。不要说"综上所述"等空话。
            """
        case .conceptAndStatute:
            return """
            你是中国法律条文与概念解释专家。将专家检索结果整合为最终回答。
            原则：
            - 若是概念：给出准确定义和构成要件，引用相关条文原文
            - 若是法条查询：按条文顺序直接呈现原文，加简要说明
            - 只陈述法律规定，不发表评价，不推测案情
            - 【严格限制】只能引用检索到的法条，不得引用未检索到的条文
            - 总长度200-500字
            严禁Markdown格式。
            """
        case .caseAnalysis:
            return coordinatorSystemPrompt
        case .gongbaoSearch:
            return coordinatorSystemPrompt  // not used by this path
        }
    }

    /// 单个专家用 LLM 知识识别法条编号，再精确查询 DB，FTS 兜底。
    /// Mod 3: uses its own local seenIds (no inout parameter) for concurrent safety.
    private func lookupArticlesWithExpert(expert: SubExpert,
                                          question: String,
                                          db: DatabaseManager) async throws -> [DatabaseManager.RAGArticle] {
        var seenIds = Set<Int>()

        let identifyPrompt = """
        你是【\(expert.name)】，专精领域：\(expert.domain)。
        根据用户的查询，列出在你的专业领域内**直接相关**的法律条文。

        规则：
        - 只列属于你专业领域的条文，不要列其他领域的条文
        - 法律全称（中文，不要简称），条文编号用"第X条"格式（汉字数字）
        - 每部法律最多5条，总共最多10条
        - 如不确定具体条文号，可只写法律名称，articles 填空数组
        - 如该查询与你的专业领域无关，输出 {"laws": []}

        输出纯 JSON：{"laws": [{"name": "完整法律名称", "articles": ["第X条", ...]}, ...]}

        用户查询：\(question)
        """
        let raw = (try? await chat(system: "只输出JSON，不要markdown。", user: identifyPrompt)) ?? ""
        let json = extractJSON(raw, open: "{", close: "}")

        struct LawRef { let name: String; let articles: [String] }
        var lawRefs: [LawRef] = []
        if let data = json.data(using: .utf8),
           let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr  = obj["laws"] as? [[String: Any]] {
            for item in arr {
                let name = (item["name"] as? String) ?? ""
                let arts = (item["articles"] as? [String]) ?? []
                if !name.isEmpty { lawRefs.append(LawRef(name: name, articles: arts)) }
            }
        }

        var result: [DatabaseManager.RAGArticle] = []
        var missedAny = false
        let allDomains = expert.ftsDomains.isEmpty ? ["宪法相关法","民法典","民法商法","刑法","行政法","经济法","社会法","诉讼与非诉讼程序法"] : expert.ftsDomains
        let allCats    = expert.ftsCategories.isEmpty ? ["法律","宪法","修正案","法律解释","司法解释","行政法规","监察法规"] : expert.ftsCategories

        for ref in lawRefs {
            let shortName = ref.name.replacingOccurrences(of: "中华人民共和国", with: "")
            if ref.articles.isEmpty {
                // No specific article — FTS within this law
                for kw in simpleKeywords(from: question).prefix(3) {
                    for a in db.ftsSearch(keyword: kw, domains: allDomains, categories: allCats, limit: 5) {
                        if (a.lawTitle.contains(shortName) || a.lawTitle.contains(ref.name))
                            && seenIds.insert(a.nodeId).inserted {
                            result.append(a)
                        }
                    }
                }
            } else {
                for artNum in ref.articles {
                    let found = db.articleByRef(lawTitleFragment: shortName, articleNumber: artNum)
                              ?? db.articleByRef(lawTitleFragment: ref.name, articleNumber: artNum)
                    if let a = found, seenIds.insert(a.nodeId).inserted {
                        result.append(a)
                    } else if found == nil {
                        missedAny = true
                    }
                }
            }
        }

        // FTS fallback if LLM gave no refs or all refs missed
        if missedAny || (result.isEmpty && !lawRefs.isEmpty) {
            for kw in simpleKeywords(from: question).prefix(4) {
                for a in db.ftsSearch(keyword: kw, domains: allDomains, categories: allCats, limit: 6) {
                    if seenIds.insert(a.nodeId).inserted { result.append(a) }
                }
            }
        }

        // DB 双向引用扩展
        let dbRefs = db.referencedArticles(nodeIds: result.map { $0.nodeId }, excludingIds: seenIds)
        for ref in dbRefs {
            if seenIds.insert(ref.nodeId).inserted { result.append(ref) }
        }

        return result
    }

    /// Handle a follow-up question, reusing previously selected experts.
    /// If the question touches new legal domains, merges in additional experts.
    func askFollowUp(question: String,
                     lastExperts: [SubExpert],
                     conversationHistory: [(user: String, assistant: String)],
                     knownFacts: [String: String],
                     onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> ([RAGCitation], [SubExpert]) {
        // Check if new legal domains are needed
        var nameToExpert: [String: SubExpert] = [:]
        for group in allExpertGroups.values {
            for e in group.subExperts { nameToExpert[e.name] = e }
        }
        let allExpertDesc = nameToExpert.values
            .map { "- \($0.name)：\($0.domain)" }.sorted().joined(separator: "\n")
        let lastExpertNames = lastExperts.map { $0.name }.joined(separator: "、")

        let checkPrompt = """
        用户正在追问一个已有法律案件。判断追问是否涉及上次未涉及的新法律领域。
        输出JSON：{"needs_new_experts": true/false, "new_experts": ["专家名1"]}
        只有在追问引入完全不同的法律关系时才添加新专家；细化追问同一法律关系则不添加。

        上次使用的专家：\(lastExpertNames)
        可用专家：\n\(allExpertDesc)
        追问内容：\(question)
        """
        let checkRaw = (try? await chat(system: "只输出JSON，不要其他内容。", user: checkPrompt)) ?? ""
        var mergedExperts = lastExperts
        if let data = extractJSON(checkRaw, open: "{", close: "}").data(using: .utf8),
           let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let needsNew = obj["needs_new_experts"] as? Bool, needsNew,
           let newNames = obj["new_experts"] as? [String] {
            let newExperts = newNames.compactMap { nameToExpert[$0] }
                .filter { e in !mergedExperts.contains(where: { $0.name == e.name }) }
            mergedExperts += newExperts
            if !newExperts.isEmpty {
                onEvent(.thinkStep(name: "扩展专家", content: newExperts.map { $0.name }.joined(separator: "、")))
            }
        }
        onEvent(.thinkStep(name: "细分专家", content: "复用：" + mergedExperts.map { $0.name }.joined(separator: "、")))

        // Build a focused context from conversation history for the coordinator
        let historyContext = conversationHistory.suffix(3)
            .map { "用户：\($0.user)\n助手：\($0.assistant)" }
            .joined(separator: "\n---\n")

        // Run retrieval + expert analysis for merged experts (skip clarifying)
        let citations = try await runPipelineWithExperts(
            question: question,
            factContext: historyContext,
            experts: mergedExperts,
            conversationHistory: conversationHistory,
            knownFacts: knownFacts,
            onEvent: onEvent
        )
        return (citations, mergedExperts)
    }

    // MARK: - Core pipeline

    private func runPipeline(question: String,
                              factContext: String,
                              subQs: [String],
                              conversationHistory: [(user: String, assistant: String)],
                              knownFacts: [String: String],
                              followUpRound: Int,
                              maxFollowUpRounds: Int,
                              onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> [RAGCitation] {

        let questionsToAnalyze = subQs.isEmpty ? [question] : subQs

        // Step 1: 递进式法律定性 + 按需路由（每个子问题独立定性）
        var questionAnalyses: [QuestionAnalysis] = []
        var allSelectedExperts: [SubExpert] = []
        var expertToQuestions:  [String: [String]] = [:]
        var seenNames = Set<String>()

        for q in questionsToAnalyze {
            // Mod 5: pass conversationHistory to characterizeAndRoute
            let analysis = await characterizeAndRoute(question: q, knownFacts: [:], conversationHistory: conversationHistory)
            questionAnalyses.append(analysis)
            for e in analysis.experts {
                expertToQuestions[e.name, default: []].append(q)
                if seenNames.insert(e.name).inserted { allSelectedExperts.append(e) }
            }
        }

        let charSummary = questionAnalyses.enumerated().map { i, a in
            questionsToAnalyze.count > 1
                ? "【子问题 \(i+1)】\n\(a.characterization)"
                : a.characterization
        }.joined(separator: "\n\n")
        onEvent(.thinkStep(name: "法律定性", content: charSummary))
        onEvent(.thinkStep(name: "细分专家",
                           content: allSelectedExperts.map { $0.name }.joined(separator: "、")))
        onEvent(.expertsSelected(allSelectedExperts))

        return try await runExpertStages(
            question: question, factContext: factContext, subQs: subQs,
            allSelectedExperts: allSelectedExperts,
            expertToQuestions: expertToQuestions,
            conversationHistory: conversationHistory,
            knownFacts: knownFacts,
            followUpRound: followUpRound,
            maxFollowUpRounds: maxFollowUpRounds,
            onEvent: onEvent
        )
    }

    /// Pipeline variant that skips routing — uses pre-selected experts directly.
    private func runPipelineWithExperts(question: String,
                                         factContext: String,
                                         experts: [SubExpert],
                                         conversationHistory: [(user: String, assistant: String)],
                                         knownFacts: [String: String],
                                         onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> [RAGCitation] {
        var expertToQuestions: [String: [String]] = [:]
        for e in experts { expertToQuestions[e.name] = [question] }
        return try await runExpertStages(
            question: question, factContext: factContext, subQs: [],
            allSelectedExperts: experts,
            expertToQuestions: expertToQuestions,
            conversationHistory: conversationHistory,
            knownFacts: knownFacts,
            followUpRound: 0, maxFollowUpRounds: 0,
            onEvent: onEvent
        )
    }

    /// Shared steps 2–6: fact extraction, retrieval, expert analysis, synthesis, coordinator.
    private func runExpertStages(question: String,
                                  factContext: String,
                                  subQs: [String],
                                  allSelectedExperts: [SubExpert],
                                  expertToQuestions: [String: [String]],
                                  conversationHistory: [(user: String, assistant: String)],
                                  knownFacts: [String: String],
                                  followUpRound: Int,
                                  maxFollowUpRounds: Int,
                                  onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> [RAGCitation] {
        let allUserText = ([factContext, question] + conversationHistory.map { $0.user + " " + $0.assistant })
            .filter { !$0.isEmpty }.joined(separator: "\n")
        var mergedFacts = autoExtractFacts(question: allUserText, experts: allSelectedExperts)
        for (k, v) in knownFacts { mergedFacts[k] = v }

        // 追问缺失的事实信息（仅当问题未拆分时才追问——多问题情形直接分析）
        if followUpRound < maxFollowUpRounds && subQs.isEmpty {
            let missingInfos = allSelectedExperts.flatMap { expert in
                expert.requiredInfo.filter { info in
                    mergedFacts[info.field] == nil &&
                    !info.regexHint.isEmpty &&
                    !info.question.isEmpty
                }
            }.uniqued(by: \.field)

            if !missingInfos.isEmpty {
                let isLastRound = followUpRound == maxFollowUpRounds - 1
                let questionText: String
                if isLastRound || missingInfos.count >= 2 {
                    // 最后一轮或多项缺失：一次性列出所有问题
                    let lines = missingInfos.enumerated().map { "\($0.offset + 1). \($0.element.question)" }
                    questionText = "为了给您提供更准确的法律分析，需要了解以下几点关键信息：\n\n"
                        + lines.joined(separator: "\n")
                        + "\n\n请尽量详细回答，有助于专家给出更具针对性的意见。"
                } else {
                    // 首轮单项缺失：礼貌引导，说明为何需要该信息
                    let info = missingInfos[0]
                    questionText = "为了更准确地分析您的情况，我需要了解一个关键信息：\n\n\(info.question)\n\n这一信息将直接影响适用的法律条款和您的权利主张，请尽量详细说明。"
                }
                onEvent(.clarifyingQuestion(questionText))
                return []
            }
        }

        let knownFacts = mergedFacts

        // Step 3: 每个专家检索并分析其负责的子问题（Mod 3: 并发执行）
        var expertArticles: [String: [DatabaseManager.RAGArticle]] = [:]
        var expertAnswers:  [String: String] = [:]

        try await withThrowingTaskGroup(of: (String, [DatabaseManager.RAGArticle], String).self) { group in
            for expert in allSelectedExperts {
                let assignedQs   = expertToQuestions[expert.name] ?? [question]
                let questionText = assignedQs.count == 1 ? assignedQs[0] : assignedQs.joined(separator: "\n")
                let expertContext = factContext.isEmpty ? questionText : "\(factContext)\n\n\(questionText)"
                let kf = knownFacts
                group.addTask { [self] in
                    guard !Task.isCancelled else { return (expert.name, [], "") }
                    // Mod 4: filterArticles removed; expert self-filters via prompt instruction
                    var articles = self.retrieveForExpert(expert: expert, question: expertContext, facts: kf)
                    articles = self.expandReferences(articles: articles)
                    let answer = try await self.analyzeWithExpert(expert: expert, question: expertContext,
                                                                  facts: kf, articles: articles)
                    return (expert.name, articles, answer)
                }
            }
            for try await (name, arts, ans) in group {
                expertArticles[name] = arts
                expertAnswers[name] = ans
            }
        }

        let totalArticleCount = expertArticles.values.map { $0.count }.reduce(0, +)
        let allArticlesForDisplay = deduplicateArticles(expertArticles).map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle, articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum, category: $0.category, content: $0.content)
        }
        onEvent(.thinkStepWithArticles(
            name: "专家检索",
            content: "共 \(totalArticleCount) 条（\(allSelectedExperts.count) 位专家）",
            articles: allArticlesForDisplay))

        // Step 4: 按专家组合并同组专家的分析
        var expertGroupMap: [String: ExpertGroup] = [:]
        for group in allExpertGroups.values {
            for e in group.subExperts { expertGroupMap[e.name] = group }
        }
        var groupToExpertNames: [String: [String]] = [:]
        for expert in allSelectedExperts {
            if let g = expertGroupMap[expert.name] {
                groupToExpertNames[g.name, default: []].append(expert.name)
            }
        }

        var groupAnswers: [String: String] = [:]
        // Parallelize synthesis across groups (single-expert groups skip synthesize instantly)
        try await withThrowingTaskGroup(of: (String, String).self) { taskGroup in
            for (groupName, expertNames) in groupToExpertNames {
                guard let group = allExpertGroups[groupName] else { continue }
                let subAns = expertNames.compactMap { name -> (String, String)? in
                    guard let ans = expertAnswers[name] else { return nil }
                    return (name, ans)
                }
                guard !subAns.isEmpty else { continue }
                if subAns.count == 1 {
                    // Single expert — no LLM call needed; collect immediately
                    groupAnswers[groupName] = subAns[0].1
                } else {
                    taskGroup.addTask { [self] in
                        let synthesis = try await self.synthesizeGroup(
                            group: group,
                            subAnswers: Dictionary(uniqueKeysWithValues: subAns),
                            question: question)
                        return (groupName, synthesis)
                    }
                }
            }
            for try await (groupName, synthesis) in taskGroup {
                groupAnswers[groupName] = synthesis
            }
        }
        onEvent(.thinkStep(name: "专家组综合",
                           content: groupAnswers.keys.joined(separator: "、") + " 已完成分析"))

        // Step 5+6: Coordinator 最终回答 + 引用提取（共用函数）
        let allArticlesFlat = deduplicateArticles(expertArticles)
        return try await runCoordinatorStage(
            question: question, subQs: subQs,
            groupAnswers: groupAnswers, allArticlesFlat: allArticlesFlat,
            systemPrompt: coordinatorSystemPrompt, onEvent: onEvent)
    }

    // MARK: - Shared coordinator + citation stage

    /// Streams the final Coordinator answer and extracts citations from the response text.
    /// Used by both runExpertStages (caseAnalysis) and runPipelineWithMode (advisory/statute).
    private func runCoordinatorStage(question: String,
                                      subQs: [String],
                                      groupAnswers: [String: String],
                                      allArticlesFlat: [DatabaseManager.RAGArticle],
                                      systemPrompt: String,
                                      onEvent: @escaping @MainActor (RAGEvent) -> Void) async throws -> [RAGCitation] {

        // 公报案例检索在 coordinator 生成之前完成，结果注入 context
        let lawIds = Array(Set(allArticlesFlat.map { $0.lawId }))
        let gazetteCites = await retrieveGazetteCases(
            question: question,
            expandedTerms: [],
            sourceFilter: nil,
            candidateLawIds: lawIds,
            onEvent: onEvent)

        let context = buildGroupContext(groupAnswers: groupAnswers, articles: allArticlesFlat,
                                        gazetteCites: gazetteCites)
        var userMsg = "用户问题：\(question)\n\n"
        if !subQs.isEmpty {
            userMsg += "问题已拆分为以下独立子问题，请逐一分标题回答，每个子问题回答前先用一句话复述该子问题：\n"
            userMsg += subQs.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")
            userMsg += "\n\n"
        }
        userMsg += context

        var answerText = ""
        try await LLMProviderRegistry.agentProvider.streamChat(
            messages: [["role": "system", "content": systemPrompt],
                       ["role": "user",   "content": userMsg]],
            temperature: 0.2,
            onToken: { token in answerText += token; onEvent(.token(token)) }
        )

        let cited = citationsFromAnswer(answerText: answerText, candidates: allArticlesFlat)
        onEvent(.thinkStep(name: "参考法条筛选",
                           content: "从答案正文引用中提取 \(cited.count) 条直接引用的法条"))

        if !gazetteCites.isEmpty {
            onEvent(.gazetteCitations(gazetteCites))
        }

        return cited.map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                        articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                        category: $0.category, content: $0.content)
        }
    }

    // MARK: - 公报案例检索（扩词 → 多路召回 → LLM 筛选）

    /// 专用公报检索路径：扩词 → 多路召回 → LLM 汇总回答
    private func askGongbaoSearch(
        question: String,
        onEvent: @escaping @MainActor (RAGEvent) -> Void
    ) async throws {
        onEvent(.thinkStep(name: "公报检索模式", content: "直接检索人民法院公报案例库"))

        // Stage 0: LLM 扩词 + 来源推断
        let expansion = await expandSearchTerms(question: question)
        let termsSummary = expansion.terms.isEmpty ? question : expansion.terms.joined(separator: "、")
        onEvent(.thinkStep(name: "检索词扩展", content: "检索词：\(termsSummary)\n目标库：\(expansion.sourceLabel)"))

        // Stage 1: 多路召回
        let gazetteCites = await retrieveGazetteCases(
            question: question,
            expandedTerms: expansion.terms,
            sourceFilter: expansion.sourceFilter,
            candidateLawIds: [],
            onEvent: onEvent
        )

        if !gazetteCites.isEmpty {
            onEvent(.gazetteCitations(gazetteCites))
        }

        // Stage 2: LLM 基于检索结果汇总回答
        let caseContext: String
        if gazetteCites.isEmpty {
            caseContext = "未找到直接相关的公报文书。"
        } else {
            caseContext = gazetteCites.map { cite in
                "【\(cite.title)】\n裁判要点：\(cite.rulingGist.isEmpty ? "（无摘要）" : String(cite.rulingGist.prefix(200)))"
            }.joined(separator: "\n\n")
        }

        let systemPrompt = """
        你是中国法律案例检索助手。根据用户问题和检索到的公报文书，给出简洁准确的回答。
        规则：
        - 只基于提供的案例内容作答，不编造案例
        - 如果找到相关案例，提炼共同裁判规则和司法口径
        - 如果没有找到，说明原因并建议换词搜索
        - 严禁使用Markdown格式（不用**、#、- 等），用中文序号和书名号
        - 总长度200-400字
        """
        let userMsg = "用户问题：\(question)\n\n检索到的公报文书：\n\(caseContext)"
        try await LLMProviderRegistry.agentProvider.streamChat(
            messages: [["role": "system", "content": systemPrompt],
                       ["role": "user",   "content": userMsg]],
            temperature: 0.2,
            onToken: { onEvent(.token($0)) }
        )
    }

    /// LLM 扩词：把口语问题转换为法律检索词 + 推断来源
    private struct SearchExpansion {
        let terms: [String]
        let sourceFilter: String?   // nil = all, "al"/"cpwsxd"/"sfwj"
        var sourceLabel: String {
            switch sourceFilter {
            case "al":     return "指导案例"
            case "cpwsxd": return "裁判文书"
            case "sfwj":   return "司法文件"
            default:       return "全部公报"
            }
        }
    }

    private func expandSearchTerms(question: String) async -> SearchExpansion {
        let system = """
        你是法律检索词扩展器。将用户的口语化问题转化为中文法律数据库检索词。

        输出严格JSON（不要其他内容）：
        {"terms":["词1","词2","词3"],"source":"al"}

        source 字段规则：
        - "al"：用户明确提到"指导案例"、"指导性案例"
        - "cpwsxd"：用户明确提到"裁判文书"、"判决书"、"裁定书"
        - "sfwj"：用户明确提到"司法文件"、"通知"、"意见"、"规定"（最高院发的）
        - "all"：不明确或同时涉及多类

        terms 字段规则：
        - 3到6个词，每个词3到8字，必须是中文法律专业术语
        - 覆盖：法律行为名称、法条名称、裁判规则关键词、同义词
        - 例："裁员相关指导案例" → terms:["经济性裁员","裁减人员","劳动合同解除","经济补偿金","违法解除劳动合同"]，source:"al"
        - 例："网购退款纠纷判决" → terms:["网络购物合同","消费者权益保护","七日无理由退货","电子商务纠纷"]，source:"cpwsxd"
        """
        guard let raw = try? await chat(system: system, user: question),
              let data = extractJSON(raw, open: "{", close: "}").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let terms = obj["terms"] as? [String], !terms.isEmpty
        else {
            // 降级：用 extractTerms 做本地扩词
            return SearchExpansion(terms: extractTerms(from: question), sourceFilter: nil)
        }
        let src = obj["source"] as? String
        let sourceFilter: String? = (src == "all" || src == nil) ? nil : src
        return SearchExpansion(terms: terms, sourceFilter: sourceFilter)
    }

    private func retrieveGazetteCases(
        question: String,
        expandedTerms: [String] = [],
        sourceFilter: String? = nil,
        candidateLawIds: [Int],
        onEvent: @escaping @MainActor (RAGEvent) -> Void
    ) async -> [GazetteCitation] {
        let db = DatabaseManager.shared
        // gazetteNotes is written from MainActor before async call begins; read directly
        let notes = gazetteNotes

        // 合并检索词：扩展词优先，fallback 到本地提取词
        let searchTerms: [String] = expandedTerms.isEmpty ? extractTerms(from: question) : expandedTerms

        // 策略 A：多词 FTS（每词独立搜索，绕过 2 字限制）
        let docsA = await Task.detached(priority: .userInitiated) {
            db.searchGazetteDocsMultiTerm(terms: searchTerms, sourceFilter: sourceFilter, limit: 15)
        }.value

        // 策略 B：keywords 字段 LIKE 匹配
        let docsB = await Task.detached(priority: .userInitiated) {
            db.searchGazetteByKeywords(terms: searchTerms, limit: 10)
        }.value

        // 策略 C：法条关联（仅普通查询路径有 candidateLawIds）
        let docsC: [GazetteDoc]
        if !candidateLawIds.isEmpty {
            docsC = await Task.detached(priority: .userInitiated) {
                db.searchGazetteByLawIds(candidateLawIds, limit: 10)
            }.value
        } else {
            docsC = []
        }

        // 策略 Note：笔记文本关键词匹配
        var noteMatches: [GazetteDoc] = []
        if !notes.isEmpty {
            let questionChars = Set(question.filter { $0.isLetter })
            for (docIdStr, noteText) in notes {
                guard let docId = Int(docIdStr) else { continue }
                let noteChars = Set(noteText.filter { $0.isLetter })
                let overlap = questionChars.intersection(noteChars).count
                if overlap >= 2, let doc = db.gazetteDoc(id: docId) {
                    noteMatches.append(doc)
                }
            }
        }

        // 合并去重（来源过滤后）
        var seen = Set<Int>()
        var candidates: [(doc: GazetteDoc, strategy: String)] = []

        func addDocs(_ docs: [GazetteDoc], strategy: String) {
            for doc in docs {
                // 如果指定了来源过滤，只保留该来源（笔记匹配不过滤）
                if let sf = sourceFilter, strategy != "note", doc.source != sf { continue }
                if seen.insert(doc.id).inserted {
                    candidates.append((doc, strategy))
                }
            }
        }

        addDocs(noteMatches, strategy: "note")
        addDocs(docsA, strategy: "fts")
        addDocs(docsC, strategy: "lawlinks")
        addDocs(docsB, strategy: "keywords")

        guard !candidates.isEmpty else { return [] }

        // LLM 筛选：超过 5 条时
        let filtered: [(doc: GazetteDoc, strategy: String, reason: String)]
        if candidates.count > 5 {
            filtered = await llmFilterGazetteCases(question: question, candidates: candidates)
        } else {
            filtered = candidates.map { ($0.doc, $0.strategy, "") }
        }

        let result = filtered.map { item in
            GazetteCitation(docId: item.doc.id, source: item.doc.source,
                            title: item.doc.title, rulingGist: item.doc.rulingGist,
                            strategy: item.strategy, relevanceReason: item.reason)
        }

        let summary = result.map { "• \($0.title)" }.joined(separator: "\n")
        onEvent(.thinkStep(name: "相关公报案例", content: summary.isEmpty ? "未找到相关案例" : summary))

        return result
    }

    /// 从问题文本中提取 2-6 字汉字词语（去除常见停用词）
    private func extractTerms(from text: String) -> [String] {
        let stopWords: Set<String> = ["的", "了", "是", "在", "我", "有", "和", "就", "不", "人",
                                       "都", "一", "一个", "上", "也", "很", "到", "说", "要", "去",
                                       "如何", "怎么", "什么", "可以", "应该", "能否", "是否", "有没有",
                                       "怎样", "哪些", "这个", "那个", "情况", "问题", "请问", "想问"]
        // 按标点/空格分割，过滤 2-6 字中文词
        let extraPunct = "\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{3001}\u{FF1B}\u{FF1A}\u{201C}\u{201D}\u{2018}\u{2019}\u{FF08}\u{FF09}\u{3010}\u{3011}\u{300A}\u{300B}\u{2026}\u{2014}"
        let tokens = text.components(separatedBy: CharacterSet.punctuationCharacters
            .union(.whitespaces).union(CharacterSet(charactersIn: extraPunct)))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { s in
                let count = s.count
                guard count >= 2 && count <= 6 else { return false }
                guard s.unicodeScalars.allSatisfy({ $0.value >= 0x4E00 && $0.value <= 0x9FFF }) else { return false }
                return !stopWords.contains(s)
            }
        return Array(Set(tokens)).prefix(8).map { $0 }
    }

    /// 用 LLM 从候选列表中筛选最相关的前 5 条
    private func llmFilterGazetteCases(
        question: String,
        candidates: [(doc: GazetteDoc, strategy: String)]
    ) async -> [(doc: GazetteDoc, strategy: String, reason: String)] {
        let listText = candidates.enumerated().map { i, item in
            "[\(item.doc.id)] 标题：\(item.doc.title)\n裁判要点：\(item.doc.rulingGist.prefix(100))"
        }.joined(separator: "\n\n")

        let prompt = """
            用户问题：\(question)

            以下是候选公报文书，请从中选出最相关的最多5条，只输出 JSON 数组，格式：
            [{"id":123,"reason":"一句话原因"}]
            不要输出任何其他内容。

            候选列表：
            \(listText)
            """

        var responseText = ""
        try? await LLMProviderRegistry.agentProvider.streamChat(
            messages: [["role": "user", "content": prompt]],
            temperature: 0.1,
            onToken: { responseText += $0 }
        )

        // 解析 JSON
        let jsonStr = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            // fallback: return first 5
            return candidates.prefix(5).map { ($0.doc, $0.strategy, "") }
        }

        var result: [(doc: GazetteDoc, strategy: String, reason: String)] = []
        let candidateMap = Dictionary(uniqueKeysWithValues: candidates.map { ($0.doc.id, $0) })
        for item in arr.prefix(5) {
            guard let id = item["id"] as? Int,
                  let candidate = candidateMap[id] else { continue }
            let reason = (item["reason"] as? String) ?? ""
            result.append((candidate.doc, candidate.strategy, reason))
        }
        return result.isEmpty ? candidates.prefix(5).map { ($0.doc, $0.strategy, "") } : result
    }

    // MARK: - 法律定性 + 递进路由

    private struct QuestionAnalysis {
        let question: String
        let characterization: String   // 多层定性描述
        let experts: [SubExpert]
    }

    /// Mod 5: characterizeAndRoute now accepts conversationHistory for context.
    private func characterizeAndRoute(question: String,
                                       knownFacts: [String: String],
                                       conversationHistory: [(user: String, assistant: String)] = []) async -> QuestionAnalysis {
        var nameToExpert: [String: SubExpert] = [:]
        for group in allExpertGroups.values {
            for e in group.subExperts { nameToExpert[e.name] = e }
        }
        let allExpertDesc = nameToExpert.values
            .map { "- \($0.name)：\($0.domain)" }
            .sorted().joined(separator: "\n")

        let system = """
        你是中国法律问题定性专家。对法律问题进行递进式定性分析，然后选出需要的细分专家。

        定性步骤（递进，每步基于上一步结论）：
        1. 法律关系性质：违约 / 侵权 / 行政 / 刑事 / 混合 / 公司法律关系 / 劳动关系 等
        2. 具体类型：基于第1步细化（如违约→买卖合同；侵权→名誉权；混合→违约侵权竞合）
        3. 程序问题：是否涉及诉讼管辖/仲裁/证据/执行（如有，加入程序专家）

        输出 JSON（严格格式，不要其他内容）：
        {
          "layers": ["第1步：...", "第2步：...", "第3步：...（无则省略）"],
          "experts": ["细分专家名1", "细分专家名2"]
        }

        可用细分专家：
        \(allExpertDesc)

        选专家规则：
        - 只选与问题核心法律关系直接相关的（通常1-3个，最多4个）
        - 违约→合同法专家；侵权→侵权责任专家；竞合→两者都选
        - 涉及公司股权/担保/决议→公司商事专家
        - 有程序问题→对应程序专家（民事/刑事/行政）
        - 不要因关键词相似选入实际无关的专家
        """

        var ctx = "问题：\(question)"
        if !knownFacts.isEmpty {
            ctx += "\n已知事实：" + knownFacts.map { "\($0.key)=\($0.value)" }.joined(separator: "；")
        }
        // Mod 5: attach recent conversation history for context
        if !conversationHistory.isEmpty {
            let hist = conversationHistory.suffix(2)
                .map { "用户：\($0.user.prefix(100))\n助手：\($0.assistant.prefix(80))" }
                .joined(separator: "\n---\n")
            ctx += "\n\n对话历史（供参考）：\n\(hist)"
        }

        guard let raw  = try? await chat(system: system, user: ctx),
              let data = extractJSON(raw, open: "{", close: "}").data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return fallbackAnalysis(question: question)
        }

        let layers      = obj["layers"] as? [String] ?? []
        let expertNames = obj["experts"] as? [String] ?? []
        let charText    = layers.isEmpty ? "（定性失败）" : layers.joined(separator: "\n")
        let selected    = expertNames.compactMap { nameToExpert[$0] }

        return QuestionAnalysis(
            question: question,
            characterization: charText,
            experts: selected.isEmpty ? fallbackAnalysis(question: question).experts : selected
        )
    }

    private func fallbackAnalysis(question: String) -> QuestionAnalysis {
        var matched: [SubExpert] = []
        var seen = Set<String>()
        for group in allExpertGroups.values {
            if group.routingKeywords.contains(where: { question.contains($0) }) {
                for e in group.subExperts.prefix(1) {
                    if seen.insert(e.name).inserted { matched.append(e) }
                }
            }
        }
        return QuestionAnalysis(
            question: question,
            characterization: "（关键词兜底路由）",
            experts: matched.isEmpty ? [contractGeneralExpert] : matched
        )
    }

    // MARK: - Info extraction

    private func autoExtractFacts(question: String, experts: [SubExpert]) -> [String: String] {
        var facts: [String: String] = [:]
        for expert in experts {
            for info in expert.requiredInfo where facts[info.field] == nil {
                guard !info.regexHint.isEmpty,
                      let regex = try? NSRegularExpression(pattern: info.regexHint),
                      let match = regex.firstMatch(in: question,
                                                   range: NSRange(question.startIndex..., in: question)),
                      let range = Range(match.range, in: question)
                else { continue }
                facts[info.field] = String(question[range])
            }
        }
        return facts
    }

    // MARK: - Step 4: Retrieval

    private func retrieveForExpert(expert: SubExpert, question: String,
                                   facts: [String: String]) -> [DatabaseManager.RAGArticle] {
        let db = DatabaseManager.shared
        var seenIds = Set<Int>()
        var results: [DatabaseManager.RAGArticle] = []

        func add(_ a: DatabaseManager.RAGArticle, pinned: Bool = false) {
            guard seenIds.insert(a.nodeId).inserted else { return }
            var copy = a; copy = DatabaseManager.RAGArticle(
                nodeId: a.nodeId, lawId: a.lawId, lawTitle: a.lawTitle,
                category: a.category, legalDomain: a.legalDomain,
                articleNumber: a.articleNumber, articleNum: a.articleNum,
                content: a.content, pinned: pinned || a.pinned)
            results.append(copy)
        }

        // 1. Chapter navigation via hint ids
        for lawTitle in expert.lawTitles {
            guard let lid = db.lawId(title: lawTitle) else { continue }
            let structure = db.lawStructure(lawId: lid)

            var chapterIds = expert.chapterIdHints
            // keyword-match structure titles
            let domainKws = expert.domain.components(separatedBy: CharacterSet(charactersIn: "、，"))
            for node in structure {
                let title = node.title.isEmpty ? node.content : node.title
                if domainKws.contains(where: { $0.count >= 2 && title.contains($0) }) {
                    if !chapterIds.contains(node.id) { chapterIds.append(node.id) }
                }
            }

            var count = 0
            for chId in chapterIds {
                let arts = db.articlesInNode(chId)
                for var art in arts {
                    art = DatabaseManager.RAGArticle(
                        nodeId: art.nodeId, lawId: lid, lawTitle: lawTitle,
                        category: "法律", legalDomain: "",
                        articleNumber: art.articleNumber, articleNum: art.articleNum,
                        content: art.content, pinned: true)
                    add(art, pinned: true)
                    count += 1
                    if count >= 30 { break }
                }
                if count >= 30 { break }
            }
        }

        // 2. FTS in primary laws
        let kws = simpleKeywords(from: question) + expert.ftsKeywordsExtra
        let lawCats   = ["法律", "宪法", "修正案", "法律解释", "监察法规"]
        let interpCats = ["司法解释"]

        for lawTitle in expert.lawTitles {
            for kw in kws {
                db.ftsSearchInLaw(keyword: kw, lawTitle: lawTitle,
                                  categories: lawCats + interpCats).forEach { add($0) }
            }
        }

        // 3. Domain FTS
        for kw in kws {
            db.ftsSearch(keyword: kw, domains: expert.ftsDomains, categories: lawCats,   limit: 8).forEach { add($0) }
            db.ftsSearch(keyword: kw, domains: expert.ftsDomains, categories: interpCats, limit: 5).forEach { add($0) }
        }

        return results
    }

    // MARK: - Reference expansion

    /// Compile a regex from a compile-time-constant pattern.
    /// `try!` is intentional: failure indicates a programming error in the pattern literal.
    private static func regex(_ pattern: String) -> NSRegularExpression {
        return try! NSRegularExpression(pattern: pattern)
    }

    private let crossLawPattern = LegalExpertService.regex(
        "《([^》]{4,30})》第([一二三四五六七八九十百千零\\d]+)条")
    private let selfRefPattern  = LegalExpertService.regex(
        "(?:本法|依照|适用|参照)第([一二三四五六七八九十百千零\\d]+)条")
    private let numberedQRE     = LegalExpertService.regex(
        #"(?:^|\n)\s*(?:\d+[、.．。）)）]|（\d+）|问题\s*[一二三四五六七八九十\d]+[、：:.]?)\s*(?=[^\n]{6,})"#)
    private let cjkKeywordRE   = LegalExpertService.regex("[\\u4E00-\\u9FFF]{3,6}")

    private func expandReferences(articles: [DatabaseManager.RAGArticle]) -> [DatabaseManager.RAGArticle] {
        let db = DatabaseManager.shared
        var seenIds = Set(articles.map { $0.nodeId })
        var extra: [DatabaseManager.RAGArticle] = []

        // Pass 1: 正则解析条文正文中的显式引用（《XX法》第Y条 / 本法第Y条）
        for art in articles {
            let content = art.content as NSString
            let range = NSRange(location: 0, length: content.length)
            for match in crossLawPattern.matches(in: art.content, range: range) {
                let lawFrag = content.substring(with: match.range(at: 1))
                let artNum  = "第\(content.substring(with: match.range(at: 2)))条"
                if let ref = db.articleByRef(lawTitleFragment: lawFrag, articleNumber: artNum),
                   seenIds.insert(ref.nodeId).inserted {
                    extra.append(ref)
                }
            }
            for match in selfRefPattern.matches(in: art.content, range: range) {
                let artNum = "第\(content.substring(with: match.range(at: 1)))条"
                if let ref = db.articleByRef(lawTitleFragment: art.lawTitle, articleNumber: artNum),
                   seenIds.insert(ref.nodeId).inserted {
                    extra.append(ref)
                }
            }
        }

        // Pass 2: article_references 表双向查找（出向 + 入向）
        let nodeIds = articles.map { $0.nodeId }
        let dbRefs = db.referencedArticles(nodeIds: nodeIds, excludingIds: seenIds)
        for ref in dbRefs {
            if seenIds.insert(ref.nodeId).inserted {
                extra.append(ref)
            }
        }

        return articles + extra
    }

    // Mod 4: filterArticles function removed entirely.
    // Expert prompts now include self-filter instruction instead.

    // MARK: - Step 4b: Expert analysis

    private func analyzeWithExpert(expert: SubExpert, question: String,
                                   facts: [String: String],
                                   articles: [DatabaseManager.RAGArticle]) async throws -> String {
        if articles.isEmpty {
            return "（\(expert.name)：未检索到相关条文，无法分析。）"
        }
        let cap      = maxContextArticles
        let ctxMax   = cap > 0 ? cap : 40
        let lawArts    = Array(articles.filter { $0.category != "司法解释" }.prefix(ctxMax * 2 / 3 + 1))
        let interpArts = Array(articles.filter { $0.category == "司法解释" }.prefix(ctxMax / 3 + 1))

        var parts: [String] = []
        if !lawArts.isEmpty {
            parts.append("【法律原文】")
            parts += lawArts.map { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(400)))" }
        }
        if !interpArts.isEmpty {
            parts.append("\n【司法解释】")
            parts += interpArts.map { "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(400)))" }
        }
        var factsText = ""
        if !facts.isEmpty {
            factsText = "\n\n【已知情况】\n" + facts.map { "- \($0.key)：\($0.value)" }.joined(separator: "\n")
        }
        let userMsg = "法条：\n\(parts.joined(separator: "\n"))\(factsText)\n\n用户问题：\(question)"
        // Mod 4: added self-filter instruction
        let systemWithConstraint = expert.answerTemplate + """

【严格限制】只能引用上方提供的法条，不得引用任何未在法条列表中出现的法律法规。
【重要】如果提供的法条与用户问题不直接相关，请明确说明"现有检索到的法条不足以回答此问题"，并说明需要什么信息或应查阅哪类法规，不得凭记忆编造法条内容或条文编号。
如果提供的法条中只有部分与问题直接相关，只引用相关的，忽略无关条文，不要为了引用而引用。
"""
        return try await chat(system: systemWithConstraint, user: userMsg)
    }

    // MARK: - Step 5: Group synthesis

    private let groupSynthSystem = """
    你是中国法律专家组负责人。将以下细分专家的分析整合成连贯的专业意见。
    要求：去除重复内容，保留最重要的结论；突出条文引用（保留《XXX》第X条格式）；总长度不超过400字。
    严禁使用任何Markdown格式，不得使用**加粗**、#标题、-列表符号等。用中文序号和标点代替。
    直接输出整合后的分析，不要说"根据以上分析"等套话。
    """

    private func synthesizeGroup(group: ExpertGroup,
                                  subAnswers: [String: String],
                                  question: String) async throws -> String {
        let combined = subAnswers.map { "【\($0.key)的分析】\n\($0.value)" }.joined(separator: "\n\n")
        return try await chat(system: groupSynthSystem,
                              user: "用户问题：\(question)\n\n\(combined)")
    }

    // MARK: - Step 6: Final answer context

    private var coordinatorSystemPrompt: String { """
    你是中国法律问题综合顾问。将多个专家组的分析整合为最终回答。
    重要原则：
    - 使用第三方客观视角，不预设提问者是哪方当事人（可能是当事人本人、家属、律师或第三方）
    - 法律判断（谁违约、谁承担责任、行为是否合法）由你独立作出，不要推给提问者判断
    - 【严格限制】只能引用"检索到的法条"中出现的条文。不得引用任何未在检索结果中列出的法律法规，即使你知道相关规定存在。
    - 【重要】如果检索到的法条不足以完整回答问题，明确说明哪部分无法回答及原因，不得编造条文编号或内容。
    - 【公报案例】如果上下文中提供了"人民法院公报相关案例"，可在回答中自然引用，格式：《案例标题》中确立的裁判规则……
    格式要求：
    1. 若只有一个问题：开头用一句话复述用户问题（如"关于XXX的问题："），再给出核心结论。
    2. 若有多个子问题：用中文序号（一、二、三）分段，每段开头复述该子问题（如"一、关于彩礼返还："），再给出该问题的结论和分析。
    3. 在分析中直接引用条文编号（如"依据第X条"），不要在末尾单独列出"引用法条"清单。
    4. 如涉及诉讼，注明应去哪个法院。
    5. 总长度400-800字。
    严禁使用任何Markdown格式：不得使用**加粗**、#标题、-列表符号、---分隔线等。用中文序号（一、二、三）、顿号、书名号代替。
    不要说"根据以上"、"综上所述"等空话。直接给结论。
    """ }

    private func buildGroupContext(groupAnswers: [String: String],
                                   articles: [DatabaseManager.RAGArticle],
                                   gazetteCites: [GazetteCitation] = []) -> String {
        let groupText = groupAnswers.map { "【\($0.key)】\n\($0.value)" }.joined(separator: "\n\n")
        let citeCap = maxCitationsLimit
        var seenCites = Set<String>()
        var citeLines = articles.compactMap { a -> String? in
            let key = "\(a.lawTitle)_\(a.articleNumber)"
            guard !a.articleNumber.isEmpty, seenCites.insert(key).inserted else { return nil }
            return "• 《\(a.lawTitle)》\(a.articleNumber) — \(String(a.content.prefix(60)))..."
        }
        if citeCap > 0 { citeLines = Array(citeLines.prefix(citeCap)) }
        var result = "各专家组分析：\n\(groupText)\n\n检索到的法条（供引用）：\n\(citeLines.joined(separator: "\n"))"
        if !gazetteCites.isEmpty {
            let caseSummary = gazetteCites.map { cite in
                "• 《\(cite.title)》裁判要点：\(cite.rulingGist.isEmpty ? "（无摘要）" : String(cite.rulingGist.prefix(100)))"
            }.joined(separator: "\n")
            result += "\n\n人民法院公报相关案例（可在回答中引用）：\n\(caseSummary)"
        }
        return result
    }

    // MARK: - Citation extraction

    // Extract articles cited in the answer text.
    // Strategy: parse《LawName》第X条 and bare 第X条; match against candidates first,
    // then fall back to DB lookup so citations always match what the LLM actually wrote.
    private func citationsFromAnswer(answerText: String,
                                     candidates: [DatabaseManager.RAGArticle]) -> [DatabaseManager.RAGArticle] {
        let db = DatabaseManager.shared

        // Pattern 1: 《法律名》第X条
        let namedPattern = try? NSRegularExpression(
            pattern: #"《([^》]{2,30})》第([一二三四五六七八九十百千零\d]+)条"#)
        // Pattern 2: bare 第X条
        let barePattern  = try? NSRegularExpression(
            pattern: #"第([一二三四五六七八九十百千零\d]+)条"#)

        let ns = answerText as NSString
        let range = NSRange(location: 0, length: ns.length)

        // Build a fast lookup from candidates by articleNum
        var candidateByNum: [Int: DatabaseManager.RAGArticle] = [:]
        for a in candidates { if let n = a.articleNum { candidateByNum[n] = a } }

        // Collect law_ids from candidates for fallback DB search
        let candidateLawIds = Array(Set(candidates.map { $0.lawId }).filter { $0 > 0 })

        var seenNodeIds = Set<Int>()
        var result: [DatabaseManager.RAGArticle] = []

        func add(_ a: DatabaseManager.RAGArticle) {
            guard seenNodeIds.insert(a.nodeId).inserted else { return }
            result.append(a)
        }

        // Named citations — only match against candidates actually shown to the LLM.
        // Do NOT fall back to DB lookup: if a named article isn't in candidates, the LLM
        // is drawing on training memory and the citation may be hallucinated or mismatched.
        if let re = namedPattern {
            for m in re.matches(in: answerText, range: range) {
                let lawFrag = ns.substring(with: m.range(at: 1))
                let numStr  = ns.substring(with: m.range(at: 2))
                guard let num = chineseOrArabicToInt(numStr) else { continue }
                if let a = candidateByNum[num], a.lawTitle.contains(lawFrag) {
                    add(a)
                }
            }
        }

        // Bare citations — candidates first, then restrict to same law_ids (no cross-law guessing)
        if let re = barePattern {
            for m in re.matches(in: answerText, range: range) {
                let numStr = ns.substring(with: m.range(at: 1))
                guard let num = chineseOrArabicToInt(numStr) else { continue }
                if let a = candidateByNum[num] {
                    add(a)
                } else if !candidateLawIds.isEmpty {
                    let artNum = "第\(numStr)条"
                    db.articlesByNumber(articleNumber: artNum, lawIds: candidateLawIds).forEach { add($0) }
                }
            }
        }

        return result
    }

    private func chineseOrArabicToInt(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let map: [Character: Int] = ["零":0,"一":1,"二":2,"三":3,"四":4,"五":5,
                                      "六":6,"七":7,"八":8,"九":9,"十":10,
                                      "百":100,"千":1000]
        var result = 0; var current = 0
        for ch in s {
            guard let v = map[ch] else { return nil }
            if v >= 10 {
                if current == 0 { current = 1 }
                result += current * v; current = 0
            } else { current = v }
        }
        return result + current
    }


    // MARK: - Helpers

    private func decomposeQuestion(_ question: String) async -> DecomposedQuestion {
        let none = DecomposedQuestion(preamble: "", questions: [])
        // Fast path: regex-split numbered questions (1. / 1、/ （1）/ 问题一 etc.)
        // Preamble = everything before the first numbered item; questions = each item alone.
        let numberedRE = numberedQRE
        let ns = question as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = numberedRE.matches(in: question, range: fullRange)

        if matches.count >= 2 {
            let firstStart = matches[0].range.location
            let preamble = ns.substring(to: firstStart).trimmingCharacters(in: .whitespacesAndNewlines)

            var items: [String] = []
            for (i, match) in matches.enumerated() {
                let itemStart = match.range.location
                let itemEnd   = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                let itemText  = ns.substring(with: NSRange(location: itemStart, length: itemEnd - itemStart))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if itemText.count > 8 { items.append(itemText) }
            }
            if items.count >= 2 { return DecomposedQuestion(preamble: preamble, questions: items) }
        }

        // Short simple questions: no LLM needed
        if question.count < 200 { return none }

        // LLM fallback for complex multi-issue questions without explicit numbering
        let prompt = """
        你是中国法律分析助手。阅读以下法律问题，判断是否包含多个需要独立分析的子问题。

        拆分规则：
        - 如果涉及多个完全不同的法律关系（如彩礼返还 + 抚养权 + 费用分担），必须拆分。
        - 同一法律关系的多个追问 → 不拆，输出 {"preamble":"","questions":[]}。
        - 最多拆分为4个子问题。

        输出要求（严格JSON，不要其他内容）：
        {
          "preamble": "所有子问题共用的案情事实摘要（如无共用事实则为空字符串）",
          "questions": ["纯粹的法律问题1，不含重复事实", "纯粹的法律问题2", ...]
        }
        - questions 中每条只写法律问题本身，事实已在 preamble 中，不要重复。
        - 无需拆分时 questions 为空数组 []。

        问题：
        \(question)
        """

        guard let raw  = try? await chat(system: "严格按指令输出JSON对象，不要其他内容。", user: prompt),
              let data = extractJSON(raw, open: "{", close: "}").data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr  = obj["questions"] as? [String]
        else { return none }

        let preamble = (obj["preamble"] as? String) ?? ""
        let items = arr.filter { $0.count > 5 }
        return items.count >= 2 ? DecomposedQuestion(preamble: preamble, questions: items) : none
    }


    private func deduplicateArticles(_ map: [String: [DatabaseManager.RAGArticle]]) -> [DatabaseManager.RAGArticle] {
        var seen = Set<Int>()
        var result: [DatabaseManager.RAGArticle] = []
        for arts in map.values {
            for a in arts where seen.insert(a.nodeId).inserted { result.append(a) }
        }
        return result
    }

    private func simpleKeywords(from text: String) -> [String] {
        let common = ["违约责任","合同解除","损害赔偿","劳动合同","经济补偿",
                      "工资拖欠","工伤认定","消费者权益","假冒伪劣",
                      "名誉权","隐私权","故意伤害","诉讼时效",
                      "合同诈骗","行政处罚","侵权责任","财产保全",
                      "婚姻家庭","遗产继承","股东权利","产品责任"]
        var found = common.filter { text.contains($0) }
        let pattern = cjkKeywordRE
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in pattern.matches(in: text, range: range) {
            let w = ns.substring(with: match.range)
            if !found.contains(w) { found.append(w) }
        }
        return Array(found.prefix(8))
    }

    private func chat(system: String, user: String) async throws -> String {
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user",   "content": user],
        ]
        return try await LLMProviderRegistry.agentProvider.chat(messages: messages, temperature: 0.05)
    }

    private func extractJSON(_ s: String, open: String, close: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = t.range(of: open)?.lowerBound,
              let b = t.range(of: close, options: .backwards)?.upperBound
        else { return t }
        return String(t[a..<b])
    }
}

// MARK: - Array helper

private extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
