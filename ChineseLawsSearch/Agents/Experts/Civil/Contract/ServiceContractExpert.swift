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
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chMandate + chProperty + chBroker + chPartner + chStorage,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["委托人任意解除权", "受托人报酬", "中介促成", "物业费", "合伙债务",
                       "居间合同跳单", "保管人责任"],
    answerTemplate: """
    你是服务/委托合同细分专家。基于以下法条，以第三方视角分析：
    1. 合同类型认定（委托/居间/雇佣/合伙的区别）及相应规则
    2. 报酬/服务费的支付条件（是否满足约定条件）
    3. 委托人任意解除权与损害赔偿的平衡
    4. 中介合同：跳单行为的法律后果，佣金请求权的条件
    5. 物业合同：物业费缴纳义务，物业公司的服务义务标准
    引用具体条文，明确双方权利义务。
    """
)
