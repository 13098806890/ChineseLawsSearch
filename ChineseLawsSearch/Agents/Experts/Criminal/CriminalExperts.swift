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
    answerTemplate: """
    你是财产犯罪刑法细分专家。基于以下法条，以第三方视角分析：
    1. 罪名认定：行为的客观要素+主观故意（非法占有目的）是否满足
    2. 数额认定标准：数额较大/数额巨大/数额特别巨大的司法解释门槛（各罪不同）
    3. 法定刑幅度：量刑区间和加重情形（入户/持凶器/多次）
    4. 从轻情节：自首/立功/退赃/认罪认罚对量刑的影响
    5. 刑事附带民事：受害人可在刑事诉讼中提起附带民事赔偿请求
    明确引用刑法条文和相关司法解释的数额标准。
    """
)

let crimePersonExpert = SubExpert(
    name: "人身伤害专家",
    domain: "故意伤害、故意杀人、强奸、绑架、非法拘禁、交通肇事、危险驾驶",
    requiredInfo: [
        RequiredInfo(field: "犯罪行为", question: "具体行为是什么（故意伤害/故意杀人/强奸/绑架/交通肇事/醉驾）？",
                     regexHint: "故意伤害|故意杀人|强奸|绑架|拘禁|殴打|人身自由|交通肇事|肇事逃逸|醉驾|危险驾驶|超速|闯红灯"),
        RequiredInfo(field: "伤害程度", question: "受害人伤情如何（轻伤/重伤/死亡）？",
                     regexHint: "轻伤|重伤|死亡|轻微伤|残疾|鉴定"),
    ],
    lawTitles: ["中华人民共和国刑法"],
    chapterIdHints: [criminalChapterPerson],
    ftsDomains: ["刑法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["故意伤害罪", "故意杀人罪", "刑事附带民事", "伤残等级",
                       "交通肇事罪", "危险驾驶罪", "肇事逃逸", "醉酒驾车", "第一百三十三条"],
    answerTemplate: """
    你是人身伤害及交通肇事刑法细分专家。基于以下法条，以第三方视角分析：
    1. 罪名认定（故意伤害/故意杀人/交通肇事/危险驾驶）及构成要件
    2. 法定刑幅度（区分情节轻重/逃逸/致人死亡等加重情形）
    3. 刑事附带民事赔偿范围
    4. 自首/立功/认罪认罚的量刑影响
    5. 被害人过错对量刑的影响（被害人有过错可酌情从轻）
    引用刑法条文，说明刑事追诉标准。
    """
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
    answerTemplate: """
    你是经济犯罪刑法细分专家。基于以下法条，以第三方视角分析：
    1. 罪名认定：经济犯罪的客观行为+主观故意（如合同诈骗须有非法占有目的）
    2. 单位犯罪与自然人犯罪的区别处理（单位犯罪双罚制）
    3. 量刑标准：数额/情节的档次划分
    4. 退赔/退赃对量刑的影响（认罪认罚从宽）
    5. 刑民交叉：刑事追缴与民事赔偿的关系（刑事优先原则及例外）
    引用刑法条文和相关司法解释。
    """
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
    lawTitles: [
        "中华人民共和国刑法",
        "最高人民法院、最高人民检察院关于办理贪污贿赂刑事案件适用法律若干问题的解释",
    ],
    chapterIdHints: [criminalChapterCorruption, criminalChapterDerelict, 2274],
    ftsDomains: ["刑法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["贪污罪", "受贿罪", "挪用公款", "渎职罪", "量刑标准",
                       "贪污贿赂解释", "数额较大三万元", "数额巨大二十万元",
                       "数额特别巨大三百万元", "行贿人免除处罚", "斡旋受贿"],
    answerTemplate: """
    你是腐败职务犯罪刑法细分专家。基于以下法条，分析：
    1. 主体认定：国家工作人员的范围（公务员+以国家工作人员论）；国有企业中的认定
    2. 贪污/受贿数额量刑档次（援引贪污贿赂解释）：3万=数额较大（3年以下），20万=数额巨大（3-10年），300万=数额特别巨大（10年以上/无期）
    3. 退赃与认罪认罚：主动退缴赃款+认罪认罚可从轻，可在法定刑以下判处
    4. 行贿罪：行贿人在被追诉前主动交待的，可从轻/减轻；情节较轻的可免除处罚
    5. 监察调查衔接：监察机关调查阶段的留置措施，调查结束后移送检察院审查起诉
    引用刑法第383条（贪污罪）、第385条（受贿罪）及贪污贿赂解释的具体金额标准。
    """
)

let allCriminalExperts: [SubExpert] = [
    crimePropertyExpert, crimePersonExpert,
    crimeEconomyExpert, crimeCorruptionExpert,
]
