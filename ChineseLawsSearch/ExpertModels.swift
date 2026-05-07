//
//  ExpertModels.swift
//  ChineseLawsSearch
//

import Foundation

// MARK: - Data types

struct RequiredInfo {
    let field: String
    let question: String
    let regexHint: String   // used to auto-extract from the question text
}

struct SubExpert {
    let name: String
    let domain: String
    let requiredInfo: [RequiredInfo]
    let lawTitles: [String]
    let chapterIdHints: [Int]
    let ftsDomains: [String]
    let ftsCategories: [String]
    let ftsKeywordsExtra: [String]
    let answerTemplate: String
}

struct ExpertGroup {
    let name: String
    let description: String
    let subExperts: [SubExpert]
    let routingKeywords: [String]
}

// MARK: - Chapter ID constants (刑法)

private let criminalChapterProperty   = 22116
private let criminalChapterPerson     = 22084
private let criminalChapterEconomy    = 22083
private let criminalChapterCorruption = 22247
private let criminalChapterDerelict   = 22263

// 民法典合同编 hint
private let civilContractGeneral = [34971, 34978, 35012, 35020, 35047, 35056, 35071, 35092]
private let civilSale  = [35111]
private let civilLease = [35226]
private let civilLoan  = [35186]

// MARK: - 民法专家组

let contractExpert = SubExpert(
    name: "合同法专家",
    domain: "合同纠纷、违约责任、合同解除、合同效力",
    requiredInfo: [
        RequiredInfo(field: "合同类型",     question: "合同是哪种类型（买卖/租赁/服务/借款/建设工程/其他）？",
                     regexHint: "买卖|租赁|服务|借款|贷款|雇佣|劳务|承揽|运输|建设工程"),
        RequiredInfo(field: "违约方",       question: "是哪一方违约（对方/甲方/乙方）？",
                     regexHint: "对方|甲方|乙方|买方|卖方|商家|平台|房东|租客"),
        RequiredInfo(field: "具体违约行为", question: "对方具体做了什么（不交货/不付款/质量问题/单方解约）？",
                     regexHint: "不交货|不付款|拖欠|逾期|质量|不合格|单方|解除|违约"),
        RequiredInfo(field: "合同金额",     question: "合同标的金额大概是多少？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千|亿)"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: civilContractGeneral + civilSale + civilLease + civilLoan,
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["违约责任", "合同解除", "继续履行", "损害赔偿"],
    answerTemplate: "你是合同法细分专家。基于以下法条，分析：\n1. 该合同的法律效力\n2. 违约方应承担哪些违约责任（继续履行/损害赔偿/定金罚则）\n3. 守约方可采取的维权路径\n引用具体条文编号，语言通俗。"
)

let propertyExpert = SubExpert(
    name: "物权专家",
    domain: "不动产所有权、用益物权、担保物权、物权登记",
    requiredInfo: [
        RequiredInfo(field: "物权类型", question: "涉及的是哪种物权（所有权/使用权/抵押/宅基地）？",
                     regexHint: "所有权|使用权|抵押|质押|留置|地役权|宅基地|建设用地|居住权"),
        RequiredInfo(field: "标的物",   question: "争议的财产是什么（房产/土地/车辆/动产）？",
                     regexHint: "房产|房屋|土地|宅基地|车辆|动产|股权"),
        RequiredInfo(field: "是否登记", question: "该财产是否已办理权属登记/过户？",
                     regexHint: "登记|过户|产权证|不动产证|已登记|未登记"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["物权登记", "善意取得", "不动产", "抵押权实现"],
    answerTemplate: "你是物权法细分专家。基于以下法条，分析：\n1. 当事人的物权归属及依据\n2. 物权是否受到侵害及侵害方式\n3. 物权人可以行使哪些请求权（返还/排除妨害/损害赔偿）\n引用具体条文，指明登记要求。"
)

let tortExpert = SubExpert(
    name: "侵权责任专家",
    domain: "侵权损害赔偿、过错责任、无过错责任、共同侵权",
    requiredInfo: [
        RequiredInfo(field: "侵权类型",   question: "属于哪种侵权（人身伤害/财产损害/名誉权/产品责任/交通事故）？",
                     regexHint: "人身伤害|受伤|死亡|财产损失|名誉|隐私|产品|交通事故|医疗|动物咬伤"),
        RequiredInfo(field: "损害后果",   question: "造成了什么具体损害（伤亡/财产损失/精神损害）？",
                     regexHint: #"受伤|死亡|残疾|财产损失|\d+元|精神损害"#),
        RequiredInfo(field: "侵权人身份", question: "侵权方是谁（个人/公司/雇主/产品生产者）？",
                     regexHint: "个人|公司|企业|雇主|单位|生产者|销售者|驾驶人|医院|学校"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["侵权责任", "损害赔偿", "精神损害", "无过错责任"],
    answerTemplate: "你是侵权责任法细分专家。基于以下法条，分析：\n1. 适用何种归责原则（过错/无过错/公平责任）\n2. 侵权构成要件是否满足\n3. 赔偿范围（医疗费/误工费/残疾赔偿金/死亡赔偿金/精神损害赔偿）\n4. 诉讼时效（一般三年）\n引用具体条文，给出赔偿项目清单。"
)

let marriageExpert = SubExpert(
    name: "婚姻家庭专家",
    domain: "离婚、抚养权、财产分割、婚姻效力、家庭暴力",
    requiredInfo: [
        RequiredInfo(field: "婚姻状况", question: "当前婚姻状态（已婚/离婚中/未婚同居/再婚）？",
                     regexHint: "已婚|离婚|结婚|同居|未婚|再婚|分居"),
        RequiredInfo(field: "纠纷类型", question: "主要纠纷是什么（离婚/子女抚养权/财产分割/家庭暴力）？",
                     regexHint: "离婚|抚养|监护|财产分割|家庭暴力|出轨|婚前财产|共同财产|彩礼"),
        RequiredInfo(field: "子女情况", question: "有无未成年子女？子女年龄？",
                     regexHint: #"\d+岁|孩子|子女|小孩|儿子|女儿|未成年|抚养"#),
        RequiredInfo(field: "财产情况", question: "主要财产有哪些（房产/存款/股权）？",
                     regexHint: #"房产|房屋|存款|股权|婚前|婚后|共同财产|\d+万"#),
        RequiredInfo(field: "过错方",   question: "是否存在过错（家暴/出轨/遗弃）？",
                     regexHint: "家暴|出轨|外遇|遗弃|分居|过错|重婚"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["离婚协议", "夫妻共同财产", "子女抚养费", "彩礼返还", "家庭暴力"],
    answerTemplate: "你是婚姻家庭法细分专家。基于以下法条，分析：\n1. 离婚条件是否具备（协议离婚/诉讼离婚）\n2. 子女抚养权归属原则\n3. 夫妻共同财产分割原则（有过错方少分/婚前财产不分）\n4. 家庭暴力的法律后果\n语言通俗，明确给出建议路径。"
)

let inheritanceExpert = SubExpert(
    name: "继承专家",
    domain: "法定继承、遗嘱继承、遗产分配、继承放弃",
    requiredInfo: [
        RequiredInfo(field: "遗嘱情况",   question: "死者是否留有遗嘱？遗嘱形式（书面/公证/口头）？",
                     regexHint: "遗嘱|公证|立遗嘱|无遗嘱|口头遗嘱|书面遗嘱"),
        RequiredInfo(field: "继承人情况", question: "继承人有哪些（配偶/子女/父母/兄弟姐妹）？",
                     regexHint: "配偶|子女|父母|兄弟|姐妹|孙子|外孙|继承人"),
        RequiredInfo(field: "遗产情况",   question: "主要遗产是什么（房产/存款/债务/股权）？",
                     regexHint: "房产|存款|债务|股权|遗产|财产"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["法定继承", "遗嘱继承", "继承顺序", "遗产债务", "遗嘱效力"],
    answerTemplate: "你是继承法细分专家。基于以下法条，分析：\n1. 遗嘱是否有效（形式要件/内容要件）\n2. 法定继承的顺序和份额\n3. 必留份（特留份）制度的适用\n4. 继承债务的处理\n明确列出继承顺序和份额计算方式。"
)

let personalityExpert = SubExpert(
    name: "人格权专家",
    domain: "名誉权、隐私权、肖像权、姓名权、网络侵权",
    requiredInfo: [
        RequiredInfo(field: "人格权类型", question: "侵害的是哪种人格权（名誉/隐私/肖像/姓名）？",
                     regexHint: "名誉|隐私|肖像|姓名|荣誉|诽谤|侮辱|泄露"),
        RequiredInfo(field: "侵权行为",   question: "侵权方具体做了什么（网络发布/散布谣言/未授权使用照片）？",
                     regexHint: "发布|散布|传播|谣言|未经授权|使用照片|泄露隐私|侮辱|诽谤"),
        RequiredInfo(field: "损害后果",   question: "造成了什么后果（名誉受损/精神痛苦/经济损失）？",
                     regexHint: #"名誉受损|精神|抑郁|失业|经济损失|\d+元"#),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: [],
    ftsDomains: ["民法典", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["名誉权", "隐私权", "肖像权", "网络侵权", "删除侵权内容"],
    answerTemplate: "你是人格权法细分专家。基于以下法条，分析：\n1. 哪种人格权受到侵害及法律依据\n2. 受害方可以主张的救济（删除/更正/赔礼道歉/损害赔偿）\n3. 平台责任（通知-删除规则）\n4. 如何证明损害及举证责任\n明确说明维权步骤。"
)

// MARK: - 刑法专家组

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

// MARK: - 劳动法专家组

let laborContractExpert = SubExpert(
    name: "劳动合同专家",
    domain: "劳动合同签订、解除、终止、经济补偿",
    requiredInfo: [
        RequiredInfo(field: "劳动关系类型", question: "劳动关系类型（正式合同/试用期/劳务派遣/外包）？",
                     regexHint: "正式员工|试用期|劳务派遣|外包|兼职|合同工|临时工"),
        RequiredInfo(field: "工作年限",     question: "在该单位工作了多久？",
                     regexHint: #"\d+\s*(?:年|个月|月)"#),
        RequiredInfo(field: "解除方式",     question: "劳动关系如何解除的（被辞退/协商解除/自行辞职）？",
                     regexHint: "辞退|开除|解雇|协商离职|自行辞职|主动离职|合同到期|不续签"),
        RequiredInfo(field: "是否签合同",   question: "是否签订了书面劳动合同？",
                     regexHint: "有合同|没有合同|未签合同|口头约定|已签"),
    ],
    lawTitles: ["中华人民共和国劳动合同法", "中华人民共和国劳动法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["经济补偿金", "赔偿金", "违法解除", "未签合同双倍工资", "竞业限制"],
    answerTemplate: "你是劳动合同法细分专家。基于以下法条，分析：\n1. 解除劳动合同是否合法\n2. 经济补偿金（N）或赔偿金（2N）的计算方式\n3. 未签书面劳动合同的双倍工资主张\n4. 维权路径（劳动仲裁→法院）及时效（1年）\n明确给出补偿金额的计算公式。"
)

let wageExpert = SubExpert(
    name: "工资福利专家",
    domain: "工资拖欠、加班费、最低工资、社会保险",
    requiredInfo: [
        RequiredInfo(field: "拖欠类型", question: "拖欠的是基本工资、加班费还是提成奖金？",
                     regexHint: "基本工资|加班费|提成|奖金|绩效|社保|五险一金|拖欠"),
        RequiredInfo(field: "拖欠金额", question: "拖欠金额是多少？拖欠了多久？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千)|\d+\s*个月"#),
    ],
    lawTitles: ["中华人民共和国劳动法", "中华人民共和国劳动合同法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["工资报酬", "加班工资", "最低工资标准", "社会保险费", "拖欠工资"],
    answerTemplate: "你是劳动工资福利细分专家。基于以下法条，分析：\n1. 工资拖欠的法律认定及追偿权利\n2. 加班费计算标准（150%/200%/300%）\n3. 社会保险缴纳义务及违法后果\n4. 劳动仲裁追偿的时效和流程\n给出具体的计算示例（如可能）。"
)

let workinjuryExpert = SubExpert(
    name: "工伤职业病专家",
    domain: "工伤认定、工伤赔偿、职业病、工亡",
    requiredInfo: [
        RequiredInfo(field: "事故情形", question: "受伤是在什么情况下发生的（工作时间/上下班途中/职业病）？",
                     regexHint: "工作时间|上班途中|下班途中|出差|职业病|工作原因|因公"),
        RequiredInfo(field: "伤情程度", question: "伤情或伤残程度（住院/伤残等级/死亡）？",
                     regexHint: "住院|伤残|等级|死亡|职业病|工亡"),
        RequiredInfo(field: "参保情况", question: "单位是否为其缴纳工伤保险？",
                     regexHint: "工伤保险|参保|未参保|未缴|社保"),
    ],
    lawTitles: ["中华人民共和国劳动法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["工伤认定", "工伤保险", "劳动能力鉴定", "一次性伤残补助金", "工亡补助金"],
    answerTemplate: "你是工伤职业病细分专家。基于以下法条，分析：\n1. 是否符合工伤认定条件（工作时间/工作场所/工作原因三要素）\n2. 工伤申报流程和时限（30日/1年）\n3. 工伤保险待遇（医疗费/伤残补助金/护理费/停工留薪）\n4. 单位未参保时的赔偿责任\n明确列出各项赔偿项目。"
)

let laborDisputeExpert = SubExpert(
    name: "劳动争议专家",
    domain: "劳动仲裁、诉讼时效、证据、仲裁前置",
    requiredInfo: [
        RequiredInfo(field: "争议事项", question: "劳动争议的核心事项是什么（工资/解除/工伤/社保）？",
                     regexHint: "工资|解除|工伤|社保|竞业限制|服务期|培训费"),
        RequiredInfo(field: "时间节点", question: "劳动关系结束多久了？是否超过1年仲裁时效？",
                     regexHint: #"\d+\s*(?:年|个月)|最近|刚刚|超过一年|时效"#),
    ],
    lawTitles: ["中华人民共和国劳动争议调解仲裁法"],
    chapterIdHints: [],
    ftsDomains: ["社会法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["劳动仲裁", "仲裁时效", "举证责任", "仲裁前置", "一裁终局"],
    answerTemplate: "你是劳动争议程序细分专家。基于以下法条，分析：\n1. 劳动仲裁时效（1年）及起算点\n2. 仲裁前置原则与例外（一裁终局情形）\n3. 举证责任分配（用人单位举证倒置规则）\n4. 仲裁→一审→二审的完整路径和时限\n给出明确的维权时间表。"
)

// MARK: - 经济法专家组

let consumerExpert = SubExpert(
    name: "消费者权益专家",
    domain: "假冒伪劣、退款、三倍赔偿、平台责任、欺诈",
    requiredInfo: [
        RequiredInfo(field: "购买渠道", question: "在哪里购买的（线上平台/实体店/直播带货）？",
                     regexHint: "淘宝|京东|拼多多|抖音|快手|微商|实体店|超市|直播|网购"),
        RequiredInfo(field: "问题类型", question: "商品/服务问题是什么（假货/虚假宣传/拒绝退款/过期食品）？",
                     regexHint: "假货|假冒|伪劣|不合格|虚假宣传|拒绝退款|过期|变质|食品安全"),
        RequiredInfo(field: "金额损失", question: "购买金额是多少？",
                     regexHint: #"\d+\s*(?:万|元|块|百|千)"#),
    ],
    lawTitles: ["中华人民共和国消费者权益保护法", "中华人民共和国食品安全法",
                "中华人民共和国产品质量法", "中华人民共和国电子商务法"],
    chapterIdHints: [],
    ftsDomains: ["经济法", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["三倍赔偿", "退一赔三", "退一赔十", "平台责任", "欺诈消费者"],
    answerTemplate: "你是消费者权益保护细分专家。基于以下法条，分析：\n1. 消费者可以主张的具体权利（退货/退款/赔偿）\n2. 惩罚性赔偿倍数（三倍/十倍）及适用条件\n3. 平台连带责任的适用场景\n4. 投诉路径（12315/市场监管局/法院）\n明确给出赔偿金额计算和维权步骤。"
)

let productExpert = SubExpert(
    name: "产品质量专家",
    domain: "产品缺陷、侵权赔偿、召回、生产者销售者责任",
    requiredInfo: [
        RequiredInfo(field: "产品类型", question: "是什么产品（食品/药品/家电/车辆/儿童用品）？",
                     regexHint: "食品|药品|家电|车辆|汽车|儿童|玩具|工业品|医疗器械"),
        RequiredInfo(field: "损害后果", question: "产品缺陷造成了什么损害（人身伤害/财产损失）？",
                     regexHint: "受伤|烫伤|中毒|财产损失|损坏|死亡|伤残"),
    ],
    lawTitles: ["中华人民共和国产品质量法", "中华人民共和国消费者权益保护法"],
    chapterIdHints: [],
    ftsDomains: ["经济法"],
    ftsCategories: ["法律"],
    ftsKeywordsExtra: ["产品缺陷", "产品责任", "生产者责任", "缺陷产品召回"],
    answerTemplate: "你是产品质量法细分专家。基于以下法条，分析：\n1. 产品缺陷的认定标准\n2. 生产者与销售者的责任划分\n3. 受害方可以主张的赔偿项目\n4. 举证责任（产品缺陷的证明方式）\n明确说明追责路径。"
)

let ecommerceExpert = SubExpert(
    name: "电子商务专家",
    domain: "网络交易、平台责任、刷单、大数据杀熟",
    requiredInfo: [
        RequiredInfo(field: "纠纷类型", question: "电子商务纠纷类型（假货/大数据杀熟/平台封号）？",
                     regexHint: "假货|刷单|大数据杀熟|差别定价|封号|扣押保证金"),
        RequiredInfo(field: "平台名称", question: "涉及哪个电商平台？",
                     regexHint: "淘宝|京东|拼多多|抖音|快手|小红书|亚马逊"),
    ],
    lawTitles: ["中华人民共和国电子商务法", "中华人民共和国消费者权益保护法"],
    chapterIdHints: [],
    ftsDomains: ["经济法"],
    ftsCategories: ["法律"],
    ftsKeywordsExtra: ["电子商务平台", "平台责任", "搭售", "大数据杀熟", "用户评价"],
    answerTemplate: "你是电子商务法细分专家。基于以下法条，分析：\n1. 电商平台的法律责任（知道或应当知道侵权行为的连带责任）\n2. 大数据杀熟的法律认定\n3. 消费者维权路径（申请退款/投诉平台/仲裁/诉讼）\n4. 平台封号/扣押保证金的合法性审查\n给出具体的操作建议。"
)

let companyExpert = SubExpert(
    name: "公司商事专家",
    domain: "公司设立、股东权利、公司决议、对外担保、破产",
    requiredInfo: [
        RequiredInfo(field: "公司类型", question: "是有限责任公司还是股份公司？",
                     regexHint: "有限责任公司|股份公司|合伙企业|个人独资"),
        RequiredInfo(field: "纠纷类型", question: "纠纷类型（股东纠纷/公司决议效力/对外担保/破产清算）？",
                     regexHint: "股东纠纷|股权|分红|决议|担保|破产|清算|注册|设立"),
    ],
    lawTitles: ["中华人民共和国公司法"],
    chapterIdHints: [],
    ftsDomains: ["经济法", "民法商法"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["股东权利", "公司决议", "股权转让", "公司担保", "破产清算"],
    answerTemplate: "你是公司商事法细分专家。基于以下法条，分析：\n1. 股东权利的法律依据\n2. 公司决议的效力及瑕疵认定\n3. 公司对外担保的法律规范\n4. 股东/高管的赔偿责任\n引用公司法条文，给出操作建议。"
)

// MARK: - 诉讼专家组

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
        RequiredInfo(field: "当事人身份", question: "咨询人身份（受害方/犯罪嫌疑人/家属）？",
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

// MARK: - All groups

let allExpertGroups: [String: ExpertGroup] = [
    "民法专家组": ExpertGroup(
        name: "民法专家组",
        description: "处理民事法律问题：合同、物权、侵权、婚姻家庭、继承、人格权",
        subExperts: [contractExpert, propertyExpert, tortExpert,
                     marriageExpert, inheritanceExpert, personalityExpert],
        routingKeywords: ["合同","违约","租赁","买卖","借款","物权","所有权","抵押",
                          "侵权","赔偿","离婚","抚养","继承","遗产","遗嘱",
                          "名誉","隐私","肖像","人格权","民法典"]
    ),
    "刑法专家组": ExpertGroup(
        name: "刑法专家组",
        description: "处理刑事犯罪问题：财产犯罪、人身伤害、经济犯罪、职务犯罪",
        subExperts: [crimePropertyExpert, crimePersonExpert, crimeEconomyExpert, crimeCorruptionExpert],
        routingKeywords: ["犯罪","刑事","坐牢","判刑","立案","报案","刑法",
                          "盗窃","诈骗","抢劫","故意伤害","故意杀人","贪污","受贿"]
    ),
    "劳动法专家组": ExpertGroup(
        name: "劳动法专家组",
        description: "处理劳动关系问题：劳动合同、工资、工伤、劳动争议",
        subExperts: [laborContractExpert, wageExpert, workinjuryExpert, laborDisputeExpert],
        routingKeywords: ["劳动","工资","加班费","辞退","解雇","工伤","职业病",
                          "劳动合同","经济补偿","仲裁","试用期","社保","五险一金","拖欠工资"]
    ),
    "行政法专家组": ExpertGroup(
        name: "行政法专家组",
        description: "处理行政机关与公民的法律关系：行政处罚、许可、复议",
        subExperts: [adminProcedureExpert],
        routingKeywords: ["行政","政府","处罚","吊销","罚款","许可证","审批",
                          "拆迁","征收","行政复议","行政诉讼","工商"]
    ),
    "经济法专家组": ExpertGroup(
        name: "经济法专家组",
        description: "处理市场监管、消费者权益、公司商事法律问题",
        subExperts: [consumerExpert, productExpert, ecommerceExpert, companyExpert],
        routingKeywords: ["消费者","购物","假货","退款","维权","质量","产品缺陷",
                          "网购","电商","平台","公司","股东","破产","食品安全"]
    ),
    "诉讼专家组": ExpertGroup(
        name: "诉讼专家组",
        description: "处理诉讼程序、管辖、证据、仲裁等程序性问题",
        subExperts: [civilProcedureExpert, criminalProcedureExpert, adminProcedureExpert],
        routingKeywords: ["诉讼","起诉","法院","仲裁","管辖","证据","上诉",
                          "执行","保全","查封","冻结","程序","时效","去哪告"]
    ),
]
