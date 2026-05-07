//
//  LaborExperts.swift
//  ChineseLawsSearch
//

import Foundation

let laborContractExpert = SubExpert(
    name: "劳动合同专家",
    domain: "劳动合同签订、解除、终止、经济补偿",
    requiredInfo: [
        RequiredInfo(field: "劳动关系类型", question: "劳动关系类型（正式合同/试用期/劳务派遣/外包）？",
                     regexHint: "正式员工|试用期|劳务派遣|外包|兼职|合同工|临时工"),
        RequiredInfo(field: "工作年限",     question: "在该单位工作了多久？",
                     regexHint: #"\d+\s*(?:年|个月|月)"#),
        RequiredInfo(field: "解除方式",     question: "劳动关系如何解除的（被辞退/协商解除/自行辞职）？",
                     regexHint: "辞退|开除|解雇|协商离职|自行辞职|主动离职|合同到期|不续签"),
        RequiredInfo(field: "是否签合同",   question: "是否签订了书面劳动合同？",
                     regexHint: "有合同|没有合同|未签合同|口头约定|已签"),
    ],
    lawTitles: ["中华人民共和国劳动合同法", "中华人民共和国劳动法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["经济补偿金", "赔偿金", "违法解除", "未签合同双倍工资", "竞业限制"],
    answerTemplate: "你是劳动合同法细分专家。基于以下法条，分析：\n1. 解除劳动合同是否合法\n2. 经济补偿金（N）或赔偿金（2N）的计算方式\n3. 未签书面劳动合同的双倍工资主张\n4. 维权路径（劳动仲裁→法院）及时效（1年）\n明确给出补偿金额的计算公式。"
)

let wageExpert = SubExpert(
    name: "工资福利专家",
    domain: "工资拖欠、加班费、最低工资、社会保险",
    requiredInfo: [
        RequiredInfo(field: "拖欠类型", question: "拖欠的是基本工资、加班费还是提成奖金？",
                     regexHint: "基本工资|加班费|提成|奖金|绩效|社保|五险一金|拖欠"),
        RequiredInfo(field: "拖欠金额", question: "拖欠金额是多少？拖欠了多久？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千)|\d+\s*个月"#),
    ],
    lawTitles: ["中华人民共和国劳动法", "中华人民共和国劳动合同法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["工资报酬", "加班工资", "最低工资标准", "社会保险费", "拖欠工资"],
    answerTemplate: "你是劳动工资福利细分专家。基于以下法条，分析：\n1. 工资拖欠的法律认定及追偿权利\n2. 加班费计算标准（150%/200%/300%）\n3. 社会保险缴纳义务及违法后果\n4. 劳动仲裁追偿的时效和流程\n给出具体的计算示例（如可能）。"
)

let workinjuryExpert = SubExpert(
    name: "工伤职业病专家",
    domain: "工伤认定、工伤赔偿、职业病、工亡",
    requiredInfo: [
        RequiredInfo(field: "事故情形", question: "受伤是在什么情况下发生的（工作时间/上下班途中/职业病）？",
                     regexHint: "工作时间|上班途中|下班途中|出差|职业病|工作原因|因公"),
        RequiredInfo(field: "伤情程度", question: "伤情或伤残程度（住院/伤残等级/死亡）？",
                     regexHint: "住院|伤残|等级|死亡|职业病|工亡"),
        RequiredInfo(field: "参保情况", question: "单位是否为其缴纳工伤保险？",
                     regexHint: "工伤保险|参保|未参保|未缴|社保"),
    ],
    lawTitles: ["中华人民共和国劳动法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["工伤认定", "工伤保险", "劳动能力鉴定", "一次性伤残补助金", "工亡补助金"],
    answerTemplate: "你是工伤职业病细分专家。基于以下法条，分析：\n1. 是否符合工伤认定条件（工作时间/工作场所/工作原因三要素）\n2. 工伤申报流程和时限（30日/1年）\n3. 工伤保险待遇（医疗费/伤残补助金/护理费/停工留薪）\n4. 单位未参保时的赔偿责任\n明确列出各项赔偿项目。"
)

let laborDisputeExpert = SubExpert(
    name: "劳动争议专家",
    domain: "劳动仲裁、诉讼时效、证据、仲裁前置",
    requiredInfo: [
        RequiredInfo(field: "争议事项", question: "劳动争议的核心事项是什么（工资/解除/工伤/社保）？",
                     regexHint: "工资|解除|工伤|社保|竞业限制|服务期|培训费"),
        RequiredInfo(field: "时间节点", question: "劳动关系结束多久了？是否超过1年仲裁时效？",
                     regexHint: #"\d+\s*(?:年|个月)|最近|刚刚|超过一年|时效"#),
    ],
    lawTitles: ["中华人民共和国劳动争议调解仲裁法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["劳动仲裁", "仲裁时效", "举证责任", "仲裁前置", "一裁终局"],
    answerTemplate: "你是劳动争议程序细分专家。基于以下法条，分析：\n1. 劳动仲裁时效（1年）及起算点\n2. 仲裁前置原则与例外（一裁终局情形）\n3. 举证责任分配（用人单位举证倒置规则）\n4. 仲裁→一审→二审的完整路径和时限\n给出明确的维权时间表。"
)

let allLaborExperts: [SubExpert] = [
    laborContractExpert, wageExpert, workinjuryExpert, laborDisputeExpert,
]
