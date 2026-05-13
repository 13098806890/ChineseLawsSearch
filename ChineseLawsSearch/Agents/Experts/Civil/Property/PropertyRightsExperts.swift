// PropertyRightsExperts.swift — 物权编专家（不动产、担保物权）

import Foundation

// 物权编章节 IDs
private let chPropGeneral: [Int]   = [34685, 34690, 34718]  // 一般规定、变动、保护
private let chOwnership: [Int]     = [34726, 34733, 34759, 34777, 34787, 34802]  // 所有权各章
private let chUsufruct: [Int]      = [34815, 34823, 34838, 34857, 34862, 34869]  // 用益物权各章
private let chSecurity: [Int]      = [34884, 34893, 34927, 34952, 34964]  // 担保物权各章

let propertyOwnershipExpert = SubExpert(
    name: "不动产所有权专家",
    domain: "房屋所有权、不动产登记、善意取得、共有、相邻关系、业主权利",
    requiredInfo: [
        RequiredInfo(field: "物权类型",
                     question: "涉及的是哪类物权（所有权/共有/相邻关系/业主区分所有）？",
                     regexHint: "所有权|产权|共有|共同|相邻|通道|采光|噪音|业主|物业|公摊"),
        RequiredInfo(field: "登记状态",
                     question: "该不动产是否已办理产权登记（不动产证）？是否存在登记与实际不符？",
                     regexHint: "不动产证|产权证|房产证|登记|过户|未登记|登记错误"),
        RequiredInfo(field: "争议性质",
                     question: "争议是关于所有权归属、还是相邻权利（通行/采光/噪音）、还是业主纠纷？",
                     regexHint: "归属|产权纠纷|通行权|采光|遮挡|噪音|业委会|物业费|公共区域"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chPropGeneral + chOwnership,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["不动产登记", "善意取得", "共有分割", "相邻权", "业主区分所有权",
                       "物权保护请求权", "排除妨碍"],
    answerTemplate: """
    你是不动产所有权细分专家。基于以下法条，以第三方视角分析：
    1. 物权归属认定：登记公示效力，登记与实际不符的处理
    2. 善意取得制度：受让人是否满足"善意+合理对价+登记"三要件
    3. 共有：按份共有vs共同共有的分割规则和优先购买权
    4. 相邻权：采光/通风/通行/排水的相邻权保护范围
    5. 维权手段：物权确认请求权/排除妨碍请求权/恢复原状请求权
    引用物权编司法解释的具体条文。
    """
)

let securityInterestExpert = SubExpert(
    name: "担保物权专家",
    domain: "抵押权、质押、留置权、担保合同效力、担保物权实现、优先受偿",
    requiredInfo: [
        RequiredInfo(field: "担保类型",
                     question: "担保是哪种形式（不动产抵押/动产抵押/股权质押/货物质押/留置）？",
                     regexHint: "抵押|质押|留置|担保|抵押权|质押权|房产抵押|股权质押|货物质押"),
        RequiredInfo(field: "登记情况",
                     question: "抵押/质押是否已向登记机关办理登记？",
                     regexHint: "登记|已登记|未登记|抵押登记|质押登记|公证|不动产登记"),
        RequiredInfo(field: "主债权状态",
                     question: "主债权（贷款/借款）是否到期？债务人是否已违约？",
                     regexHint: "到期|逾期|违约|未还款|借款到期|贷款"),
    ],
    lawTitles: [
        "中华人民共和国民法典",
        "最高人民法院关于适用《中华人民共和国民法典》有关担保制度的解释",
    ],
    chapterIdHints: chSecurity + [13043],
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["抵押权实现", "拍卖变卖", "优先受偿", "最高额抵押", "留置权",
                       "流押条款无效", "担保制度司法解释", "担保制度解释",
                       "浮动抵押", "动产抵押未登记", "善意取得担保物权", "股权质押公示"],
    answerTemplate: """
    你是担保物权细分专家。基于以下法条，以第三方视角分析：
    1. 设立要件：不动产抵押须登记（未登记不生效）；动产抵押可设立但未登记不能对抗善意第三人；质押须转移占有/登记
    2. 担保物权顺位：同一财产多重抵押按登记先后顺序，未登记的最后受偿
    3. 实现程序：主债权到期未清偿 → 协议折价/拍卖/变卖（禁止流押/流质，但可约定优先以物抵债）
    4. 担保物权与建设工程价款优先权：工程价款优先权优先于抵押权（担保制度解释第54-56条）
    5. 善意取得担保物权：受让人善意+合理对价+已登记/占有，可对抗原权利人
    引用担保制度解释的具体条文，结合九民纪要担保纠纷部分。
    """
)

let usufructExpert = SubExpert(
    name: "用益物权专家",
    domain: "土地承包经营权、建设用地使用权、宅基地使用权、居住权、地役权",
    requiredInfo: [
        RequiredInfo(field: "用益物权类型",
                     question: "涉及哪种用益物权（土地承包/宅基地/建设用地/居住权/地役权）？",
                     regexHint: "土地承包|宅基地|建设用地|居住权|地役权|农村土地|集体土地"),
        RequiredInfo(field: "纠纷核心",
                     question: "核心争议是什么（流转/收回/侵占/补偿/抵押融资）？",
                     regexHint: "流转|出租|转让|抵押|收回|征收|补偿|侵占|建房"),
    ],
    lawTitles: ["中华人民共和国民法典"],
    chapterIdHints: chUsufruct,
    ftsDomains: ["民法典"],
    ftsCategories: ["法律", "司法解释"],
    ftsKeywordsExtra: ["土地承包经营权", "宅基地使用权", "居住权登记", "地役权",
                       "建设用地使用权出让", "农村土地流转"],
    answerTemplate: """
    你是用益物权细分专家。基于以下法条，以第三方视角分析：
    1. 该用益物权的取得方式和保护范围
    2. 流转限制：宅基地/土地承包经营权的流转条件和限制
    3. 居住权：设立登记要件，居住权人vs所有权人的权利边界
    4. 征收补偿：用益物权人有权独立获得补偿
    5. 维权：物权确认诉讼的管辖和举证
    引用具体条文，区分城市与农村土地的不同规则。
    """
)
