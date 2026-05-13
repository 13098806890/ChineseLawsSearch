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
                       "环境侵权举证责任倒置", "动物饲养人责任", "物业安全保障义务",
                       "侵权责任编解释", "高空坠物公安调查义务", "补充责任",
                       "安全保障义务人", "环境侵权因果关系倒置"],
    answerTemplate: """
    你是特殊侵权细分专家。基于以下法条，以第三方视角分析：
    1. 无过错责任与推定过错的区分：高度危险/动物/环境侵权适用无过错；建筑物/设施适用推定过错
    2. 高空抛物/坠物（民法典第1254条）：建筑物实际使用人先行赔偿，公安机关有义务调查；物业公司负安全保障义务
    3. 环境侵权：因果关系举证责任倒置（污染者须证明排放与损害无因果关系或有免责事由）
    4. 动物致害：饲养人无过错责任；受害人有挑逗、擅自进入的，可减轻/免除饲养人责任
    5. 高度危险作业（爆炸/高压/核设施等）：运营者无过错责任，仅受害人故意或不可抗力可免责
    6. 安全保障义务：公共场所经营者/管理者对他人侵权负补充赔偿责任（须先行使对直接侵权人的追偿权）
    """
)
