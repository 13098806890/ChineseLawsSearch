// OtherTortExpert.swift — 其他特殊侵权（环境污染、高度危险、动物、建筑物）

import Foundation

private let chEnv: [Int]      = [35806]  // 第七章 环境污染和生态破坏
private let chHighRisk: [Int] = [35814]  // 第八章 高度危险责任
private let chAnimal: [Int]   = [35824]  // 第九章 饲养动物损害责任
private let chBuilding: [Int] = [35832]  // 第十章 建筑物和物件损害责任

let otherTortExpert = SubExpert(
    name: "特殊侵权专家",
    domain: "环境污染、高度危险作业、动物致人损害、建筑物倒塌坠物、公共场所安全",
    requiredInfo: [
        RequiredInfo(field: "侵权类型",
                     question: "属于哪类特殊侵权（环境污染/爆炸高压/动物咬伤/高空坠物/建筑倒塌）？",
                     regexHint: "环境污染|污水|废气|爆炸|高压电|核辐射|动物|狗咬|高空坠物|建筑物|坠落"),
        RequiredInfo(field: "损害情况",
                     question: "造成了什么损害（人身伤亡/财产损失/生态破坏）？",
                     regexHint: "受伤|死亡|财产|损坏|污染|生态|庄稼|鱼塘"),
        RequiredInfo(field: "责任人信息",
                     question: "侵权方是谁（个人/企业/物业/建筑施工方/动物所有人）？",
                     regexHint: "物业|业主|施工|建设方|工厂|企业|动物主人|饲养人"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chEnv + chHighRisk + chAnimal + chBuilding,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["无过错责任", "高度危险", "高空抛物", "建筑物坠落",
                       "环境侵权举证责任倒置", "动物饲养人责任", "物业安全保障义务"],
    answerTemplate: """
    你是特殊侵权细分专家。基于以下法条，以第三方视角分析：
    1. 适用无过错责任还是推定过错责任（此类侵权通常为无过错，免责事由严格）
    2. 免责事由：受害人故意/不可抗力/第三人原因各自的免责效果
    3. 高空抛物/坠物：建筑物所有人/管理人/物业的补偿责任，公安机关的调查义务
    4. 动物致害：饲养人责任，受害人挑逗/擅入的减免责任
    5. 环境侵权：因果关系举证责任倒置（污染者自证无因果关系）
    引用具体条文，指出维权程序要点。
    """
)
