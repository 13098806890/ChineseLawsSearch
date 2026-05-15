// ServiceContractExpert.swift — 服务/委托/劳务合同专家（含物业、中介、合伙）

import Foundation

private let chMandate: [Int]    = [35459]  // 第二十三章 委托合同
private let chProperty: [Int]   = [35478]  // 第二十四章 物业服务合同
private let chBroker: [Int]     = [35504]  // 第二十六章 中介合同
private let chPartner: [Int]    = [35511]  // 第二十七章 合伙合同
private let chStorage: [Int]    = [35426, 35443]  // 保管、仓储

let serviceContractExpert = SubExpert(
    name: "服务委托合同专家",
    domain: "委托合同、劳务合同、物业服务、中介合同、居间合同、合伙合同、保管仓储",
    requiredInfo: [
        RequiredInfo(field: "服务类型",
                     question: "属于哪类服务关系（物业管理/中介居间/代理委托/保管/合伙经营）？",
                     regexHint: "物业|中介|居间|委托|代理|保管|仓储|合伙|劳务|服务"),
        RequiredInfo(field: "纠纷核心",
                     question: "核心纠纷是什么（服务费/损害赔偿/提前解除/利润分配）？",
                     regexHint: "服务费|佣金|中介费|报酬|损害|赔偿|解除|分配|退款"),
    ],
    lawTitles: [
        "中华人民共和国民法典",
        "最高人民法院关于适用《中华人民共和国民法典》合同编通则若干问题的解释",
    ],
    chapterIdHints: chMandate + chProperty + chBroker + chPartner + chStorage + [12788],
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["委托人任意解除权", "受托人报酬", "中介促成", "物业费", "合伙债务",
                       "居间合同跳单", "保管人责任", "委托人任意解除权赔偿",
                       "经纪合同跳单", "物业合同解除", "合伙人连带债务", "保管物灭失责任"],
    answerTemplate: """
    你是服务/委托合同细分专家。基于以下法条，以第三方视角分析：
    1. 合同类型辨析：委托（以委托人名义）vs 居间（促成第三方合同）vs 雇佣的区别
    2. 委托人任意解除权：无须理由可解除，但须赔偿受托人因此受到的损失（不含预期利益）
    3. 中介/居间：促成合同是获得报酬的前提；跳单（绕开中介签合同）的法律后果
    4. 物业服务合同：服务费支付义务，物业公司服务不达标时的减免规则
    5. 合伙债务：合伙人对合伙债务承担连带责任，出伙人对出伙前债务仍负连带责任
    6. 维权路径：书面催告→仲裁/诉讼，保留服务记录和付款凭证
    【本领域标杆案例索引】（人民法院公报，了解裁判规则，结合具体问题判断是否需要深入检索）
    • [裁判文书]《青岛华仁物业股份有限公司与恒丰银行股份有限公司青岛分行等物业合同纠纷案》：前期物业服务合同对个别业主具有约束力，排除约定无效。
    """
)
