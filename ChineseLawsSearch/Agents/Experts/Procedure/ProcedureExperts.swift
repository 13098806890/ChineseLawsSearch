//
//  ProcedureExperts.swift
//  ChineseLawsSearch
//

import Foundation

let civilProcedureExpert = SubExpert(
    name: "民事诉讼专家",
    domain: "管辖、起诉、证据、审判、执行、保全",
    requiredInfo: [
        RequiredInfo(field: "纠纷类型",       question: "属于哪类民事纠纷（合同/侵权/婚姻/劳动/房屋）？",
                     regexHint: "合同|侵权|婚姻|劳动|房屋|租赁|借款|离婚|继承"),
        RequiredInfo(field: "是否有保全需求", question: "是否需要财产保全（防止被告转移财产）？",
                     regexHint: "保全|查封|冻结|扣押|转移财产|跑路"),
    ],
    lawTitles: ["中华人民共和国民事诉讼法"],
    chapterIdHints: [],
    ftsDomains: ["诉讼与非诉讼程序法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["管辖权", "起诉条件", "证据规则", "财产保全", "强制执行"],
    answerTemplate: "你是民事诉讼程序细分专家。基于以下法条，分析：\n1. 管辖法院的确定（级别管辖/地域管辖）\n2. 起诉条件（诉讼主体/诉讼请求/管辖）\n3. 证据收集和保全建议\n4. 财产保全的申请条件和流程\n给出具体的起诉准备清单。"
)

let criminalProcedureExpert = SubExpert(
    name: "刑事诉讼专家",
    domain: "报案、立案、逮捕、起诉、辩护、上诉",
    requiredInfo: [
        RequiredInfo(field: "案件阶段",   question: "目前案件处于哪个阶段（报案/立案/侦查/批捕/审判）？",
                     regexHint: "报案|立案|侦查|逮捕|起诉|审判|判决|上诉|执行|羁押"),
        RequiredInfo(field: "当事人身份", question: "案件中涉及哪方当事人（被害人/犯罪嫌疑人/被告人/家属）？",
                     regexHint: "受害者|被害人|嫌疑人|被告|家属|辩护|律师"),
    ],
    lawTitles: ["中华人民共和国刑事诉讼法"],
    chapterIdHints: [],
    ftsDomains: ["诉讼与非诉讼程序法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["取保候审", "不起诉", "辩护权", "非法证据排除", "上诉"],
    answerTemplate: "你是刑事诉讼程序细分专家。基于以下法条，分析：\n1. 当前阶段的程序权利（如申请取保候审/委托辩护人）\n2. 侦查/逮捕/审查起诉的法定时限\n3. 非法证据排除的申请条件\n4. 认罪认罚从宽制度的适用\n给出具体的程序建议和下一步行动。"
)

let adminProcedureExpert = SubExpert(
    name: "行政诉讼专家",
    domain: "行政诉讼、行政复议、具体行政行为、行政赔偿",
    requiredInfo: [
        RequiredInfo(field: "行政行为类型", question: "政府的具体行政行为是什么（处罚/许可/强制/征收）？",
                     regexHint: "行政处罚|吊销执照|罚款|行政许可|审批|行政强制|征收|拆迁"),
        RequiredInfo(field: "是否复议",     question: "是否已经申请了行政复议？",
                     regexHint: "行政复议|已复议|复议决定|维持|撤销|复议前置"),
    ],
    lawTitles: ["中华人民共和国行政诉讼法"],
    chapterIdHints: [],
    ftsDomains: ["诉讼与非诉讼程序法", "行政法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["行政诉讼受案范围", "行政复议前置", "举证责任倒置", "行政赔偿"],
    answerTemplate: "你是行政诉讼程序细分专家。基于以下法条，分析：\n1. 该行政行为是否属于行政诉讼受案范围\n2. 是否需要先行政复议（复议前置的情形）\n3. 起诉期限（6个月一般期限）\n4. 行政诉讼中的举证责任（行政机关举证）\n5. 行政赔偿的申请条件\n给出明确的路径建议。"
)

let allProcedureExperts: [SubExpert] = [
    civilProcedureExpert, criminalProcedureExpert, adminProcedureExpert,
]
