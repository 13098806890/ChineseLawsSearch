//
//  DatabaseManager.swift
//  ChineseLawsSearch
//

import Foundation
import SQLite3

// MARK: - 数据模型

struct LawMeta: Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let legalDomain: String
    let pubDate: String
    let effectiveDate: String
    let issuingOrg: String
    let docNumber: String
    let totalArticles: Int
    let subjectArea: String
}

struct LawNode: Identifiable {
    let id: Int
    let lawId: Int
    let parentId: Int?
    let type: String        // part / chapter / section / article
    let title: String
    let content: String
    let globalOrder: Int
    let articleNum: Int?
}

struct SearchResult: Identifiable {
    let id: Int             // node id
    let lawId: Int
    let lawTitle: String
    let articleNumber: String
    let content: String
    let nodeArticleNum: Int?
}

// 某条文引用的其他法条（出向）
struct OutgoingRef: Identifiable {
    let id: Int
    let fromArticleNum: Int
    let rawText: String
    let toLawId: Int
    let toLawTitle: String
    let toArticleNum: Int
}

// 某条文被哪些法条引用（入向）
struct IncomingRef: Identifiable {
    let id: Int
    let toArticleNum: Int
    let fromLawId: Int
    let fromLawTitle: String
    let fromArticleNum: Int
    let fromArticleLabel: String
}

// MARK: - DatabaseManager

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private var enhDb: OpaquePointer?

    private init() {
        guard let url = Bundle.main.url(forResource: "law_content", withExtension: "db") else {
            print("DatabaseManager: 找不到 law_content.db")
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("DatabaseManager: 无法打开数据库")
            db = nil
        }

        if let enhUrl = Bundle.main.url(forResource: "law_enhancements", withExtension: "db") {
            if sqlite3_open_v2(enhUrl.path, &enhDb, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                print("DatabaseManager: 无法打开 law_enhancements.db")
                enhDb = nil
            }
        }
    }

    deinit {
        sqlite3_close(db)
        sqlite3_close(enhDb)
    }

    // MARK: 读取 law_menu.json 菜单结构

    struct MenuLaw {
        let id: Int
        let title: String
    }
    struct MenuSubgroup {
        let label: String
        let laws: [MenuLaw]
    }
    struct MenuGroup {
        let label: String
        let subgroups: [MenuSubgroup]
    }
    struct LawMenu {
        let name: String
        let version: String
        let groups: [MenuGroup]
    }

    func loadMenu() -> LawMenu? {
        guard let url = Bundle.main.url(forResource: "law_menu", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String,
              let version = obj["version"] as? String,
              let groupsArr = obj["groups"] as? [[String: Any]]
        else { return nil }

        let groups = groupsArr.compactMap { gObj -> MenuGroup? in
            guard let label = gObj["label"] as? String,
                  let subsArr = gObj["subgroups"] as? [[String: Any]]
            else { return nil }
            let subs = subsArr.compactMap { sObj -> MenuSubgroup? in
                guard let slabel = sObj["label"] as? String,
                      let lawsArr = sObj["laws"] as? [[String: Any]]
                else { return nil }
                let laws = lawsArr.compactMap { lObj -> MenuLaw? in
                    guard let id = lObj["id"] as? Int,
                          let title = lObj["title"] as? String
                    else { return nil }
                    return MenuLaw(id: id, title: title)
                }
                return MenuSubgroup(label: slabel, laws: laws)
            }
            return MenuGroup(label: label, subgroups: subs)
        }
        return LawMenu(name: name, version: version, groups: groups)
    }

    // MARK: 某部法律的全部节点

    func nodes(lawId: Int) -> [LawNode] {
        let sql = """
            SELECT id, law_id, parent_id, type, title, content, global_order, article_num
            FROM nodes
            WHERE law_id = ?
            ORDER BY global_order
            """
        var stmt: OpaquePointer?
        var result: [LawNode] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(lawId))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let parentCol = sqlite3_column_type(stmt, 2)
            let parentId: Int? = parentCol == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 2))
            let artNumCol = sqlite3_column_type(stmt, 7)
            let artNum: Int? = artNumCol == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 7))
            result.append(LawNode(
                id:          Int(sqlite3_column_int(stmt, 0)),
                lawId:       Int(sqlite3_column_int(stmt, 1)),
                parentId:    parentId,
                type:        str(stmt, 3),
                title:       str(stmt, 4),
                content:     str(stmt, 5),
                globalOrder: Int(sqlite3_column_int(stmt, 6)),
                articleNum:  artNum
            ))
        }
        return result
    }

    // MARK: 法律元数据（by id）

    func lawMeta(id: Int) -> LawMeta? {
        let sql = """
            SELECT id, title, category, legal_domain, pub_date, effective_date,
                   issuing_org, doc_number, total_articles,
                   COALESCE(subject_area, '') AS subject_area
            FROM laws
            WHERE id = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(id))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return LawMeta(
            id:            Int(sqlite3_column_int(stmt, 0)),
            title:         str(stmt, 1),
            category:      str(stmt, 2),
            legalDomain:   str(stmt, 3),
            pubDate:       str(stmt, 4),
            effectiveDate: str(stmt, 5),
            issuingOrg:    str(stmt, 6),
            docNumber:     str(stmt, 7),
            totalArticles: Int(sqlite3_column_int(stmt, 8)),
            subjectArea:   str(stmt, 9)
        )
    }

    // MARK: 某部法律的全部出向引用（按条文分组用）

    func outgoingRefsForLaw(lawId: Int) -> [OutgoingRef] {
        let sql = """
            SELECT ar.id, ar.from_article_num, ar.raw_text, ar.to_law_id, l.title, ar.to_article_num
            FROM article_references ar
            JOIN laws l ON ar.to_law_id = l.id
            WHERE ar.from_law_id = ?
              AND ar.resolved = 1 AND ar.to_article_num IS NOT NULL
            """
        var stmt: OpaquePointer?
        var result: [OutgoingRef] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(lawId))
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(OutgoingRef(
                id:             Int(sqlite3_column_int(stmt, 0)),
                fromArticleNum: Int(sqlite3_column_int(stmt, 1)),
                rawText:        str(stmt, 2),
                toLawId:        Int(sqlite3_column_int(stmt, 3)),
                toLawTitle:     str(stmt, 4),
                toArticleNum:   Int(sqlite3_column_int(stmt, 5))
            ))
        }
        return result
    }

    // MARK: 某部法律的全部入向引用（按条文分组用）

    func incomingRefsForLaw(lawId: Int) -> [IncomingRef] {
        let sql = """
            SELECT ar.id, ar.to_article_num, ar.from_law_id, l.title, ar.from_article_num, n.article_number
            FROM article_references ar
            JOIN laws l ON ar.from_law_id = l.id
            JOIN nodes n ON ar.from_node_id = n.id
            WHERE ar.to_law_id = ?
              AND ar.resolved = 1 AND ar.ref_type = 'cross_law'
            """
        var stmt: OpaquePointer?
        var result: [IncomingRef] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(lawId))
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(IncomingRef(
                id:               Int(sqlite3_column_int(stmt, 0)),
                toArticleNum:     Int(sqlite3_column_int(stmt, 1)),
                fromLawId:        Int(sqlite3_column_int(stmt, 2)),
                fromLawTitle:     str(stmt, 3),
                fromArticleNum:   Int(sqlite3_column_int(stmt, 4)),
                fromArticleLabel: str(stmt, 5)
            ))
        }
        return result
    }

    // MARK: 按标题搜索法律

    func searchByTitle(query: String, limit: Int = 50) -> [LawMeta] {
        let sql = """
            SELECT id, title, category, legal_domain, pub_date, effective_date,
                   issuing_org, doc_number, total_articles,
                   COALESCE(subject_area, '') AS subject_area
            FROM laws
            WHERE is_current = 1 AND title LIKE ?
            ORDER BY title
            LIMIT ?
            """
        var stmt: OpaquePointer?
        var result: [LawMeta] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "%\(query)%", -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(LawMeta(
                id:            Int(sqlite3_column_int(stmt, 0)),
                title:         str(stmt, 1),
                category:      str(stmt, 2),
                legalDomain:   str(stmt, 3),
                pubDate:       str(stmt, 4),
                effectiveDate: str(stmt, 5),
                issuingOrg:    str(stmt, 6),
                docNumber:     str(stmt, 7),
                totalArticles: Int(sqlite3_column_int(stmt, 8)),
                subjectArea:   str(stmt, 9)
            ))
        }
        return result
    }

    // MARK: 条文内容搜索（自动选择索引）
    // 1-2字走 bigram FTS，3字以上走 trigram FTS，均为毫秒级
    // excludeArticleNumber: 屏蔽条号前缀匹配（3字以上走 content_body 列，短词在 Swift 过滤）

    func searchContent(query: String, limit: Int = 100,
                       excludeArticleNumber: Bool = false) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let cjkChars = query.unicodeScalars.filter {
            $0.value >= 0x4E00 && $0.value <= 0x9FFF
        }
        let useBigram = cjkChars.count < 3

        let sql: String
        let ftsQuery: String

        if useBigram {
            // bigram 表：每个字空格分开（AND 语义）
            ftsQuery = cjkChars.map { String($0) }.joined(separator: " ")
            sql = """
                SELECT n.id, n.law_id, l.title, n.article_number, n.content, n.article_num
                FROM nodes_fts_bigram f
                JOIN nodes n ON f.rowid = n.id
                JOIN laws  l ON n.law_id = l.id
                WHERE nodes_fts_bigram MATCH ? AND n.type = 'article' AND l.is_current = 1
                LIMIT ?
                """
        } else {
            ftsQuery = query
            // 屏蔽条号时搜 content_body 列，否则搜全文
            let col = excludeArticleNumber ? "content_body" : "nodes_fts"
            sql = """
                SELECT n.id, n.law_id, l.title, n.article_number, n.content, n.article_num
                FROM nodes_fts f
                JOIN nodes n ON f.rowid = n.id
                JOIN laws  l ON n.law_id = l.id
                WHERE \(col) MATCH ? AND n.type = 'article' AND l.is_current = 1
                LIMIT ?
                """
        }

        var stmt: OpaquePointer?
        var result: [SearchResult] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, transient)
        sqlite3_bind_int(stmt,  2, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let content = str(stmt, 4)
            // 短词屏蔽条号：bigram 无 content_body，在 Swift 侧过滤
            if useBigram && excludeArticleNumber {
                let artNum = str(stmt, 3)
                let body   = content.replacingOccurrences(of: artNum, with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !body.contains(query) { continue }
            }
            let artNumCol = sqlite3_column_type(stmt, 5)
            let artNum: Int? = artNumCol == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5))
            result.append(SearchResult(
                id:             Int(sqlite3_column_int(stmt, 0)),
                lawId:          Int(sqlite3_column_int(stmt, 1)),
                lawTitle:       str(stmt, 2),
                articleNumber:  str(stmt, 3),
                content:        content,
                nodeArticleNum: artNum
            ))
        }
        return result
    }

    // MARK: 数字转换工具

    /// 把查询词里的阿拉伯数字转成中文数字，或中文数字转成阿拉伯数字。
    /// 返回转换后的变体（若无数字或转换结果与原词相同则返回 nil）。
    static func numberVariant(of query: String) -> String? {
        // 阿拉伯 → 中文
        if query.range(of: #"[0-9]+"#, options: .regularExpression) != nil {
            let result = arabicToChinese(query)
            return result == query ? nil : result
        }
        // 中文数字 → 阿拉伯
        let cnDigits: Set<Character> = ["零","一","二","三","四","五","六","七","八","九","十","百","千","万"]
        if query.contains(where: { cnDigits.contains($0) }) {
            let result = chineseToArabic(query)
            return result == query ? nil : result
        }
        return nil
    }

    private static func arabicToChinese(_ s: String) -> String {
        let pattern = try! NSRegularExpression(pattern: #"[0-9]+"#)
        var result = s
        var offset = 0
        for match in pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let range  = Range(match.range, in: s)!
            let numStr = String(s[range])
            guard let n = Int(numStr) else { continue }
            let cn = intToChinese(n)
            let nsRange = NSRange(range, in: result)
            let shifted = NSRange(location: nsRange.location + offset, length: nsRange.length)
            result = (result as NSString).replacingCharacters(in: shifted, with: cn)
            offset += cn.count - numStr.count
        }
        return result
    }

    private static func chineseToArabic(_ s: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "[零一二三四五六七八九十百千万]+")
        var result = s
        var offset = 0
        for match in pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let range  = Range(match.range, in: s)!
            let cnStr  = String(s[range])
            let n      = chineseToInt(cnStr)
            if n == 0 { continue }
            let arabic = "\(n)"
            let nsRange = NSRange(range, in: result)
            let shifted = NSRange(location: nsRange.location + offset, length: nsRange.length)
            result = (result as NSString).replacingCharacters(in: shifted, with: arabic)
            offset += arabic.count - cnStr.count
        }
        return result
    }

    private static func intToChinese(_ n: Int) -> String {
        let digits = ["零","一","二","三","四","五","六","七","八","九"]
        if n < 10  { return digits[n] }
        if n < 20  { return "十" + (n % 10 == 0 ? "" : digits[n % 10]) }
        if n < 100 {
            let tens = digits[n / 10] + "十"
            let ones = n % 10 == 0 ? "" : digits[n % 10]
            return tens + ones
        }
        if n < 1000 {
            let h    = digits[n / 100] + "百"
            let rest = n % 100
            if rest == 0 { return h }
            return h + (rest < 10 ? "零" : "") + intToChinese(rest)
        }
        if n < 10000 {
            let k    = digits[n / 1000] + "千"
            let rest = n % 1000
            if rest == 0 { return k }
            return k + (rest < 100 ? "零" : "") + intToChinese(rest)
        }
        return "\(n)"  // 超过万直接返回阿拉伯
    }

    private static func chineseToInt(_ s: String) -> Int {
        let val: [Character: Int] = [
            "零":0,"一":1,"二":2,"三":3,"四":4,
            "五":5,"六":6,"七":7,"八":8,"九":9,
            "十":10,"百":100,"千":1000,"万":10000
        ]
        var result = 0
        var tmp    = 0
        var hasUnit = false
        for ch in s {
            let v = val[ch] ?? 0
            if v >= 10 {
                result += (tmp == 0 && !hasUnit ? 1 : tmp) * v
                tmp = 0
                hasUnit = true
            } else {
                tmp = v
            }
        }
        return result + tmp
    }

    // MARK: Enhancement DB — RAG support

    /// 别名扩展：colloquial → [legal_term]（term_aliases + alias_patches 两表合并）
    func legalTerms(for colloquial: String) -> [String] {
        guard let edb = enhDb else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for table in ["term_aliases", "alias_patches"] {
            let sql = "SELECT legal_term FROM \(table) WHERE colloquial = ? ORDER BY fts_hits DESC"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(edb, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, colloquial, -1, t)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let term = str(stmt, 0)
                if seen.insert(term).inserted { result.append(term) }
            }
        }
        return result
    }

    /// keyword_synonyms: LLM词 → [精确FTS词]
    func synonyms(for keyword: String) -> [String] {
        guard let edb = enhDb else { return [] }
        let sql = "SELECT target_kw FROM keyword_synonyms WHERE source_kw = ? ORDER BY fts_hits DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(edb, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, keyword, -1, t)
        var result: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(str(stmt, 0)) }
        return result
    }

    /// topic_law_hints: keywords → [(priority, lawTitle)]，已按 priority 排序去重
    func topicLawHints(for keywords: [String]) -> [String] {
        guard let edb = enhDb else { return [] }
        var seen = Set<String>()
        var hints: [(Int, String)] = []
        let sql = "SELECT priority, law_title FROM topic_law_hints WHERE topic_keyword = ? ORDER BY priority"
        for kw in keywords {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(edb, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, kw, -1, t)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let priority = Int(sqlite3_column_int(stmt, 0))
                let title = str(stmt, 1)
                if seen.insert(title).inserted { hints.append((priority, title)) }
            }
        }
        return hints.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // MARK: RAG FTS 检索

    struct RAGArticle {
        let nodeId: Int
        let lawId: Int
        let lawTitle: String
        let category: String
        let legalDomain: String
        let articleNumber: String
        let articleNum: Int?
        let content: String
        var pinned: Bool
    }

    /// FTS 检索单个关键词，在指定 legal_domain 和 category 范围内
    func ftsSearch(keyword: String, domains: [String], categories: [String], limit: Int = 10) -> [RAGArticle] {
        guard !keyword.isEmpty, let db = db else { return [] }
        let cjk = keyword.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let domainPH = domains.map { _ in "?" }.joined(separator: ",")
        let catPH    = categories.map { _ in "?" }.joined(separator: ",")

        let sql: String
        let ftsKw: String
        if cjk >= 3 {
            ftsKw = keyword
            sql = """
                SELECT n.id, n.law_id, l.title, l.category, l.legal_domain, n.article_number, n.content, n.article_num
                FROM nodes_fts f
                JOIN nodes n ON f.rowid = n.id
                JOIN laws  l ON n.law_id = l.id
                WHERE nodes_fts MATCH ?
                  AND n.type = 'article' AND l.is_current = 1
                  AND l.legal_domain IN (\(domainPH))
                  AND l.category IN (\(catPH))
                LIMIT ?
                """
        } else if cjk > 0 {
            ftsKw = keyword.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
                        .map { String($0) }.joined(separator: " ")
            sql = """
                SELECT n.id, n.law_id, l.title, l.category, l.legal_domain, n.article_number, n.content, n.article_num
                FROM nodes_fts_bigram f
                JOIN nodes n ON f.rowid = n.id
                JOIN laws  l ON n.law_id = l.id
                WHERE nodes_fts_bigram MATCH ?
                  AND n.type = 'article' AND l.is_current = 1
                  AND l.legal_domain IN (\(domainPH))
                  AND l.category IN (\(catPH))
                LIMIT ?
                """
        } else {
            return []
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var col: Int32 = 1
        sqlite3_bind_text(stmt, col, ftsKw, -1, t); col += 1
        for d in domains { sqlite3_bind_text(stmt, col, d, -1, t); col += 1 }
        for c in categories { sqlite3_bind_text(stmt, col, c, -1, t); col += 1 }
        sqlite3_bind_int(stmt, col, Int32(limit))

        var result: [RAGArticle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(RAGArticle(
                nodeId:        Int(sqlite3_column_int(stmt, 0)),
                lawId:         Int(sqlite3_column_int(stmt, 1)),
                lawTitle:      str(stmt, 2),
                category:      str(stmt, 3),
                legalDomain:   str(stmt, 4),
                articleNumber: str(stmt, 5),
                articleNum:    sqlite3_column_type(stmt, 7) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 7)) : nil,
                content:       str(stmt, 6),
                pinned:        false
            ))
        }
        return result
    }

    /// hint law 检索：在指定法律标题内 FTS 搜索
    func ftsSearchInLaw(keyword: String, lawTitle: String, categories: [String], limit: Int = 10) -> [RAGArticle] {
        guard !keyword.isEmpty, let db = db else { return [] }
        let cjk = keyword.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        guard cjk >= 3 else { return [] }
        let catPH = categories.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT n.id, n.law_id, l.title, l.category, l.legal_domain, n.article_number, n.content, n.article_num
            FROM nodes_fts f
            JOIN nodes n ON f.rowid = n.id
            JOIN laws  l ON n.law_id = l.id
            WHERE nodes_fts MATCH ?
              AND n.type = 'article' AND l.is_current = 1
              AND l.title = ?
              AND l.category IN (\(catPH))
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var col: Int32 = 1
        sqlite3_bind_text(stmt, col, keyword, -1, t); col += 1
        sqlite3_bind_text(stmt, col, lawTitle, -1, t); col += 1
        for c in categories { sqlite3_bind_text(stmt, col, c, -1, t); col += 1 }
        sqlite3_bind_int(stmt, col, Int32(limit))

        var result: [RAGArticle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(RAGArticle(
                nodeId:        Int(sqlite3_column_int(stmt, 0)),
                lawId:         Int(sqlite3_column_int(stmt, 1)),
                lawTitle:      str(stmt, 2),
                category:      str(stmt, 3),
                legalDomain:   str(stmt, 4),
                articleNumber: str(stmt, 5),
                articleNum:    sqlite3_column_type(stmt, 7) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 7)) : nil,
                content:       str(stmt, 6),
                pinned:        true
            ))
        }
        return result
    }

    /// FTS 命中数（用于关键词精确度排序）
    func ftsHitCount(keyword: String) -> Int {
        guard !keyword.isEmpty, let db = db else { return 999 }
        let cjk = keyword.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        guard cjk >= 3 else { return 999 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM nodes_fts WHERE nodes_fts MATCH ?", -1, &stmt, nil) == SQLITE_OK else { return 999 }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, keyword, -1, t)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 999 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: Expert Agent DB helpers

    struct LawStructureNode {
        let id: Int
        let type: String
        let title: String
        let content: String
    }

    func lawId(title: String) -> Int? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT id FROM laws WHERE title = ? AND is_current = 1 LIMIT 1",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, title, -1, t)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(stmt, 0))
    }

    func lawStructure(lawId: Int) -> [LawStructureNode] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT id, type, title, content FROM nodes WHERE law_id = ? AND type IN ('part','chapter','section') ORDER BY global_order",
            -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(lawId))
        var result: [LawStructureNode] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(LawStructureNode(
                id:      Int(sqlite3_column_int(stmt, 0)),
                type:    str(stmt, 1),
                title:   str(stmt, 2),
                content: str(stmt, 3)
            ))
        }
        return result
    }

    func articlesInNode(_ nodeId: Int) -> [RAGArticle] {
        guard let db = db else { return [] }
        // direct articles
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT id, article_number, article_num, content FROM nodes WHERE parent_id = ? AND type = 'article' ORDER BY global_order",
            -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(nodeId))
        var result: [RAGArticle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let nid = Int(sqlite3_column_int(stmt, 0))
            result.append(RAGArticle(
                nodeId: nid, lawId: 0, lawTitle: "", category: "法律", legalDomain: "",
                articleNumber: str(stmt, 1),
                articleNum: sqlite3_column_type(stmt, 2) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 2)) : nil,
                content: str(stmt, 3), pinned: true
            ))
        }
        // recurse into sub-sections
        var sectionStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT id FROM nodes WHERE parent_id = ? AND type = 'section'",
            -1, &sectionStmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(sectionStmt) }
        sqlite3_bind_int(sectionStmt, 1, Int32(nodeId))
        var subIds: [Int] = []
        while sqlite3_step(sectionStmt) == SQLITE_ROW { subIds.append(Int(sqlite3_column_int(sectionStmt, 0))) }
        for subId in subIds { result += articlesInNode(subId) }
        return result
    }

    func articleByRef(lawTitleFragment: String, articleNumber: String) -> RAGArticle? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT n.id, n.law_id, l.title, l.category, l.legal_domain, n.article_number, n.article_num, n.content FROM nodes n JOIN laws l ON n.law_id = l.id WHERE l.title LIKE ? AND n.article_number = ? AND l.is_current = 1 LIMIT 1",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "%\(lawTitleFragment)%", -1, t)
        sqlite3_bind_text(stmt, 2, articleNumber, -1, t)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return RAGArticle(
            nodeId: Int(sqlite3_column_int(stmt, 0)),
            lawId:  Int(sqlite3_column_int(stmt, 1)),
            lawTitle: str(stmt, 2), category: str(stmt, 3), legalDomain: str(stmt, 4),
            articleNumber: str(stmt, 5),
            articleNum: sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 6)) : nil,
            content: str(stmt, 7), pinned: false
        )
    }

    // MARK: 工具

    private func str(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cstr)
    }
}
