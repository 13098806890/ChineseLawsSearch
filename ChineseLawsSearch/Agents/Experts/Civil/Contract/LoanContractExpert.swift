// LoanContractExpert.swift — 借款合同专家（民间借贷、银行贷款、利息）

import Foundation

private let chLoan: [Int]       = [35186]  // 第十二章 借款合同
private let chGuarantee: [Int]  = [35201]  // 第十三章 保证合同

let loanContractExpert = SubExpert(
    name: "借款合同专家",
    domain: "民间借贷、银行贷款、利息约定、还款期限、逾期利息、借条、保证担保",
    requiredInfo: [
        RequiredInfo(field: "借款金额",
                     question: "借款金额是多少？",
                     regexHint: #"\d+\s*(?:万|千|百|元|块)"#),
        RequiredInfo(field: "是否有凭证",
                     question: "是否有借条/借款协议/转账记录？",
                     regexHint: "借条|借据|协议|合同|转账|微信|支付宝|银行流水|打款|记录"),
        RequiredInfo(field: "利息约定",
                     question: "是否约定了利息？约定利率是多少？",
                     regexHint: #"利息|利率|年利率|月利率|\d+%|无息|免息"#),
        RequiredInfo(field: "担保情况",
                     question: "是否有人做保证人？或是否有抵押物担保？",
                     regexHint: "保证人|担保人|抵押|质押|连带责任|保证|担保"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chLoan + chGuarantee,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["民间借贷", "利率上限", "逾期利息", "保证期间", "一般保证", "连带保证",
                       "超过诉讼时效", "催款通知"],
    answerTemplate: """
    你是借款合同细分专家。基于以下法条，以第三方视角分析：
    1. 借款合同的成立与生效（实践合同性质，实际出借为生效要件）
    2. 利率合法性判断：约定利率是否超过法定上限（LPR4倍），超出部分的处理
    3. 逾期还款的利息计算规则
    4. 保证责任：一般保证vs连带责任保证，保证期间（未约定时6个月）
    5. 诉讼时效：借款到期后3年，催收对时效的影响
    指出债权人起诉时需证明的事实和证据清单。
    """
)
