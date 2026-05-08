// ContractGeneralExpert.swift — 合同编通则专家（成立/效力/违约/保全/解除）

import Foundation

// 民法典合同编通则章节 IDs
private let chGeneral: [Int] = [34971, 34978, 35012, 35020, 35047, 35056, 35071, 35092]
// 九民纪要：一（民法总则与合同法衔接）、三（合同纠纷）
private let chJiuMinContract: [Int] = [1371, 1402]

let contractGeneralExpert = SubExpert(
    name: "合同通则专家",
    domain: "合同成立、合同效力、合同履行、合同变更转让、合同解除、违约责任",
    requiredInfo: [
        RequiredInfo(field: "合同形式",
                     question: "合同是口头约定还是书面签署？是否有微信/邮件等记录？",
                     regexHint: "口头|书面|微信|邮件|合同书|电子合同|协议|盖章|签字"),
        RequiredInfo(field: "违约事实",
                     question: "对方具体做了什么或没做什么（拒绝交付/逾期/质量不符/拒绝付款）？",
                     regexHint: "拒绝|逾期|超期|未付|不付|不履行|拖延|质量|瑕疵"),
        RequiredInfo(field: "损失金额",
                     question: "因此造成的直接损失大约多少（货款/定金/利润损失）？",
                     regexHint: #"\d+\s*(?:万|千|百|元|块)"#),
    ],
    lawTitles: ["中华人民共和国民法典", "全国法院民商事审判工作会议纪要"],
    chapterIdHints: chGeneral + chJiuMinContract,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["合同成立", "合同效力", "违约责任", "合同解除", "损害赔偿", "定金", "预期违约",
                       "格式条款", "显失公平", "情势变更", "欺诈撤销", "违约金调整"],
    answerTemplate: """
    你是合同编通则细分专家。基于以下法条，以第三方视角分析：
    1. 合同效力（成立要件/效力瑕疵/撤销权）；注意九民纪要第1-4条关于民法总则与合同法的时间衔接规则
    2. 履行状态（是否构成违约，违约类型：拒绝履行/迟延履行/不完全履行）
    3. 违约责任（继续履行/损害赔偿/定金罚则，优先判断哪方违约）；违约金过高/过低的调整标准（九民纪要第50条）
    4. 合同解除条件（约定解除/法定解除）及解除后的法律后果
    5. 格式条款效力（九民纪要第44-45条）
    6. 诉讼时效（一般3年）
    引用具体条文编号，明确双方权利义务边界。
    """
)
