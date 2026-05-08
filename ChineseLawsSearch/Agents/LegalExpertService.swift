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

    /// Result of decomposing a multi-question input.
    struct DecomposedQuestion {
        let preamble:  String    // shared factual context (empty if none)
        let questions: [String]  // individual questions (empty = no split needed)
    }

    // MARK: - Public entry point

    /// Decompose a question into preamble + individual sub-questions.
    func decomposeWithFacts(question: String) async -> DecomposedQuestion {
        await decomposeQuestion(question)
    }

    /// Classify the user's message intent before routing.
    /// - Parameters:
    ///   - message: Current user input
    ///   - history: Recent conversation turns (last 2 used)
    func classifyIntent(message: String,
                        history: [(user: String, assistant: String)]) async -> MessageIntent {
        // Fast-path: no history + very short message with no legal keywords → off_topic
        let legalKeywords = ["合同","侵权","违约","诉讼","法院","赔偿","解除","仲裁",
                             "劳动","离婚","继承","公司","股东","刑事","行政","执行",
                             "借款","担保","抵押","保证","租赁","房屋","土地","消费者"]
        let hasLegal = legalKeywords.contains { message.contains($0) }
        if history.isEmpty && message.count < 15 && !hasLegal {
            return .offTopic
        }

        let recentHistory = history.suffix(2)
            .map { "用户：\($0.user)\n助手：\($0.assistant.prefix(100))" }
            .joined(separator: "\n---\n")
        let historySection = recentHistory.isEmpty ? "（无历史对话）" : recentHistory

        let system = """
        你是意图分类器。判断用户消息属于以下哪种类型，输出JSON（严格格式，不要其他内容）：
        {"intent": "<类型>"}

        类型说明：
        - "case"：用户陈述具体纠纷事实，包含当事人、争议内容、损失、时间等具体信息
        - "follow_up"：基于历史对话中已有的**具体案情**继续追问，如"那我应该去哪个法院"、"这种情况能否申请保全"
        - "law_lookup"：用户想查某条具体法律规定、某部法律的内容、某类行为的法律规范，如"合同法第几条规定了违约金"、"未成年人保护法对网络游戏有什么规定"、"酒驾的法律标准是什么"、"劳动法规定试用期最长多久"
        - "general"：法律知识提问或使用咨询，不依赖具体案情，如"什么是连带责任"、"我应该怎么描述我的问题"、"你能帮我做什么"
        - "off_topic"：问候、闲聊、与法律无关的内容，以及询问 app 使用方式、对话格式等功能性问题

        注意：
        - "follow_up" 必须以历史对话中存在明确的具体案情为前提；若历史对话中没有案情，只有 off_topic/general 回复，则当前消息不能判定为 follow_up
        - "law_lookup" 优先于 "general"：如果用户明确在查某条规定或某部法律的具体内容，判定为 law_lookup，不是 general
        - 询问"如何输入问题"、"需要什么格式"、"你是谁"等使用引导性问题属于 off_topic
        - 有历史对话时，如果用户引入了与之前完全不同的新案情，判定为 "case"
        - 无历史对话时，纯法律知识问题判定为 "general" 或 "law_lookup"，不要判定为 "case"
        """
        let user = "历史对话：\n\(historySection)\n\n当前消息：\(message)"

        guard let raw  = try? await chat(system: system, user: user),
              let data = extractJSON(raw, open: "{", close: "}").data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let intentStr = obj["intent"] as? String,
              let intent = MessageIntent(rawValue: intentStr)
        else {
            // fallback: if history exists assume follow_up, otherwise case
            return history.isEmpty ? .caseNarration : .followUp
        }
        return intent
    }

    /// Handle a general legal knowledge question.
    /// Uses LLM to decide if simple (FTS + direct answer) or complex (full pipeline, no clarifying).
    func askGeneral(question: String,
                    onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
        // Ask LLM whether the question is simple or complex
        let complexityPrompt = """
        判断以下法律知识问题的复杂度，输出JSON：{"complexity": "simple" | "complex"}
        - simple：涉及单一法条查询或基础概念解释（如诉讼时效、管辖权等）
        - complex：涉及多个法律领域或需要综合分析（如多种责任竞合、程序+实体结合等）
        问题：\(question)
        """
        let complexityRaw = (try? await chat(system: "只输出JSON，不要其他内容。", user: complexityPrompt)) ?? ""
        let isComplex: Bool
        if let data = extractJSON(complexityRaw, open: "{", close: "}").data(using: .utf8),
           let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let val  = obj["complexity"] as? String {
            isComplex = (val == "complex")
        } else {
            isComplex = false
        }

        onEvent(.thinkStep(name: "问题类型", content: isComplex ? "综合法律问题 → 专家分析" : "知识查询 → 直接检索"))

        if isComplex {
            // Full pipeline but skip clarifying questions (maxFollowUpRounds = 0)
            return try await runPipeline(question: question, factContext: "", subQs: [],
                                         conversationHistory: [], knownFacts: [:],
                                         followUpRound: 0, maxFollowUpRounds: 0,
                                         onEvent: onEvent)
        } else {
            // Simple: broad FTS across all domains + single LLM call
            let keywords = simpleKeywords(from: question)
            let db = DatabaseManager.shared
            var seenIds = Set<Int>()
            var articles: [DatabaseManager.RAGArticle] = []
            let allDomains = ["民法典", "民法商法", "刑法", "行政法", "经济法", "社会法", "诉讼与非诉讼程序法"]
            let cats = ["法律", "宪法", "修正案", "法律解释", "司法解释"]
            for kw in keywords.prefix(4) {
                for a in db.ftsSearch(keyword: kw, domains: allDomains, categories: cats, limit: 5) {
                    if seenIds.insert(a.nodeId).inserted { articles.append(a) }
                }
            }
            let topArticles = Array(articles.prefix(10))
            onEvent(.thinkStep(name: "法条检索", content: "检索到 \(topArticles.count) 条相关条文"))

            let citations = topArticles.map {
                RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                            articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                            category: $0.category, content: $0.content)
            }
            let artText = topArticles.map {
                "《\($0.lawTitle)》\($0.articleNumber)：\(String($0.content.prefix(300)))"
            }.joined(separator: "\n")

            let systemPrompt = """
            你是中国法律顾问。根据提供的法条，简明扼要地回答用户的法律知识问题。
            直接给出答案，引用条文编号。严禁使用Markdown格式。总长度不超过300字。
            """
            let userMsg = "法条：\n\(artText)\n\n问题：\(question)"
            try await LLMProviderRegistry.current.streamChat(
                messages: [["role": "system", "content": systemPrompt],
                           ["role": "user",   "content": userMsg]],
                temperature: 0.1,
                onToken: { onEvent(.token($0)) }
            )
            return citations
        }
    }

    /// Handle a law/regulation lookup — user wants to find specific provisions.
    /// Extracts law name + topic keywords, does precise FTS, returns full articles + explanation.
    func askLawLookup(question: String,
                      onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
        onEvent(.thinkStep(name: "法条查询", content: "识别目标法律和查询关键词…"))

        // Step 1: LLM extracts target law name + keywords
        let extractPrompt = """
        用户想查找特定法律规定。从问题中提取检索信息，输出JSON：
        {"law": "完整法律名称或空字符串", "keywords": ["词1", "词2", "词3"]}

        关键词提取规则：
        - 每个关键词必须是**单个最小语义单元**（2-4个汉字），不要提取组合短语
        - 优先使用法条中的规范用语，例如：
          用户说"噪音施工时间" → 提取 ["施工噪声", "禁止", "夜间"] 而不是 ["噪音施工时间"]
          用户说"酒驾标准" → 提取 ["饮酒", "驾驶", "血液酒精"] 而不是 ["酒驾标准"]
          用户说"试用期最长多久" → 提取 ["试用期", "期限"] 而不是 ["试用期最长"]
        - 提取3-5个词，覆盖问题的不同维度（主体、行为、后果、时间等）
        - 如果问题明确提到法律名称，填入"law"字段（写完整名称，如"中华人民共和国噪声污染防治法"）

        问题：\(question)
        """
        let extractRaw = (try? await chat(system: "只输出JSON，不要其他内容。", user: extractPrompt)) ?? ""
        var targetLaw = ""
        var keywords: [String] = []
        if let data = extractJSON(extractRaw, open: "{", close: "}").data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            targetLaw = (obj["law"] as? String) ?? ""
            keywords  = (obj["keywords"] as? [String]) ?? []
        }
        if keywords.isEmpty { keywords = simpleKeywords(from: question) }

        let db = DatabaseManager.shared
        var seenIds = Set<Int>()
        var articles: [DatabaseManager.RAGArticle] = []
        let allDomains = ["宪法相关法", "民法典", "民法商法", "刑法",
                          "行政法", "经济法", "社会法", "诉讼与非诉讼程序法"]
        let allCats = ["法律", "宪法", "修正案", "法律解释", "司法解释", "行政法规", "监察法规"]

        // Boost: if target law name given, search within that law first
        if !targetLaw.isEmpty {
            for kw in keywords.prefix(4) {
                for a in db.ftsSearch(keyword: kw, domains: allDomains, categories: allCats, limit: 8) {
                    if a.lawTitle.contains(targetLaw) || targetLaw.contains(a.lawTitle) {
                        if seenIds.insert(a.nodeId).inserted { articles.append(a) }
                    }
                }
            }
        }
        // Fallback / supplement: broad search
        for kw in keywords.prefix(5) {
            for a in db.ftsSearch(keyword: kw, domains: allDomains, categories: allCats, limit: 6) {
                if seenIds.insert(a.nodeId).inserted { articles.append(a) }
            }
        }

        // Filter out unrelated articles using the same relevance check as expert pipeline
        let filtered = filterArticles(question: question, articles: articles)
        let topArticles = Array((filtered.isEmpty ? articles : filtered).prefix(15))
        let lawInfo = targetLaw.isEmpty ? "全库检索" : "目标：《\(targetLaw)》"
        onEvent(.thinkStep(name: "法条检索",
                           content: "\(lawInfo)，关键词：\(keywords.joined(separator: "、"))，命中 \(topArticles.count) 条（过滤后）"))

        if topArticles.isEmpty {
            let kws = keywords.joined(separator: "、")
            let msg = targetLaw.isEmpty
                ? "未找到与「\(kws)」相关的法律条文，请尝试换用其他关键词。"
                : "未找到《\(targetLaw)》中与「\(kws)」相关的条文，请确认法律名称或关键词。"
            onEvent(.token(msg))
            return []
        }

        let citations = topArticles.map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                        articleNumber: $0.articleNumber, articleNum: $0.articleNum,
                        category: $0.category, content: $0.content)
        }
        let artText = topArticles.map {
            "《\($0.lawTitle)》\($0.articleNumber)：\($0.content)"
        }.joined(separator: "\n\n")

        let systemPrompt = """
        你是中国法律条文检索助手。根据检索到的法条，直接引用原文回答用户的查询。
        - 先点名具体是哪部法律第几条
        - 引用条文原文（可适当截取关键句）
        - 如有多条相关条文，逐条列出
        - 不要发表评论，不要推测案情，只陈述法条规定
        - 严禁使用Markdown格式
        """
        let userMsg = "相关法条：\n\(artText)\n\n用户查询：\(question)"
        try await LLMProviderRegistry.current.streamChat(
            messages: [["role": "system", "content": systemPrompt],
                       ["role": "user",   "content": userMsg]],
            temperature: 0.05,
            onToken: { onEvent(.token($0)) }
        )
        return citations
    }

    /// Handle a follow-up question, reusing previously selected experts.
    /// If the question touches new legal domains, merges in additional experts.
    func askFollowUp(question: String,
                     lastExperts: [SubExpert],
                     conversationHistory: [(user: String, assistant: String)],
                     knownFacts: [String: String],
                     onEvent: @escaping (RAGEvent) -> Void) async throws -> ([RAGCitation], [SubExpert]) {
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

    /// Legacy shim — returns only question strings (preamble absorbed into each).
    func decompose(question: String) async -> [String] {
        let d = await decomposeQuestion(question)
        if d.questions.isEmpty { return [] }
        return d.questions.map { q in
            d.preamble.isEmpty ? q : "\(d.preamble)\n\n\(q)"
        }
    }

    /// Analyze a single (already-decomposed) question — no further decomposition.
    func askSingle(question: String,
                   factContext: String = "",
                   conversationHistory: [(user: String, assistant: String)] = [],
                   knownFacts: [String: String] = [:],
                   followUpRound: Int = 0,
                   maxFollowUpRounds: Int = 3,
                   onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
        try await runPipeline(question: question, factContext: factContext, subQs: [],
                              conversationHistory: conversationHistory,
                              knownFacts: knownFacts,
                              followUpRound: followUpRound,
                              maxFollowUpRounds: maxFollowUpRounds,
                              onEvent: onEvent)
    }

    /// Main entry — also called by LegalChatViewModel.send() as the RAGService-compatible overload.
    func ask(question: String,
             onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
        try await ask(question: question, conversationHistory: [],
                      knownFacts: [:], followUpRound: 0, maxFollowUpRounds: 3,
                      onEvent: onEvent)
    }

    func ask(question: String,
             conversationHistory: [(user: String, assistant: String)],
             knownFacts: [String: String],
             followUpRound: Int,
             maxFollowUpRounds: Int,
             onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
        let decomposed = await decomposeQuestion(question)
        let subQs = decomposed.questions
        let displayLines = subQs.isEmpty
            ? "问题无需拆分，直接分析。"
            : subQs.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")
        onEvent(.thinkStep(name: "拆分问题", content: displayLines))
        if !subQs.isEmpty { onEvent(.subQuestions(subQs)) }
        return try await runPipeline(question: question, factContext: decomposed.preamble, subQs: subQs,
                                     conversationHistory: conversationHistory,
                                     knownFacts: knownFacts,
                                     followUpRound: followUpRound,
                                     maxFollowUpRounds: maxFollowUpRounds,
                                     onEvent: onEvent)
    }

    // MARK: - Core pipeline (shared by ask and askSingle)

    private func runPipeline(question: String,
                              factContext: String,
                              subQs: [String],
                              conversationHistory: [(user: String, assistant: String)],
                              knownFacts: [String: String],
                              followUpRound: Int,
                              maxFollowUpRounds: Int,
                              onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {

        let questionsToAnalyze = subQs.isEmpty ? [question] : subQs

        // Step 1: 递进式法律定性 + 按需路由（每个子问题独立定性）
        var questionAnalyses: [QuestionAnalysis] = []
        var allSelectedExperts: [SubExpert] = []
        var expertToQuestions:  [String: [String]] = [:]
        var seenNames = Set<String>()

        for q in questionsToAnalyze {
            let analysis = await characterizeAndRoute(question: q, knownFacts: [:])
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
                                         onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
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
                                  onEvent: @escaping (RAGEvent) -> Void) async throws -> [RAGCitation] {
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

        // Step 3: 每个专家检索并分析其负责的子问题
        var expertArticles: [String: [DatabaseManager.RAGArticle]] = [:]
        var expertAnswers:  [String: String] = [:]

        for expert in allSelectedExperts {
            let assignedQs   = expertToQuestions[expert.name] ?? [question]
            let questionText = assignedQs.count == 1 ? assignedQs[0] : assignedQs.joined(separator: "\n")
            // Expert gets: shared factual preamble (if any) + question text
            let expertContext = factContext.isEmpty ? questionText : "\(factContext)\n\n\(questionText)"

            var articles = retrieveForExpert(expert: expert, question: expertContext, facts: knownFacts)
            articles = expandReferences(articles: articles)
            articles = filterArticles(question: expertContext, articles: articles)
            expertArticles[expert.name] = articles

            let answer = try await analyzeWithExpert(expert: expert, question: expertContext,
                                                     facts: knownFacts, articles: articles)
            expertAnswers[expert.name] = answer
        }

        let totalArticleCount = expertArticles.values.map { $0.count }.reduce(0, +)
        let allArticlesForDisplay = deduplicateArticles(expertArticles).map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle, articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum, category: $0.category, content: $0.content)
        }
        onEvent(.thinkStepWithArticles(
            name: "专家检索",
            content: "共检索 \(totalArticleCount) 条条文（\(allSelectedExperts.count) 位专家）",
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
        for (groupName, expertNames) in groupToExpertNames {
            guard let group = allExpertGroups[groupName] else { continue }
            let subAns = expertNames.compactMap { name -> (String, String)? in
                guard let ans = expertAnswers[name] else { return nil }
                return (name, ans)
            }
            guard !subAns.isEmpty else { continue }
            if subAns.count == 1 {
                groupAnswers[groupName] = subAns[0].1
            } else {
                let synthesis = try await synthesizeGroup(
                    group: group,
                    subAnswers: Dictionary(uniqueKeysWithValues: subAns),
                    question: question)
                groupAnswers[groupName] = synthesis
            }
        }
        onEvent(.thinkStep(name: "专家组综合",
                           content: groupAnswers.keys.joined(separator: "、") + " 已完成分析"))

        // Step 5: Coordinator 最终回答（流式，同时收集全文用于法条匹配）
        let allArticlesFlat = deduplicateArticles(expertArticles)
        let context = buildGroupContext(groupAnswers: groupAnswers, articles: allArticlesFlat)
        let systemPrompt = coordinatorSystemPrompt
        var userMsg = "用户问题：\(question)\n\n"
        if !subQs.isEmpty {
            userMsg += "问题已拆分为以下子问题，请逐一回答：\n"
            userMsg += subQs.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")
            userMsg += "\n\n"
        }
        userMsg += context

        var answerText = ""
        try await LLMProviderRegistry.current.streamChat(
            messages: [["role": "system", "content": systemPrompt],
                       ["role": "user",   "content": userMsg]],
            temperature: 0.2,
            onToken: { token in
                answerText += token
                onEvent(.token(token))
            }
        )

        // Step 6: 参考法条 — 从答案正文中提取引用的条文编号，匹配已检索到的条文
        let cited = citationsFromAnswer(answerText: answerText, candidates: allArticlesFlat)
        onEvent(.thinkStep(name: "参考法条筛选",
                           content: "从答案正文引用中提取 \(cited.count) 条直接引用的法条"))

        return cited.map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                        articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum,
                        category: $0.category, content: $0.content)
        }
    }

    // MARK: - 法律定性 + 递进路由

    private struct QuestionAnalysis {
        let question: String
        let characterization: String   // 多层定性描述
        let experts: [SubExpert]
    }

    private func characterizeAndRoute(question: String,
                                       knownFacts: [String: String]) async -> QuestionAnalysis {
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

    private let crossLawPattern = try! NSRegularExpression(
        pattern: "《([^》]{4,30})》第([一二三四五六七八九十百千零\\d]+)条")
    private let selfRefPattern  = try! NSRegularExpression(
        pattern: "(?:本法|依照|适用|参照)第([一二三四五六七八九十百千零\\d]+)条")

    private func expandReferences(articles: [DatabaseManager.RAGArticle]) -> [DatabaseManager.RAGArticle] {
        let db = DatabaseManager.shared
        var seenIds = Set(articles.map { $0.nodeId })
        var extra: [DatabaseManager.RAGArticle] = []
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
        return articles + extra
    }

    // MARK: - Article filter (light, non-streaming)

    private func filterArticles(question: String,
                                articles: [DatabaseManager.RAGArticle]) -> [DatabaseManager.RAGArticle] {
        guard articles.count > 5 else { return articles }
        let cap = UserDefaults.standard.integer(forKey: "maxContextArticles")
        return Array(articles.prefix(cap > 0 ? cap : 20))
    }

    // MARK: - Step 4b: Expert analysis

    private func analyzeWithExpert(expert: SubExpert, question: String,
                                   facts: [String: String],
                                   articles: [DatabaseManager.RAGArticle]) async throws -> String {
        if articles.isEmpty {
            return "（\(expert.name)：未检索到相关条文，无法分析。）"
        }
        let cap      = UserDefaults.standard.integer(forKey: "maxContextArticles")
        let ctxMax   = cap > 0 ? cap : 20
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
        let systemWithConstraint = expert.answerTemplate + "\n【严格限制】只能引用上方提供的法条，不得引用任何未在法条列表中出现的法律法规。"
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
    格式要求：
    1. 开头直接给出核心结论
    2. 按问题或专家组分段陈述详细法律分析，在分析中直接引用条文编号（如"依据第X条"）
    3. 不要在末尾单独列出"引用法条"清单，引用已在分析中体现
    4. 如涉及诉讼，注明应去哪个法院
    5. 总长度400-800字
    严禁使用任何Markdown格式：不得使用**加粗**、#标题、-列表符号、---分隔线等。用中文序号（一、二、三）、顿号、书名号代替。
    不要说"根据以上"、"综上所述"等空话。直接给结论。
    """ }

    private func buildGroupContext(groupAnswers: [String: String],
                                   articles: [DatabaseManager.RAGArticle]) -> String {
        let groupText = groupAnswers.map { "【\($0.key)】\n\($0.value)" }.joined(separator: "\n\n")
        let citeCap = UserDefaults.standard.integer(forKey: "maxCitations")
        var seenCites = Set<String>()
        var citeLines = articles.compactMap { a -> String? in
            let key = "\(a.lawTitle)_\(a.articleNumber)"
            guard !a.articleNumber.isEmpty, seenCites.insert(key).inserted else { return nil }
            return "• 《\(a.lawTitle)》\(a.articleNumber) — \(String(a.content.prefix(60)))..."
        }
        if citeCap > 0 { citeLines = Array(citeLines.prefix(citeCap)) }
        return "各专家组分析：\n\(groupText)\n\n检索到的法条（供引用）：\n\(citeLines.joined(separator: "\n"))"
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

        // Named citations — highest confidence
        if let re = namedPattern {
            for m in re.matches(in: answerText, range: range) {
                let lawFrag = ns.substring(with: m.range(at: 1))
                let numStr  = ns.substring(with: m.range(at: 2))
                guard let num = chineseOrArabicToInt(numStr) else { continue }
                if let a = candidateByNum[num], a.lawTitle.contains(lawFrag) {
                    add(a)
                } else {
                    // DB lookup by law name fragment + article number
                    let artNum = "第\(numStr)条"
                    db.articlesByNumber(articleNumber: artNum, lawTitleFragment: lawFrag).forEach { add($0) }
                }
            }
        }

        // Bare citations — use candidates first, then DB with law_ids scope
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

        return result.isEmpty ? candidates : result
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
        let numberedRE = try! NSRegularExpression(
            pattern: #"(?:^|\n)\s*(?:\d+[、.．。）)）]|（\d+）|问题\s*[一二三四五六七八九十\d]+[、：:.]?)\s*(?=[^\n]{6,})"#)
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
        - 如果涉及多个完全不同的法律关系（如合同纠纷 + 侵权 + 继承），必须拆分。
        - 同一法律关系的多个追问 → 不拆，输出 []。
        - 每个子问题必须包含完整案情背景，使其可以独立被理解和分析。
        - 最多拆分为4个子问题。

        输出要求：
        - 需要拆分：输出JSON数组，每个元素是一个包含案情背景+该问题的完整字符串。
        - 无需拆分：输出空数组 []。
        - 只输出JSON数组，不要任何其他内容。

        问题：
        \(question)
        """

        guard let raw  = try? await chat(system: "严格按指令输出JSON数组，不要其他内容。", user: prompt),
              let data = extractJSON(raw, open: "[", close: "]").data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return none }

        let items = arr.filter { $0.count > 10 }
        return items.count >= 2 ? DecomposedQuestion(preamble: "", questions: items) : none
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
        let pattern = try! NSRegularExpression(pattern: "[\\u4E00-\\u9FFF]{3,6}")
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
        return try await LLMProviderRegistry.current.chat(messages: messages, temperature: 0.05)
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
