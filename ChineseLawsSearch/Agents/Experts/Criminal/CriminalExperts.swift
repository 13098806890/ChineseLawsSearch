//
//  CriminalExperts.swift
//  ChineseLawsSearch
//

import Foundation

private let criminalChapterProperty   = 22116
private let criminalChapterPerson     = 22084
private let criminalChapterEconomy    = 22083
private let criminalChapterCorruption = 22247
private let criminalChapterDerelict   = 22263

let crimePropertyExpert = SubExpert(
    name: "财产犯罪专家",
    domain: "盗窃、诈骗、抢劫、敲诈勒索、侵占",
    requiredInfo: [
        RequiredInfo(field: "犯罪行为", question: "具体行为是什么（盗窃/诈骗/抢劫/敲诈/侵占）？",
                     regexHint: "盗窃|诈骗|抢劫|抢夺|敲诈勒索|侵占|挪用|骗取"),
        RequiredInfo(field: "涉案金额", question: "涉及金额是多少？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千|亿)"#),
    ],
    lawTitles: ["中华人民共和国刑法"],
    chapterIdHints: [criminalChapterProperty],
    ftsDomains: ["刑法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["盗窃罪", "诈骗罪", "抢劫罪", "数额较大", "数额巨大"],
    answerTemplate: "你是财产犯罪刑法细分专家。基于以下法条，分析：\n1. 行为构成何种犯罪（罪名及构成要件）\n2. 法定刑幅度（量刑区间）\n3. 数额认定标准（较大/巨大/特别巨大）\n4. 从重/从轻/减轻情节\n明确引用刑法条文和相关司法解释。"
)

let crimePersonExpert = SubExpert(
    name: "人身伤害专家",
    domain: "故意伤害、故意杀人、强奸、绑架、非法拘禁",
    requiredInfo: [
        RequiredInfo(field: "犯罪行为", question: "具体行为是什么（故意伤害/故意杀人/强奸/绑架）？",
                     regexHint: "故意伤害|故意杀人|强奸|绑架|拘禁|殴打|人身自由"),
        RequiredInfo(field: "伤害程度", question: "受害人伤情如何（轻伤/重伤/死亡）？",
                     regexHint: "轻伤|重伤|死亡|轻微伤|残疾|鉴定"),
    ],
    lawTitles: ["中华人民共和国刑法"],
    chapterIdHints: [criminalChapterPerson],
    ftsDomains: ["刑法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["故意伤害罪", "故意杀人罪", "刑事附带民事", "伤残等级"],
    answerTemplate: "你是人身伤害刑法细分专家。基于以下法条，分析：\n1. 罪名认定（故意伤害/故意杀人）\n2. 法定刑（轻伤/重伤/死亡对应量刑）\n3. 刑事附带民事赔偿范围\n4. 自首/立功的量刑影响\n引用刑法条文，说明刑事追诉标准。"
)

let crimeEconomyExpert = SubExpert(
    name: "经济犯罪专家",
    domain: "合同诈骗、生产销售伪劣商品、走私、破坏市场秩序",
    requiredInfo: [
        RequiredInfo(field: "犯罪类型", question: "属于哪类经济犯罪（合同诈骗/销售假冒伪劣/走私/非法经营）？",
                     regexHint: "合同诈骗|假冒伪劣|走私|非法经营|洗钱|虚假广告"),
        RequiredInfo(field: "涉案金额", question: "涉案金额是多少？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千|亿)"#),
    ],
    lawTitles: ["中华人民共和国刑法"],
    chapterIdHints: [criminalChapterEconomy],
    ftsDomains: ["刑法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["合同诈骗", "生产销售伪劣", "非法经营", "单位犯罪"],
    answerTemplate: "你是经济犯罪刑法细分专家。基于以下法条，分析：\n1. 经济犯罪的罪名及构成要件\n2. 单位犯罪与自然人犯罪的区别处理\n3. 量刑标准（数额/情节）\n4. 退赔对量刑的影响\n引用刑法条文和相关司法解释。"
)

let crimeCorruptionExpert = SubExpert(
    name: "腐败职务犯罪专家",
    domain: "贪污贿赂、渎职、滥用职权、玩忽职守",
    requiredInfo: [
        RequiredInfo(field: "犯罪类型", question: "是哪类职务犯罪（贪污/受贿/行贿/挪用公款/渎职）？",
                     regexHint: "贪污|受贿|行贿|挪用公款|滥用职权|玩忽职守|失职"),
        RequiredInfo(field: "主体身份", question: "行为人是什么身份（国家工作人员/公务员/国有企业）？",
                     regexHint: "国家工作人员|公务员|国有企业|事业单位|村委会"),
        RequiredInfo(field: "涉案金额", question: "涉案金额（贪污/受贿/挪用金额）？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千|亿)"#),
    ],
    lawTitles: ["中华人民共和国刑法"],
    chapterIdHints: [criminalChapterCorruption, criminalChapterDerelict],
    ftsDomains: ["刑法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["贪污罪", "受贿罪", "挪用公款", "渎职罪", "量刑标准"],
    answerTemplate: "你是腐败职务犯罪刑法细分专家。基于以下法条，分析：\n1. 罪名认定及主体要件\n2. 量刑档次（3万/20万/300万等数额标准）\n3. 主动退赃和认罪认罚的量刑影响\n4. 监察调查与刑事诉讼的衔接\n明确引用刑法条文及最高院司法解释。"
)

let allCriminalExperts: [SubExpert] = [
    crimePropertyExpert, crimePersonExpert,
    crimeEconomyExpert, crimeCorruptionExpert,
]
