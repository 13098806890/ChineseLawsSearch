//
//  LaborExperts.swift
//  ChineseLawsSearch
//

import Foundation

// 劳动合同法章节 IDs
private let chLaborContractGeneral: [Int] = [22912, 22919, 22942, 22950]  // 总则、订立、履行变更、解除终止
private let chLaborContractSpecial: [Int] = [22966, 23000]  // 特别规定、法律责任
// 劳动法章节 IDs
private let chLaborLawWage: [Int]         = [23190]  // 第五章 工资
private let chLaborLawSocial: [Int]       = [23218]  // 第九章 社会保险和福利
// 劳动争议调解仲裁法
private let chLaborDispute: [Int]         = [22851, 22861, 22869]  // 总则、调解、仲裁

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
    chapterIdHints: chLaborContractGeneral + chLaborContractSpecial + [5230],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["经济补偿金", "赔偿金", "违法解除", "未签合同双倍工资", "竞业限制"],
    answerTemplate: """
    你是劳动合同法细分专家。基于以下法条，分析：
    1. 劳动关系认定：是否存在劳动关系（管理+劳动+报酬三要素），劳务关系vs劳动关系的区别
    2. 合法解除 vs 违法解除：用人单位解除的合法依据（第39/40/41条），不满足条件时为违法解除
    3. 经济补偿金（N）计算：每满1年补偿1个月工资（月均工资上限为当地社平工资3倍）
    4. 违法解除赔偿金（2N）：违法解除或终止劳动合同的，支付2倍经济补偿金
    5. 未签书面合同：入职满1个月未签，用人单位须支付双倍工资（最长11个月）
    6. 维权路径：向劳动仲裁委员会申请（仲裁前置，时效1年）→法院诉讼
    """
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
    chapterIdHints: chLaborLawWage + chLaborLawSocial + chLaborContractGeneral,
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["工资报酬", "加班工资", "最低工资标准", "社会保险费", "拖欠工资"],
    answerTemplate: """
    你是劳动工资福利细分专家。基于以下法条，分析：
    1. 工资性质与保护：工资须按时足额支付，无故拖欠须支付额外赔偿（拖欠金额50%-100%的赔偿金）
    2. 加班费计算标准：平日加班150%/休息日200%/法定假日300%
    3. 最低工资标准：不得低于当地最低工资标准，违法须补差额+赔偿金
    4. 社会保险：用人单位须依法缴纳五险（养老/医疗/失业/工伤/生育），未缴纳可申请补缴
    5. 维权路径：向劳动局投诉（拖欠工资可申请督促支付令）→劳动仲裁（1年时效）→诉讼
    """
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
    lawTitles: [
        "中华人民共和国劳动法",
        "工伤保险条例",
        "最高人民法院关于审理劳动争议案件适用法律问题的解释（一）",
    ],
    chapterIdHints: [75513, 75521, 75531, 5230],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释", "行政法规"],
    ftsKeywordsExtra: ["工伤认定", "工伤保险", "劳动能力鉴定", "一次性伤残补助金", "工亡补助金"],
    answerTemplate: """
    你是工伤职业病细分专家。基于以下法条，分析：
    1. 工伤认定三要素：工作时间+工作场所+工作原因（三者同时满足），上下班途中交通事故的特殊认定
    2. 申请流程：用人单位30日内申请（未申请则工伤职工1年内自行申请）→劳动能力鉴定→申请待遇
    3. 工伤保险待遇（援引工伤保险条例）：
       - 医疗费：全额报销（工伤保险基金支付）
       - 停工留薪：原工资福利不变，一般不超过12个月
       - 伤残补助金：1-10级，7-27个月月工资
       - 工亡补助金：上年度全国城镇居民人均可支配收入×20年
    4. 单位未参保时的责任：由用人单位按工伤保险条例标准自行支付全部费用
    5. 职业病认定：须经职业病诊断机构诊断，再申请工伤认定；特殊保护（禁止解除劳动合同）
    """
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
    lawTitles: [
        "中华人民共和国劳动争议调解仲裁法",
        "最高人民法院关于审理劳动争议案件适用法律问题的解释（一）",
        "最高人民法院关于审理劳动争议案件适用法律问题的解释（二）",
    ],
    chapterIdHints: chLaborDispute + [5230, 5285],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["劳动仲裁", "仲裁时效", "举证责任", "仲裁前置", "一裁终局"],
    answerTemplate: """
    你是劳动争议程序细分专家。基于以下法条，分析：
    1. 仲裁时效：一般1年，从当事人知道或应当知道权利被侵害之日起算；拖欠劳动报酬的时效从劳动关系终止之日起算
    2. 仲裁前置原则：劳动争议须先仲裁，不服仲裁裁决才能起诉；一裁终局的情形（追索劳动报酬/工伤医疗费≤12个月当地月平均工资×15倍）
    3. 举证责任分配：用人单位对劳动者工资标准、工作时间、解除原因等有举证义务（掌握证据的一方）
    4. 维权证据清单：劳动合同/工资条/打卡记录/社保缴纳记录/解除通知书/录音录像
    5. 仲裁→诉讼完整时间表：仲裁45日（特殊60日）→一审6个月→二审3个月
    """
)

let allLaborExperts: [SubExpert] = [
    laborContractExpert, wageExpert, workinjuryExpert, laborDisputeExpert,
]
