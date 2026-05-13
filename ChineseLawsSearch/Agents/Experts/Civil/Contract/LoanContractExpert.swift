// LoanContractExpert.swift — 借款合同专家（民间借贷、银行贷款、利息）

import Foundation

private let chLoan: [Int]       = [35186]  // 第十二章 借款合同
private let chGuarantee: [Int]  = [35201]  // 第十三章 保证合同
// 民法典担保制度司法解释
private let chGuaranteeInterp: [Int] = [13043]
// 九民纪要：四（担保纠纷）
private let chJiuMinGuarantee: [Int] = [1427]

let loanContractExpert = SubExpert(
    name: "借款合同专家",
    domain: "民间借贷、银行贷款、利率上限、逾期利息、借条效力、保证担保、抵押担保、诉讼时效",
    requiredInfo: [
        RequiredInfo(field: "借款金额",
                     question: "借款金额是多少？是否有银行转账记录或收据？",
                     regexHint: #"\d+\s*(?:万|千|百|元|块)"#),
        RequiredInfo(field: "是否有凭证",
                     question: "是否有借条/借款协议/转账记录？",
                     regexHint: "借条|借据|协议|合同|转账|微信|支付宝|银行流水|打款|记录|IOU"),
        RequiredInfo(field: "利息约定",
                     question: "是否约定了利息？约定利率是多少（如年利率/月利率）？",
                     regexHint: #"利息|利率|年利率|月利率|\d+%|无息|免息|高利贷"#),
        RequiredInfo(field: "担保情况",
                     question: "是否有人做保证人？或是否有房产/车辆等抵押物担保？",
                     regexHint: "保证人|担保人|抵押|质押|连带责任|保证|担保|房产抵押"),
    ],
    lawTitles: [
        "中华人民共和国民法典",
        "最高人民法院关于适用《中华人民共和国民法典》有关担保制度的解释",
        "全国法院民商事审判工作会议纪要",
    ],
    chapterIdHints: chLoan + chGuarantee + chGuaranteeInterp + chJiuMinGuarantee,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["民间借贷", "利率上限", "LPR四倍", "逾期利息", "砍头息",
                       "保证期间", "一般保证", "连带保证", "超过诉讼时效",
                       "催款通知", "越权担保", "善意相对人", "担保合同无效",
                       "抵押权", "质押权", "执行担保", "以物抵债"],
    answerTemplate: """
    你是借款合同细分专家。基于以下法条，以第三方视角分析：
    1. 借款合同效力：实践合同（实际出借为生效要件），借条/转账记录的证明力
    2. 利率合法性：
       - 约定利率是否超过法定上限（LPR四倍，约年利率15%左右）
       - 超出部分不受法律保护，已付可主张抵扣本金
       - "砍头息"（预先扣除利息）的认定与处理
    3. 逾期还款：逾期利率规则，催告后的利息计算起点
    4. 担保效力分析（参考九民纪要第17-20条，担保制度解释）：
       - 公司越权担保：是否审查股东会/董事会决议，善意相对人的保护
       - 一般保证 vs 连带责任保证：先诉抗辩权的有无
       - 保证期间：约定优先，未约定为6个月，期间届满担保人免责
    5. 诉讼时效：借款到期后3年；催收对时效的中断效力（须有证据）
    6. 维权路径：证据清单（借条+转账记录+催告记录）→ 法院起诉或申请支付令
    引用担保制度解释及九民纪要具体条文，给出债权人诉讼要点。
    """
)
