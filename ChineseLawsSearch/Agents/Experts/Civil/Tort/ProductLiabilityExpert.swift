// ProductLiabilityExpert.swift — 产品责任专家

import Foundation

private let chProduct: [Int] = [35776]  // 第四章 产品责任

let productLiabilityExpert = SubExpert(
    name: "产品责任专家",
    domain: "产品缺陷、产品质量、生产者责任、销售者责任、召回、食品安全",
    requiredInfo: [
        RequiredInfo(field: "产品类型",
                     question: "是什么产品（食品/药品/电器/玩具/机械设备/其他）？",
                     regexHint: "食品|食物|药品|电器|家电|玩具|机械|设备|汽车|建材"),
        RequiredInfo(field: "缺陷类型",
                     question: "产品问题是设计缺陷、制造缺陷还是警示说明不足？",
                     regexHint: "设计|制造|工艺|说明书|警示|标识|标签|批次"),
        RequiredInfo(field: "损害结果",
                     question: "产品缺陷造成了什么损害（人身伤害/财产损失）？",
                     regexHint: "受伤|烫伤|触电|中毒|爆炸|损坏|火灾|财产损失"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chProduct,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["产品缺陷", "生产者责任", "销售者先行赔偿", "惩罚性赔偿",
                       "食品安全惩罚性赔偿", "产品质量法"],
    answerTemplate: """
    你是产品责任细分专家。基于以下法条，以第三方视角分析：
    1. 产品缺陷的认定标准（不合理危险/违反标准）
    2. 责任主体：生产者（无过错责任）vs 销售者（过错责任/先行赔偿后追偿）
    3. 食品/药品的惩罚性赔偿：价款10倍或损失3倍，最低1000元
    4. 召回缺陷产品的义务及召回费用负担
    5. 举证：受害方需证明产品存在缺陷及缺陷与损害的因果关系
    注明产品质量法的交叉适用。
    """
)
