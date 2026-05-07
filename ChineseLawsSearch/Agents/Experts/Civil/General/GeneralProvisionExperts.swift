// GeneralProvisionExperts.swift — 总则编专家（法律行为、代理、诉讼时效）

import Foundation

// 总则编章节 IDs
private let chLegalAct: [Int]    = [34600]  // 第六章 民事法律行为（含各节）
private let chAgency: [Int]      = [34633]  // 第七章 代理
private let chLiability: [Int]   = [34652]  // 第八章 民事责任
private let chLimitation: [Int]  = [34665]  // 第九章 诉讼时效

let civilJurisdictionExpert = SubExpert(
    name: "民事法律行为效力专家",
    domain: "民事法律行为效力、意思表示、欺诈胁迫、无效行为、代理权限",
    requiredInfo: [
        RequiredInfo(field: "行为类型",
                     question: "涉及什么民事行为（合同签署/代理/公司决议/捐赠/放弃权利）？",
                     regexHint: "合同|协议|代理|授权|委托|决议|公司|放弃|捐赠|赠与"),
        RequiredInfo(field: "效力瑕疵",
                     question: "是否存在欺诈/胁迫/重大误解/显失公平等情形？",
                     regexHint: "欺诈|欺骗|胁迫|强迫|误解|公平|乘人之危|显失公平|虚假|伪造"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chLegalAct + chAgency + chLiability,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["民事法律行为效力", "欺诈撤销权", "重大误解", "无效行为",
                       "无权代理", "表见代理", "撤销权除斥期间"],
    answerTemplate: """
    你是民事法律行为效力细分专家。基于以下法条，以第三方视角分析：
    1. 行为效力认定：有效/可撤销/效力待定/无效的认定标准
    2. 可撤销事由：欺诈/胁迫/重大误解/显失公平，撤销权行使期限（1年/5年）
    3. 代理：授权范围、无权代理的效力待定与追认、表见代理的构成
    4. 无效民事法律行为的后果：返还财产/折价补偿/损害赔偿
    引用总则编司法解释的具体条文，明确撤销权的行使方式和期限。
    """
)

let limitationExpert = SubExpert(
    name: "诉讼时效专家",
    domain: "诉讼时效、时效中止、时效中断、时效届满后果、特殊时效",
    requiredInfo: [
        RequiredInfo(field: "权利类型",
                     question: "主张的是什么权利（债权/物权/人格权/其他）？",
                     regexHint: "债权|借款|合同|侵权|损害赔偿|返还财产|物权|所有权"),
        RequiredInfo(field: "最后接触时间",
                     question: "最后一次对方承认债务或权利人主张权利是什么时候？",
                     regexHint: #"\d{4}年|\d+年前|上次|最后|承认|催收|通知|起诉"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chLimitation,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["诉讼时效", "一般时效3年", "时效中断", "时效中止", "不适用时效",
                       "时效届满后果", "最长权利保护期20年"],
    answerTemplate: """
    你是诉讼时效细分专家。基于以下法条，以第三方视角分析：
    1. 适用一般3年时效还是特殊时效，起算时间点认定
    2. 时效中断事由：提起诉讼/申请仲裁/义务人承认/权利人催收等
    3. 时效中止：最后6个月内的障碍（不可抗力/行为能力等）
    4. 不适用时效的情形（物权请求权/不动产登记等）
    5. 时效届满的后果：丧失胜诉权，但不丧失实体权利
    明确计算起点、中断时间，并给出当前是否仍在时效内的判断。
    """
)
