//
//  AgentIntegrationTests.swift
//  ChineseLawsSearchTests
//
//  Integration tests: real LLM pipeline + LLM-as-Judge scoring (0-10, pass ≥ 8).
//  Results are written to ~/Desktop/agent_test_results.json after each run.
//
//  The API key is injected at test startup via injectAPIKeyIfNeeded().
//

import Testing
import Foundation
@testable import ChineseLawsSearch

// MARK: - Result record

private struct TestRecord: Codable {
    let testId:     String
    let category:   String
    let question:   String
    let mode:       String
    let answer:     String
    let citations:  [CitationRecord]
    let judgeScore: Int          // 0-10
    let judgeReason: String
    let passed:     Bool         // score >= 8
    let answerChars: Int
    let citationCount: Int
    let durationSeconds: Double
}

private struct CitationRecord: Codable {
    let lawTitle: String
    let articleNumber: String
    let category: String
    let contentPreview: String   // first 80 chars
}

private struct TestReport: Codable {
    let runAt:        String
    let totalTests:   Int
    let passedTests:  Int
    let failedTests:  Int
    let passRate:     String
    let results:      [TestRecord]
}

// MARK: - Judge

private func judgeAnswer(question: String, answer: String, criteria: String) async -> (score: Int, reason: String) {
    let system = """
    你是中国法律问答质量评审员。对下面的回答打分（0-10分整数），并用一句话说明理由。

    评分标准：
    10 = 回答准确全面、引用法条正确、直接解决问题
    8-9 = 基本正确，有小瑕疵（措辞模糊或遗漏次要点）
    6-7 = 部分回答了问题，有明显遗漏或模糊
    4-5 = 方向正确但内容严重不足或有错误
    0-3 = 与问题无关、完全错误，或只说"不知道"

    额外要求：\(criteria)

    输出JSON（严格格式，不要其他内容）：
    {"score": <0-10>, "reason": "<一句话>"}
    """
    let user = "【问题】\(question)\n\n【回答】\(answer)"
    guard let raw = try? await LLMProviderRegistry.current.chat(
        messages: [["role": "system", "content": system],
                   ["role": "user",   "content": user]],
        temperature: 0
    ) else { return (0, "judge call failed") }

    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("```") { t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n") }
    if t.hasSuffix("```") { t = String(t.dropLast(3)) }
    guard let s = t.firstIndex(of: "{"), let e = t.lastIndex(of: "}"),
          let data = String(t[s...e]).data(using: .utf8),
          let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let score  = obj["score"]  as? Int,
          let reason = obj["reason"] as? String
    else { return (0, "parse failed: \(raw.prefix(120))") }
    return (score, reason)
}

// MARK: - Pipeline runner

private func runPipeline(question: String,
                          mode: QueryMode,
                          history: [(user: String, assistant: String)] = []) async throws
    -> (answer: String, citations: [RAGCitation]) {
    var answer = ""
    var citations: [RAGCitation] = []
    (citations, _) = try await LegalExpertService.shared.askLegalQuery(
        question: question,
        conversationHistory: history,
        knownFacts: [:],
        followUpRound: 0,
        maxFollowUpRounds: 0,
        preClassifiedMode: mode
    ) { if case .token(let t) = $0 { answer += t } }
    return (answer, citations)
}

// MARK: - Shared state for report accumulation

// Swift Testing runs each @Test as an independent instance, so we write individual
// JSON fragments and merge them at the end via a dedicated "report" test that
// depends on all others being done. Simpler: accumulate via actor.

private actor ResultStore {
    static let shared = ResultStore()
    private var records: [TestRecord] = []
    func append(_ r: TestRecord) { records.append(r) }
    func all() -> [TestRecord] { records }
}

// MARK: - Per-test helper

/// Run one full test case: pipeline + judge + record.
/// Returns the TestRecord so the @Test can also assert pass/fail.
private func runCase(testId: String,
                     category: String,
                     question: String,
                     mode: QueryMode,
                     criteria: String,
                     requiredLawFragment: String? = nil,
                     history: [(user: String, assistant: String)] = []) async throws -> TestRecord {
    let start = Date()
    let (answer, citations) = try await runPipeline(question: question, mode: mode, history: history)
    let elapsed = Date().timeIntervalSince(start)

    let (score, reason) = await judgeAnswer(question: question, answer: answer, criteria: criteria)

    let citRecords = citations.map {
        CitationRecord(lawTitle: $0.lawTitle,
                       articleNumber: $0.articleNumber,
                       category: $0.category,
                       contentPreview: String($0.content.prefix(80)))
    }

    let record = TestRecord(
        testId:          testId,
        category:        category,
        question:        question,
        mode:            mode.rawValue,
        answer:          answer,
        citations:       citRecords,
        judgeScore:      score,
        judgeReason:     reason,
        passed:          score >= 8,
        answerChars:     answer.count,
        citationCount:   citations.count,
        durationSeconds: elapsed
    )
    await ResultStore.shared.append(record)
    let status = record.passed ? "✅" : "❌"
    print("\(status) [\(testId)] score=\(score)/10 chars=\(record.answerChars) cites=\(record.citationCount) | \(reason)")
    return record
}

// MARK: - Key injection

private func injectAPIKeyIfNeeded() {
    let key = "deepseek_api_key"
    if (KeychainHelper.loadLocal(forKey: key) ?? KeychainHelper.load(forKey: key) ?? "").isEmpty {
        // Set DEEPSEEK_API_KEY in the scheme's environment variables before running integration tests.
        guard let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty else {
            XCTFail("DEEPSEEK_API_KEY environment variable not set — cannot run integration tests")
            return
        }
        KeychainHelper.saveLocal(envKey, forKey: key)
    }
}

// MARK: - Write report

private func writeReport() async {
    let records = await ResultStore.shared.all()
    guard !records.isEmpty else { return }
    let passed = records.filter { $0.passed }.count
    let report = TestReport(
        runAt:       ISO8601DateFormatter().string(from: Date()),
        totalTests:  records.count,
        passedTests: passed,
        failedTests: records.count - passed,
        passRate:    String(format: "%.1f%%", Double(passed) / Double(records.count) * 100),
        results:     records.sorted { $0.testId < $1.testId }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(report) else { return }
    // Write to macOS Desktop — use real user home, not Simulator home
    let realHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
    let desktopPath = (realHome as NSString).appendingPathComponent("Desktop/agent_test_results.json")
    let url = URL(fileURLWithPath: desktopPath)
    try? data.write(to: url)
    print("📄 Report written to \(url.path)")
    print("📊 \(passed)/\(records.count) passed (\(report.passRate))")
}

// MARK: - Test Suite

@Suite("Agent Integration Tests", .serialized)
struct AgentIntegrationTests {

    init() { injectAPIKeyIfNeeded() }

    // ─── 案情分析 (8 cases) ──────────────────────────────────────────────────

    @Test func case01_租房强制驱逐() async throws {
        let r = try await runCase(
            testId: "case01", category: "案情分析",
            question: "我和房东签了一年租约，还有四个月到期，房东突然要求我两周内搬走并拒绝退押金，我该怎么办？",
            mode: .caseAnalysis,
            criteria: "应提及房东违约责任、租客拒绝搬离的权利、押金退还依据，并建议具体维权路径"
        )
        #expect(r.answerChars > 100, "answer too short")
        #expect(r.citationCount > 0, "no citations")
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case02_工资拖欠() async throws {
        let r = try await runCase(
            testId: "case02", category: "案情分析",
            question: "我在公司工作两年，已三个月未发工资，老板说公司资金困难，我该怎么维权？",
            mode: .caseAnalysis,
            criteria: "应提及劳动仲裁申请途径、拖欠工资的法律后果（加付赔偿金）、保留证据建议"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case03_人身伤害() async throws {
        let r = try await runCase(
            testId: "case03", category: "案情分析",
            question: "上周被邻居无故打伤住院，花了五千元医疗费，对方拒绝赔偿，我可以怎么做？",
            mode: .caseAnalysis,
            criteria: "应提及民事侵权赔偿（医疗费误工费等）、可同时报警追究刑事责任，说明诉讼途径"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case04_交通肇事逃逸() async throws {
        let r = try await runCase(
            testId: "case04", category: "案情分析",
            question: "骑电动车被轿车撞伤，对方肇事逃逸后警察找到了他但他拒绝赔偿，我该如何处理？",
            mode: .caseAnalysis,
            criteria: "应提及肇事逃逸加重责任、民事赔偿途径、保险赔付可能，指出可向法院提起民事诉讼"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case05_网购假货() async throws {
        let r = try await runCase(
            testId: "case05", category: "案情分析",
            question: "在电商平台买了运动鞋收货发现是假货，商家拒绝退款，平台客服也不处理，我该怎么办？",
            mode: .caseAnalysis,
            criteria: "应提及消费者权益保护、假一赔三的惩罚性赔偿、向市场监管/消协投诉或向平台申诉的途径"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case06_离婚财产纠纷() async throws {
        let r = try await runCase(
            testId: "case06", category: "案情分析",
            question: "我和丈夫准备离婚，婚前他全款买的房子，婚后我们共同还的车贷，这些财产怎么分？",
            mode: .caseAnalysis,
            criteria: "应区分婚前个人财产（房子）与婚后共同财产（车贷出资部分），说明分割原则"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case07_劳动合同违法解除() async throws {
        let r = try await runCase(
            testId: "case07", category: "案情分析",
            question: "公司以\"不符合岗位要求\"为由在我产假期间将我辞退，没有提前告知也没有任何赔偿，我该怎么办？",
            mode: .caseAnalysis,
            criteria: "应提及孕期/产假期间的特殊保护、违法解除劳动合同的赔偿标准（二倍经济补偿）、劳动仲裁途径"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func case08_网络诈骗() async throws {
        let r = try await runCase(
            testId: "case08", category: "案情分析",
            question: "我被人以投资理财为名骗走了八万元，对方现在拉黑了我，我该怎么追回损失？",
            mode: .caseAnalysis,
            criteria: "应建议立即报警（诈骗罪立案），说明刑事追赃与民事赔偿并行的路径，提示保存证据"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    // ─── 法律咨询 (8 cases) ──────────────────────────────────────────────────

    @Test func advisory01_劳动合同到期不续签() async throws {
        let r = try await runCase(
            testId: "advisory01", category: "法律咨询",
            question: "劳动合同到期公司不续签，员工能拿到经济补偿金吗？",
            mode: .legalAdvisory,
            criteria: "应明确：公司不续签一般需支付经济补偿金；但若员工拒绝续签且条件不低于原合同则无需补偿，并说明计算标准"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory02_试用期辞退() async throws {
        let r = try await runCase(
            testId: "advisory02", category: "法律咨询",
            question: "试用期被公司辞退，公司需要赔偿吗？",
            mode: .legalAdvisory,
            criteria: "应区分合法辞退（有正当理由）与违法辞退，说明违法辞退时的赔偿倍数"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory03_房东提前终止租约() async throws {
        let r = try await runCase(
            testId: "advisory03", category: "法律咨询",
            question: "房东能不能在租约未到期时单方面要求租客搬走？",
            mode: .legalAdvisory,
            criteria: "应说明一般情况下房东不能单方面提前终止，违约需承担赔偿责任；并列举法定可解除情形"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory04_离婚财产分割原则() async throws {
        let r = try await runCase(
            testId: "advisory04", category: "法律咨询",
            question: "夫妻离婚时共同财产怎么分割？有哪些一般原则？",
            mode: .legalAdvisory,
            criteria: "应提及平等分割原则、照顾子女/女方/无过错方原则，区分个人财产与共同财产"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory05_加班费计算() async throws {
        let r = try await runCase(
            testId: "advisory05", category: "法律咨询",
            question: "公司要求员工周末加班但不给加班费，说调休就行，这合法吗？",
            mode: .legalAdvisory,
            criteria: "应说明双休日加班优先安排补休，不能补休才支付200%工资；法定节假日加班必须支付300%工资，不可用调休替代"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory06_网贷高利息() async throws {
        let r = try await runCase(
            testId: "advisory06", category: "法律咨询",
            question: "我借了一笔网络贷款，年化利率高达36%，这合法吗？超出部分还需要还吗？",
            mode: .legalAdvisory,
            criteria: "应说明LPR4倍作为司法保护上限，超出部分法院不予支持，借款人可拒绝偿还超出部分"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory07_遗产继承顺序() async throws {
        let r = try await runCase(
            testId: "advisory07", category: "法律咨询",
            question: "父亲去世没有留下遗嘱，房子和存款由谁来继承？顺序是怎样的？",
            mode: .legalAdvisory,
            criteria: "应说明法定继承的第一顺序（配偶、子女、父母）、第二顺序，以及一般均等分配的原则"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func advisory08_个人信息泄露() async throws {
        let r = try await runCase(
            testId: "advisory08", category: "法律咨询",
            question: "我发现某平台将我的个人信息卖给了第三方广告商，我有什么法律权利？",
            mode: .legalAdvisory,
            criteria: "应提及个人信息保护法的权利（知情权、删除权、投诉权），以及可向监管机构投诉或提起民事诉讼"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    // ─── 法条检索 (6 cases) ──────────────────────────────────────────────────

    @Test func statute01_交通肇事罪构成要件() async throws {
        let r = try await runCase(
            testId: "statute01", category: "法条检索",
            question: "交通肇事罪的构成要件是什么？",
            mode: .conceptAndStatute,
            criteria: "必须列出四个构成要件（违反交规、发生重大事故、致人重伤/死亡/重大财损、主观过失），并引用刑法第133条",
            requiredLawFragment: "刑法"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0, "no citations")
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func statute02_善意取得() async throws {
        let r = try await runCase(
            testId: "statute02", category: "法条检索",
            question: "什么是善意取得制度？构成条件是什么？",
            mode: .conceptAndStatute,
            criteria: "应解释善意取得的含义（无权处分+受让人善意+合理对价+完成登记/交付），引用民法典相关条文",
            requiredLawFragment: "民法典"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func statute03_违约金规定() async throws {
        let r = try await runCase(
            testId: "statute03", category: "法条检索",
            question: "民法典关于违约金的规定有哪些？过高或过低时如何处理？",
            mode: .conceptAndStatute,
            criteria: "应提及违约金可约定、过高可申请降低（不超过损失的30%）、过低可申请提高，引用民法典第585条",
            requiredLawFragment: "民法典"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func statute04_故意伤害罪量刑() async throws {
        let r = try await runCase(
            testId: "statute04", category: "法条检索",
            question: "故意伤害罪的量刑标准是怎样的？",
            mode: .conceptAndStatute,
            criteria: "应区分轻伤（三年以下）、重伤（三至十年）、致死或以特别残忍手段（十年以上/无期/死刑），引用刑法第234条",
            requiredLawFragment: "刑法"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func statute05_诉讼时效() async throws {
        let r = try await runCase(
            testId: "statute05", category: "法条检索",
            question: "民事诉讼的诉讼时效是多少年？从什么时候开始计算？",
            mode: .conceptAndStatute,
            criteria: "应说明一般诉讼时效三年（民法典第188条）、从知道或应当知道权利受损之日起算，及最长二十年期限"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    @Test func statute06_合同无效情形() async throws {
        let r = try await runCase(
            testId: "statute06", category: "法条检索",
            question: "哪些情形下合同是无效的？",
            mode: .conceptAndStatute,
            criteria: "应列举民法典规定的合同无效情形（无民事行为能力人、欺诈/胁迫损害国家利益、违反法律强制性规定、违背公序良俗等）"
        )
        #expect(r.answerChars > 100)
        #expect(r.citationCount > 0)
        #expect(r.passed, "judge \(r.judgeScore)/10: \(r.judgeReason)")
        await writeReport()
    }

    // ─── 意图分类 (3 cases) ──────────────────────────────────────────────────

    @Test func intent01_问候语() async throws {
        injectAPIKeyIfNeeded()
        let (intent, _) = await LegalExpertService.shared.classifyIntentAndMode(
            message: "你好，请问你是谁？", history: [])
        let record = TestRecord(
            testId: "intent01", category: "意图分类",
            question: "你好，请问你是谁？",
            mode: "n/a", answer: "intent=\(intent.rawValue)",
            citations: [], judgeScore: intent == .offTopic ? 10 : 0,
            judgeReason: intent == .offTopic ? "正确分类为offTopic" : "错误分类为\(intent.rawValue)",
            passed: intent == .offTopic,
            answerChars: 0, citationCount: 0, durationSeconds: 0
        )
        await ResultStore.shared.append(record)
        #expect(intent == .offTopic, "expected offTopic, got \(intent.rawValue)")
        await writeReport()
    }

    @Test func intent02_口语化纠纷() async throws {
        injectAPIKeyIfNeeded()
        let (intent, _) = await LegalExpertService.shared.classifyIntentAndMode(
            message: "邻居每天晚上放很大的音乐，我都没法睡觉了", history: [])
        let record = TestRecord(
            testId: "intent02", category: "意图分类",
            question: "邻居每天晚上放很大的音乐，我都没法睡觉了",
            mode: "n/a", answer: "intent=\(intent.rawValue)",
            citations: [], judgeScore: intent == .legalQuery ? 10 : 0,
            judgeReason: intent == .legalQuery ? "正确分类为legalQuery" : "错误分类为\(intent.rawValue)",
            passed: intent == .legalQuery,
            answerChars: 0, citationCount: 0, durationSeconds: 0
        )
        await ResultStore.shared.append(record)
        #expect(intent == .legalQuery, "expected legalQuery, got \(intent.rawValue)")
        await writeReport()
    }

    @Test func intent03_构成要件为statute模式() async throws {
        injectAPIKeyIfNeeded()
        let (intent, mode) = await LegalExpertService.shared.classifyIntentAndMode(
            message: "交通肇事罪的构成要件是什么？", history: [])
        let correct = intent == .legalQuery && mode == .conceptAndStatute
        let record = TestRecord(
            testId: "intent03", category: "意图分类",
            question: "交通肇事罪的构成要件是什么？",
            mode: mode?.rawValue ?? "nil", answer: "intent=\(intent.rawValue) mode=\(mode?.rawValue ?? "nil")",
            citations: [], judgeScore: correct ? 10 : 0,
            judgeReason: correct ? "正确分类" : "intent=\(intent.rawValue) mode=\(mode?.rawValue ?? "nil")",
            passed: correct,
            answerChars: 0, citationCount: 0, durationSeconds: 0
        )
        await ResultStore.shared.append(record)
        #expect(intent == .legalQuery)
        #expect(mode == .conceptAndStatute, "expected statute, got \(String(describing: mode))")
        await writeReport()
    }
}
