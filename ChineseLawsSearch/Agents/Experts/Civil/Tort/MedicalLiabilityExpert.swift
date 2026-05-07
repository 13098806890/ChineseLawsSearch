// MedicalLiabilityExpert.swift — 医疗损害责任专家

import Foundation

private let chMedical: [Int] = [35794]  // 第六章 医疗损害责任

let medicalLiabilityExpert = SubExpert(
    name: "医疗损害责任专家",
    domain: "医疗事故、医疗过失、知情同意、病历资料、损害鉴定、医院责任",
    requiredInfo: [
        RequiredInfo(field: "损害后果",
                     question: "医疗行为导致了什么后果（死亡/残疾/病情加重/感染/误诊）？",
                     regexHint: "死亡|残疾|后遗症|误诊|漏诊|感染|过度治疗|手术失误|病情加重"),
        RequiredInfo(field: "知情同意",
                     question: "医院是否告知了手术/治疗风险？患者/家属是否签署了知情同意书？",
                     regexHint: "知情同意|告知|签字|手术同意书|未告知|隐瞒"),
        RequiredInfo(field: "病历情况",
                     question: "是否取得了完整病历资料？病历是否有篡改迹象？",
                     regexHint: "病历|病案|医疗记录|篡改|涂改|封存|复印"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chMedical,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["医疗过错", "医疗损害鉴定", "病历封存", "知情同意", "过度医疗",
                       "医疗机构免责", "医疗损害责任纠纷"],
    answerTemplate: """
    你是医疗损害责任细分专家。基于以下法条，以第三方视角分析：
    1. 归责原则：医疗损害适用过错责任，三类推定过错情形（隐匿/篡改病历/违规使用药品等）
    2. 诊疗行为与损害结果之间的因果关系认定（需医疗损害鉴定）
    3. 知情同意义务：未尽告知义务的独立赔偿责任
    4. 维权步骤：申请病历封存 → 医疗损害鉴定（司法鉴定或医学会鉴定）→ 诉讼
    5. 举证责任：患者举证基本事实，医疗机构举证无过错
    引用医疗损害责任司法解释的具体条文。
    """
)
