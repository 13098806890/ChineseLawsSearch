// GeneralTortExpert.swift — 侵权责任通则专家（一般侵权、损害赔偿计算、责任主体）

import Foundation

private let chTortGeneral: [Int]  = [35735, 35751]  // 第一章一般规定、第二章损害赔偿
private let chTortSubject: [Int]  = [35761]          // 第三章 责任主体的特殊规定

let generalTortExpert = SubExpert(
    name: "侵权通则专家",
    domain: "过错责任、无过错责任、共同侵权、雇主责任、网络侵权、损害赔偿计算",
    requiredInfo: [
        RequiredInfo(field: "侵权主体",
                     question: "侵权行为由谁实施（个人/公司/员工职务行为/网络用户）？",
                     regexHint: "员工|雇员|职工|公司|单位|网络|平台|用户|个人|法人"),
        RequiredInfo(field: "损害类型",
                     question: "造成了什么损害（人身伤亡/财产损失/精神损害）？",
                     regexHint: "受伤|死亡|残疾|财产|损坏|精神|抑郁|名誉"),
        RequiredInfo(field: "因果关系",
                     question: "损害是否因对方行为直接造成？是否存在多因一果的情形？",
                     regexHint: "导致|造成|引起|原因|直接|间接|共同|多人"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chTortGeneral + chTortSubject,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["过错责任", "无过错责任", "共同侵权", "连带责任", "雇主替代责任",
                       "人身损害赔偿", "死亡赔偿金", "精神损害赔偿", "误工费", "护理费"],
    answerTemplate: """
    你是侵权责任通则细分专家。基于以下法条，以第三方视角分析：
    1. 归责原则（过错/推定过错/无过错）及举证责任分配
    2. 侵权构成要件：加害行为、损害结果、因果关系、主观过错
    3. 责任主体认定：用人单位替代责任、多数人侵权的连带/按份责任
    4. 损害赔偿项目清单：
       - 人身损害：医疗费/误工费/护理费/残疾赔偿金/死亡赔偿金
       - 精神损害赔偿的适用条件和计算参考
    5. 过失相抵规则（受害方自身过错的减责情形）
    引用人身损害赔偿司法解释的具体条文和赔偿标准说明。
    """
)
