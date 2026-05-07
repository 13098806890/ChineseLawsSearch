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

    // MARK: - Public entry point

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

        // Step 0: 拆分问题
        let subQs = await decomposeQuestion(question)
        onEvent(.thinkStep(name: "拆分问题",
                           content: subQs.isEmpty
                               ? "问题无需拆分，直接分析。"
                               : subQs.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")))
        if !subQs.isEmpty { onEvent(.subQuestions(subQs)) }

        // 用于路由和检索的合并文本（原问题 + 子问题）
        let enrichedQuestion = subQs.isEmpty ? question : question + "\n" + subQs.joined(separator: "\n")

        // Step 1: Route to expert groups
        let groupNames = await identifyGroups(question: enrichedQuestion)
        onEvent(.thinkStep(name: "专家路由",
                           content: "召集专家组：\(groupNames.joined(separator: "、"))"))

        let groups = groupNames.compactMap { allExpertGroups[$0] }

        // Step 2: Each group selects sub-experts
        var groupToExperts: [String: [SubExpert]] = [:]
        var allSelectedExperts: [SubExpert] = []
        var seenNames = Set<String>()

        for group in groups {
            let roughFacts = autoExtractFacts(question: enrichedQuestion, experts: group.subExperts)
            let selected = await identifySubExperts(group: group, question: enrichedQuestion, knownFacts: roughFacts)
            groupToExperts[group.name] = selected
            for e in selected where seenNames.insert(e.name).inserted {
                allSelectedExperts.append(e)
            }
        }

        let expertNames = allSelectedExperts.map { $0.name }
        onEvent(.thinkStep(name: "细分专家",
                           content: expertNames.joined(separator: "、")))

        // Step 3: Auto-extract facts from all conversation messages
        let allUserText = ([question] + conversationHistory.map { $0.user + " " + $0.assistant }).joined(separator: "\n")
        var mergedFacts = autoExtractFacts(question: allUserText, experts: allSelectedExperts)
        for (k, v) in knownFacts { mergedFacts[k] = v }

        // Follow-up: check for missing critical info when allowed
        if followUpRound < maxFollowUpRounds {
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
                if isLastRound || missingInfos.count == 1 {
                    // Last round or only one question: list all at once
                    let lines = missingInfos.enumerated().map { "\($0.offset + 1). \($0.element.question)" }
                    questionText = "为了提供更准确的分析，请补充以下事实信息：\n" + lines.joined(separator: "\n")
                } else {
                    // Ask the single most important missing field
                    questionText = missingInfos[0].question
                }
                onEvent(.clarifyingQuestion(questionText))
                return []
            }
        }

        let knownFacts = mergedFacts

        // Step 4: Each sub-expert retrieves + analyzes
        var expertArticles: [String: [DatabaseManager.RAGArticle]] = [:]
        var expertAnswers:  [String: String] = [:]

        for expert in allSelectedExperts {
            var articles = retrieveForExpert(expert: expert, question: enrichedQuestion, facts: knownFacts)
            articles = expandReferences(articles: articles)
            articles = filterArticles(question: enrichedQuestion, articles: articles)
            expertArticles[expert.name] = articles

            let answer = try await analyzeWithExpert(expert: expert, question: enrichedQuestion,
                                                     facts: knownFacts, articles: articles)
            expertAnswers[expert.name] = answer
        }

        let totalArticleCount = expertArticles.values.map { $0.count }.reduce(0, +)
        onEvent(.thinkStep(name: "专家检索",
                           content: "共检索 \(totalArticleCount) 条条文（\(allSelectedExperts.count) 位专家）"))

        // Step 5: Group synthesis
        var groupAnswers: [String: String] = [:]
        for group in groups {
            let experts = groupToExperts[group.name] ?? []
            let subAns = experts.compactMap { e -> (String, String)? in
                guard let ans = expertAnswers[e.name] else { return nil }
                return (e.name, ans)
            }
            guard !subAns.isEmpty else { continue }
            if subAns.count == 1 {
                groupAnswers[group.name] = subAns[0].1
            } else {
                let synthesis = try await synthesizeGroup(group: group, subAnswers: Dictionary(uniqueKeysWithValues: subAns), question: question)
                groupAnswers[group.name] = synthesis
            }
        }
        onEvent(.thinkStep(name: "专家组综合",
                           content: groupAnswers.keys.joined(separator: "、") + " 已完成分析"))

        // Step 6: Coordinator final answer (streamed)
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

        try await LLMProviderRegistry.current.streamChat(
            messages: [["role": "system", "content": systemPrompt],
                       ["role": "user",   "content": userMsg]],
            temperature: 0.2,
            onToken: { onEvent(.token($0)) }
        )

        // Step 7: Citation filter
        let candidates = Array(allArticlesFlat.prefix(12))
        let cited = try await filterCitations(question: question, candidates: candidates)
        onEvent(.thinkStep(name: "参考法条筛选",
                           content: "从 \(candidates.count) 条候选中筛出 \(cited.count) 条直接相关法条"))

        return cited.map {
            RAGCitation(lawId: $0.lawId, lawTitle: $0.lawTitle,
                        articleNumber: $0.articleNumber,
                        articleNum: $0.articleNum,
                        category: $0.category, content: $0.content)
        }
    }

    // MARK: - Step 1: Route

    private func identifyGroups(question: String) async -> [String] {
        let groupDesc = allExpertGroups.map { "- \($0.key)：\($0.value.description)" }.joined(separator: "\n")
        let system = """
        你是中国法律问题协调员。判断以下问题应由哪些专家组处理。
        可用专家组：
        \(groupDesc)
        规则：
        - 可以选多个专家组（如劳动争议诉讼 → 劳动法专家组 + 诉讼专家组）
        - 劳动关系问题（工资/解雇/加班/工伤/劳动合同）→ 劳动法专家组，不要选经济法专家组
        - 经济法专家组仅用于消费者权益、网购、产品质量、食品安全、公司注册等非劳动关系场景
        - 宁可多选，不要漏选
        只输出 JSON 数组，包含专家组名称。不要其他内容。示例：["民法专家组", "诉讼专家组"]
        """
        guard let raw = try? await chat(system: system, user: "问题：\(question)"),
              let data = extractJSON(raw, open: "[", close: "]").data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return keywordRoute(question: question) }
        let valid = arr.filter { allExpertGroups[$0] != nil }
        return valid.isEmpty ? keywordRoute(question: question) : valid
    }

    private func keywordRoute(question: String) -> [String] {
        var matched: [String] = []
        for (name, group) in allExpertGroups {
            if group.routingKeywords.contains(where: { question.contains($0) }) {
                matched.append(name)
            }
        }
        return matched.isEmpty ? Array(allExpertGroups.keys.prefix(2)) : matched
    }

    // MARK: - Step 2: Sub-experts

    private func identifySubExperts(group: ExpertGroup, question: String,
                                     knownFacts: [String: String]) async -> [SubExpert] {
        let expertDesc = group.subExperts.map { "- \($0.name)：\($0.domain)" }.joined(separator: "\n")
        let system = """
        你是\(group.name)。根据用户问题，从以下细分专家中选出需要参与分析的专家。
        细分专家：
        \(expertDesc)
        规则：只选与问题直接相关的专家（1-3个为宜）。
        只输出 JSON 数组，包含专家名称。不要其他内容。
        """
        var ctx = "问题：\(question)"
        if !knownFacts.isEmpty {
            ctx += "\n已知信息：" + knownFacts.map { "\($0.key)=\($0.value)" }.joined(separator: "；")
        }
        guard let raw  = try? await chat(system: system, user: ctx),
              let data = extractJSON(raw, open: "[", close: "]").data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return Array(group.subExperts.prefix(2)) }
        let nameMap = Dictionary(uniqueKeysWithValues: group.subExperts.map { ($0.name, $0) })
        let selected = arr.compactMap { nameMap[$0] }
        return selected.isEmpty ? Array(group.subExperts.prefix(1)) : selected
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
        // Just cap at 20 on iOS to avoid context blow-up; full LLM filter in analyzeWithExpert
        return Array(articles.prefix(20))
    }

    // MARK: - Step 4b: Expert analysis

    private func analyzeWithExpert(expert: SubExpert, question: String,
                                   facts: [String: String],
                                   articles: [DatabaseManager.RAGArticle]) async throws -> String {
        if articles.isEmpty {
            return "（\(expert.name)：未检索到相关条文，无法分析。）"
        }
        let lawArts    = Array(articles.filter { $0.category != "司法解释" }.prefix(10))
        let interpArts = Array(articles.filter { $0.category == "司法解释" }.prefix(5))

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
        return try await chat(system: expert.answerTemplate, user: userMsg)
    }

    // MARK: - Step 5: Group synthesis

    private let groupSynthSystem = """
    你是中国法律专家组负责人。将以下细分专家的分析整合成连贯的专业意见。
    要求：去除重复内容，保留最重要的结论；突出条文引用（保留《XXX》第X条格式）；总长度不超过400字。
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
    格式要求：
    1. 开头直接给出各问题的核心结论（逐条列出）
    2. 按问题或专家组分段陈述详细法律分析
    3. 末尾列出"⚖️ 引用法条"（格式：• 《法律名》第X条 — 摘要）
    4. 如涉及诉讼，注明应去哪个法院
    5. 总长度500-900字
    不要说"根据以上"、"综上所述"等空话。直接给结论。
    """ }

    private func buildGroupContext(groupAnswers: [String: String],
                                   articles: [DatabaseManager.RAGArticle]) -> String {
        let groupText = groupAnswers.map { "【\($0.key)】\n\($0.value)" }.joined(separator: "\n\n")
        var seenCites = Set<String>()
        let citeLines = articles.compactMap { a -> String? in
            let key = "\(a.lawTitle)_\(a.articleNumber)"
            guard !a.articleNumber.isEmpty, seenCites.insert(key).inserted else { return nil }
            return "• 《\(a.lawTitle)》\(a.articleNumber) — \(String(a.content.prefix(60)))..."
        }.prefix(15)
        return "各专家组分析：\n\(groupText)\n\n检索到的法条（供引用）：\n\(citeLines.joined(separator: "\n"))"
    }

    // MARK: - Citation filter

    private func filterCitations(question: String,
                                  candidates: [DatabaseManager.RAGArticle]) async -> [DatabaseManager.RAGArticle] {
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

    // MARK: - Helpers

    private func decomposeQuestion(_ question: String) async -> [String] {
        // Fast path: detect explicitly numbered questions (1、2、3 or 1. 2. 3)
        let numberedPattern = try? NSRegularExpression(
            pattern: #"(?:^|\n)\s*[①②③④⑤⑥⑦⑧⑨⑩]|(?:^|\n)\s*\d+[、.．。]\s*[^\n]{5,}"#)
        let ns = question as NSString
        let matches = numberedPattern?.matches(in: question, range: NSRange(location: 0, length: ns.length)) ?? []
        if matches.count >= 2 {
            // Extract each numbered item as a sub-question, preserving background context
            // Find the "background" preamble (text before the first numbered item)
            var items: [String] = []
            var ranges: [NSRange] = matches.map { $0.range }
            let preambleEnd = ranges[0].location
            let background = preambleEnd > 10
                ? String(question[..<question.index(question.startIndex, offsetBy: min(preambleEnd, question.count))])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            for i in 0..<ranges.count {
                let start = ranges[i].location
                let end   = i + 1 < ranges.count ? ranges[i+1].location : ns.length
                var item  = ns.substring(with: NSRange(location: start, length: end - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !background.isEmpty {
                    item = background + "\n" + item
                }
                if !item.isEmpty { items.append(item) }
            }
            if items.count >= 2 { return items }
        }

        // Fallback: ask LLM
        let prompt = """
        你是中国法律助手。判断用户的问题是否包含多个独立的法律子问题（如同时涉及请求权和诉讼程序，或多个不同法律关系）。
        如果问题简单或只有一个核心问题，输出空数组 []。
        如果可以拆分，输出2-4个子问题的JSON数组，每个子问题都需要包含详细的上下文（案情背景）。
        只输出JSON数组，不要其他内容。
        """
        guard let raw  = try? await chat(system: prompt, user: "问题：\(question)"),
              let data = extractJSON(raw, open: "[", close: "]").data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [String],
              arr.count >= 2
        else { return [] }
        return arr.filter { !$0.isEmpty }
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
