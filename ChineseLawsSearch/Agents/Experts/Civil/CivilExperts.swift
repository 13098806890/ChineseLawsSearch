// CivilExperts.swift — 民法专家索引（汇总所有民法典细分专家）
// 各细分专家定义分散在 Civil/ 子目录中，此文件只做聚合。

import Foundation

// MARK: - 合同编（Contract/）
// contractGeneralExpert      — 合同通则（成立/效力/违约/解除）
// saleContractExpert         — 买卖合同（含商品房）
// leaseContractExpert        — 租赁合同（含融资租赁）
// loanContractExpert         — 借款合同（含保证担保）
// constructionContractExpert — 建设工程合同（含承揽）
// serviceContractExpert      — 委托/物业/中介/合伙/保管

// MARK: - 侵权责任编（Tort/）
// generalTortExpert          — 侵权通则（损害赔偿、共同侵权、雇主责任）
// trafficAccidentExpert      — 交通事故责任
// medicalLiabilityExpert     — 医疗损害责任
// productLiabilityExpert     — 产品责任
// otherTortExpert            — 特殊侵权（环境/高度危险/动物/建筑物）

// MARK: - 人格权编（Personality/）
// reputationPrivacyExpert    — 名誉权/隐私权/肖像权/个人信息
// lifeHealthRightsExpert     — 生命权/身体权/健康权

// MARK: - 物权编（Property/）
// propertyOwnershipExpert    — 不动产所有权/登记/善意取得/共有
// securityInterestExpert     — 担保物权（抵押/质押/留置）
// usufructExpert             — 用益物权（土地承包/宅基地/居住权/地役权）

// MARK: - 婚姻家庭编（Family/）
// divorcePropertyExpert      — 离婚财产分割/彩礼
// childCustodyExpert         — 子女抚养权/抚养费/探视权
// adoptionExpert             — 收养

// MARK: - 继承编（Inheritance/）
// intestateInheritanceExpert    — 法定继承
// testamentaryInheritanceExpert — 遗嘱继承/遗赠

// MARK: - 总则编（General/）
// civilJurisdictionExpert    — 民事法律行为效力/代理
// limitationExpert           — 诉讼时效

let allCivilExperts: [SubExpert] = [
    // 合同编
    contractGeneralExpert,
    saleContractExpert,
    leaseContractExpert,
    loanContractExpert,
    constructionContractExpert,
    serviceContractExpert,
    // 侵权责任编
    generalTortExpert,
    trafficAccidentExpert,
    medicalLiabilityExpert,
    productLiabilityExpert,
    otherTortExpert,
    // 人格权编
    reputationPrivacyExpert,
    lifeHealthRightsExpert,
    // 物权编
    propertyOwnershipExpert,
    securityInterestExpert,
    usufructExpert,
    // 婚姻家庭编
    divorcePropertyExpert,
    childCustodyExpert,
    adoptionExpert,
    // 继承编
    intestateInheritanceExpert,
    testamentaryInheritanceExpert,
    // 总则编
    civilJurisdictionExpert,
    limitationExpert,
]
