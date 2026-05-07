// ConstructionContractExpert.swift — 建设工程合同专家

import Foundation

private let chConstruction: [Int] = [35315]  // 第十八章 建设工程合同
private let chWork: [Int]         = [35296]  // 第十七章 承揽合同

let constructionContractExpert = SubExpert(
    name: "建设工程合同专家",
    domain: "施工合同、工程款结算、工程质量、竣工验收、优先受偿权、违法分包转包",
    requiredInfo: [
        RequiredInfo(field: "工程类型",
                     question: "工程项目类型（住宅建设/装修装饰/市政/路桥/其他）？",
                     regexHint: "建设|施工|装修|装饰|市政|道路|桥梁|管道|安装|工程"),
        RequiredInfo(field: "工程款状态",
                     question: "工程款是否结清？欠款金额？是否已竣工验收？",
                     regexHint: "工程款|结算|欠款|拖欠|竣工|验收|决算|审计|未付"),
        RequiredInfo(field: "施工资质",
                     question: "施工方是否有相应资质？是否存在违法分包或转包？",
                     regexHint: "资质|无资质|分包|转包|挂靠|违法|许可证"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chConstruction + chWork,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["工程款优先受偿权", "建设工程施工合同", "竣工验收", "工程结算",
                       "违法分包", "无资质施工", "质量保修", "工期延误"],
    answerTemplate: """
    你是建设工程合同细分专家。基于以下法条，以第三方视角分析：
    1. 合同效力：无资质/违法转包对合同效力的影响（效力性强制规范）
    2. 工程款结算：以审计结论为准/双方认可结算书的效力
    3. 工程款优先受偿权：建设工程价款在抵押权之前的优先顺位，行使期限（18个月）
    4. 工程质量责任：缺陷保修期、施工方的质量保证义务
    5. 发包方违约（逾期付款/擅自变更）的工期顺延和索赔
    引用建设工程施工合同司法解释的具体条文。
    """
)
