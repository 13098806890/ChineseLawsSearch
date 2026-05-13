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
    let aliases: [String]    // 法律别名，如 ["民诉法", "民事诉讼法"]
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

struct GongbaoDoc: Identifiable {
    let id: Int
    let source: String      // "cpwsxd" | "al" | "sfwj"
    let caseNumber: String  // 仅 al 有
    let title: String
    let issue: String
    let year: Int
    let pubDate: String
    let url: String
    let rulingGist: String
    let keywords: String
    let fullText: String
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

    /// 所有 SQLite 操作必须在此队列上执行，保证线程安全。
    private let queue = DispatchQueue(label: "com.lushu.dbqueue", qos: .userInitiated)

    private init() {
        db    = DatabaseManager.openDB(resource: "law_content",     ext: "db")
        enhDb = DatabaseManager.openDB(resource: "law_enhancements", ext: "db")
    }

    private static func openDB(resource: String, ext: String) -> OpaquePointer? {
        guard let bundleURL = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("DatabaseManager: 找不到 \(resource).\(ext)")
            return nil
        }
        // Try opening directly from bundle first (works when DB is in delete/journal mode)
        var ptr: OpaquePointer?
        if sqlite3_open_v2(bundleURL.path, &ptr, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            return ptr
        }
        // Bundle open failed (e.g. WAL mode needs writable dir) — copy to Documents and retry
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docs.appendingPathComponent("\(resource).\(ext)")
        do {
            if fm.fileExists(atPath: destURL.path) {
                let bundleSize = (try? fm.attributesOfItem(atPath: bundleURL.path)[.size] as? Int) ?? 0
                let destSize   = (try? fm.attributesOfItem(atPath: destURL.path)[.size]   as? Int) ?? 0
                if bundleSize != destSize { try fm.removeItem(at: destURL) }
            }
            if !fm.fileExists(atPath: destURL.path) {
                try fm.copyItem(at: bundleURL, to: destURL)
            }
        } catch {
            print("DatabaseManager: 复制 \(resource).\(ext) 失败：\(error)")
            return nil
        }
        if sqlite3_open_v2(destURL.path, &ptr, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            print("DatabaseManager: 无法打开 \(resource).\(ext)")
            return nil
        }
        return ptr
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

    func loadFlkMenu() -> LawMenu? { loadMenuResource("flk_menu") }

    func loadMenu() -> LawMenu? { loadMenuResource("law_menu") }

    private func loadMenuResource(_ name: String) -> LawMenu? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
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
        queue.sync { _nodes(lawId: lawId) }
    }

    private func _nodes(lawId: Int) -> [LawNode] {
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
        queue.sync { _lawMeta(id: id) }
    }

    private func _lawMeta(id: Int) -> LawMeta? {
        let sql = """
            SELECT id, title, category, legal_domain, pub_date, effective_date,
                   issuing_org, doc_number, total_articles,
                   COALESCE(subject_area, '') AS subject_area,
                   COALESCE(aliases, '') AS aliases
            FROM laws
            WHERE id = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(id))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let aliasStr = str(stmt, 10)
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
            subjectArea:   str(stmt, 9),
            aliases:       aliasStr.isEmpty ? [] : aliasStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    // MARK: 某部法律的全部出向引用（按条文分组用）

    func outgoingRefsForLaw(lawId: Int, flkOnly: Bool = false) -> [OutgoingRef] {
        queue.sync { _outgoingRefsForLaw(lawId: lawId, flkOnly: flkOnly) }
    }

    private func _outgoingRefsForLaw(lawId: Int, flkOnly: Bool) -> [OutgoingRef] {
        let flkFilter = flkOnly ? "AND l.is_flk = 1" : ""
        let sql = """
            SELECT ar.id, ar.from_article_num, ar.raw_text, ar.to_law_id, l.title, ar.to_article_num
            FROM article_references ar
            JOIN laws l ON ar.to_law_id = l.id
            WHERE ar.from_law_id = ?
              AND ar.resolved = 1 AND ar.to_article_num IS NOT NULL
              \(flkFilter)
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

    func incomingRefsForLaw(lawId: Int, flkOnly: Bool = false) -> [IncomingRef] {
        queue.sync { _incomingRefsForLaw(lawId: lawId, flkOnly: flkOnly) }
    }

    private func _incomingRefsForLaw(lawId: Int, flkOnly: Bool) -> [IncomingRef] {
        let flkFilter = flkOnly ? "AND l.is_flk = 1" : ""
        let sql = """
            SELECT ar.id, ar.to_article_num, ar.from_law_id, l.title, ar.from_article_num, n.article_number
            FROM article_references ar
            JOIN laws l ON ar.from_law_id = l.id
            JOIN nodes n ON ar.from_node_id = n.id
            WHERE ar.to_law_id = ?
              AND ar.resolved = 1 AND ar.ref_type = 'cross_law'
              \(flkFilter)
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

    nonisolated func searchByTitle(query: String, limit: Int = 50, categories: [String] = [], flkOnly: Bool = false) -> [LawMeta] {
        queue.sync { _searchByTitle(query: query, limit: limit, categories: categories, flkOnly: flkOnly) }
    }

    private func _searchByTitle(query: String, limit: Int = 50, categories: [String] = [], flkOnly: Bool = false) -> [LawMeta] {
        let catFilter = categories.isEmpty ? "" : "AND category IN (\(categories.map { _ in "?" }.joined(separator: ",")))"
        let flkFilter = flkOnly ? "AND is_flk = 1" : ""
        let sql = """
            SELECT id, title, category, legal_domain, pub_date, effective_date,
                   issuing_org, doc_number, total_articles,
                   COALESCE(subject_area, '') AS subject_area,
                   COALESCE(aliases, '') AS aliases
            FROM laws
            WHERE is_current = 1 AND (title LIKE ? OR aliases LIKE ?) \(catFilter) \(flkFilter)
            ORDER BY title
            LIMIT ?
            """
        var stmt: OpaquePointer?
        var result: [LawMeta] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var col: Int32 = 1
        sqlite3_bind_text(stmt, col, "%\(query)%", -1, transient); col += 1
        sqlite3_bind_text(stmt, col, "%\(query)%", -1, transient); col += 1
        for cat in categories { sqlite3_bind_text(stmt, col, cat, -1, transient); col += 1 }
        sqlite3_bind_int(stmt, col, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let aliasStr = str(stmt, 10)
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
                subjectArea:   str(stmt, 9),
                aliases:       aliasStr.isEmpty ? [] : aliasStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ))
        }
        return result
    }

    // MARK: 条文内容搜索（自动选择索引）
    // 1-2字走 bigram FTS，3字以上走 trigram FTS，均为毫秒级
    // excludeArticleNumber: 屏蔽条号前缀匹配（3字以上走 content_body 列，短词在 Swift 过滤）

    nonisolated func searchContent(query: String, limit: Int = 100,
                       excludeArticleNumber: Bool = false,
                       categories: [String] = [],
                       flkOnly: Bool = false) -> [SearchResult] {
        queue.sync { _searchContent(query: query, limit: limit,
                                    excludeArticleNumber: excludeArticleNumber,
                                    categories: categories,
                                    flkOnly: flkOnly) }
    }

    private func _searchContent(query: String, limit: Int = 100,
                       excludeArticleNumber: Bool = false,
                       categories: [String] = [],
                       flkOnly: Bool = false) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let cjkChars = query.unicodeScalars.filter {
            $0.value >= 0x4E00 && $0.value <= 0x9FFF
        }
        let useLike = cjkChars.count < 3   // 短词用 LIKE，避免 bigram 单字拆开无结果

        let catFilter = categories.isEmpty ? "" : "AND l.category IN (\(categories.map { _ in "?" }.joined(separator: ",")))"
        let flkFilter = flkOnly ? "AND l.is_flk = 1" : ""
        let sql: String
        let ftsQuery: String

        if useLike {
            // 短词（1-2字）：LIKE '%keyword%' 全扫，准确可靠
            let col = excludeArticleNumber ? "n.content" : "(n.article_number || n.content)"
            sql = """
                SELECT n.id, n.law_id, l.title, n.article_number, n.content, n.article_num
                FROM nodes n
                JOIN laws l ON n.law_id = l.id
                WHERE \(col) LIKE ? AND n.type = 'article' AND l.is_current = 1 \(catFilter) \(flkFilter)
                LIMIT ?
                """
            ftsQuery = "%\(query)%"
        } else {
            ftsQuery = query
            // 屏蔽条号时搜 content_body 列，否则搜全文
            let col = excludeArticleNumber ? "content_body" : "nodes_fts"
            sql = """
                SELECT n.id, n.law_id, l.title, n.article_number, n.content, n.article_num
                FROM nodes_fts f
                JOIN nodes n ON f.rowid = n.id
                JOIN laws  l ON n.law_id = l.id
                WHERE \(col) MATCH ? AND n.type = 'article' AND l.is_current = 1 \(catFilter) \(flkFilter)
                LIMIT ?
                """
        }

        var stmt: OpaquePointer?
        var result: [SearchResult] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var bindCol: Int32 = 1
        sqlite3_bind_text(stmt, bindCol, ftsQuery, -1, transient); bindCol += 1
        for cat in categories { sqlite3_bind_text(stmt, bindCol, cat, -1, transient); bindCol += 1 }
        sqlite3_bind_int(stmt, bindCol, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let content = str(stmt, 4)
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

    private static let arabicRegex   = try! NSRegularExpression(pattern: #"[0-9]+"#)
    private static let chineseRegex  = try! NSRegularExpression(pattern: "[零一二三四五六七八九十百千万]+")

    private static func arabicToChinese(_ s: String) -> String {
        var result = s
        var offset = 0
        for match in arabicRegex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
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
        var result = s
        var offset = 0
        for match in chineseRegex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
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
        queue.sync { _legalTerms(for: colloquial) }
    }

    private func _legalTerms(for colloquial: String) -> [String] {
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
        queue.sync { _synonyms(for: keyword) }
    }

    private func _synonyms(for keyword: String) -> [String] {
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
        queue.sync { _topicLawHints(for: keywords) }
    }

    private func _topicLawHints(for keywords: [String]) -> [String] {
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
        queue.sync { _ftsSearch(keyword: keyword, domains: domains, categories: categories, limit: limit) }
    }

    private func _ftsSearch(keyword: String, domains: [String], categories: [String], limit: Int = 10) -> [RAGArticle] {
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
        queue.sync { _ftsSearchInLaw(keyword: keyword, lawTitle: lawTitle, categories: categories, limit: limit) }
    }

    private func _ftsSearchInLaw(keyword: String, lawTitle: String, categories: [String], limit: Int = 10) -> [RAGArticle] {
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
        queue.sync { _ftsHitCount(keyword: keyword) }
    }

    private func _ftsHitCount(keyword: String) -> Int {
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
        queue.sync { _lawId(title: title) }
    }

    private func _lawId(title: String) -> Int? {
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
        queue.sync { _lawStructure(lawId: lawId) }
    }

    private func _lawStructure(lawId: Int) -> [LawStructureNode] {
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
        queue.sync { _articlesInNode(nodeId, depth: 0) }
    }

    private func _articlesInNode(_ nodeId: Int, depth: Int) -> [RAGArticle] {
        guard depth < 4 else { return [] }  // guard against malformed data cycles
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
        for subId in subIds { result += _articlesInNode(subId, depth: depth + 1) }
        return result
    }

    func articleByRef(lawTitleFragment: String, articleNumber: String) -> RAGArticle? {
        queue.sync { _articleByRef(lawTitleFragment: lawTitleFragment, articleNumber: articleNumber) }
    }

    private func _articleByRef(lawTitleFragment: String, articleNumber: String) -> RAGArticle? {
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

    /// Lookup articles by article_number within a set of law_ids (or all current laws if empty).
    /// lawTitleFragment: optional partial law title for narrowing (e.g. "民法典").
    func articlesByNumber(articleNumber: String,
                          lawTitleFragment: String? = nil,
                          lawIds: [Int] = []) -> [RAGArticle] {
        queue.sync { _articlesByNumber(articleNumber: articleNumber, lawTitleFragment: lawTitleFragment, lawIds: lawIds) }
    }

    private func _articlesByNumber(articleNumber: String,
                                   lawTitleFragment: String? = nil,
                                   lawIds: [Int] = []) -> [RAGArticle] {
        guard let db = db else { return [] }
        // lawIds: integer values only — safe to inline (no user input)
        let idsPart = lawIds.isEmpty ? "" : " AND n.law_id IN (\(lawIds.map { String($0) }.joined(separator: ",")))"
        // lawTitleFragment comes from LLM output — use parameter binding to prevent SQL injection
        let titlePart = (lawTitleFragment?.isEmpty == false) ? " AND l.title LIKE ?" : ""
        let sql = """
            SELECT n.id, n.law_id, l.title, l.category, l.legal_domain,
                   n.article_number, n.article_num, n.content
            FROM nodes n JOIN laws l ON n.law_id = l.id
            WHERE n.article_number = ? AND n.type = 'article' AND l.is_current = 1
            \(idsPart)\(titlePart)
            LIMIT 10
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, articleNumber, -1, t)
        if let frag = lawTitleFragment, !frag.isEmpty {
            sqlite3_bind_text(stmt, 2, "%\(frag)%", -1, t)
        }
        var result: [RAGArticle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(RAGArticle(
                nodeId: Int(sqlite3_column_int(stmt, 0)),
                lawId:  Int(sqlite3_column_int(stmt, 1)),
                lawTitle: str(stmt, 2), category: str(stmt, 3), legalDomain: str(stmt, 4),
                articleNumber: str(stmt, 5),
                articleNum: sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 6)) : nil,
                content: str(stmt, 7), pinned: false
            ))
        }
        return result
    }

    // MARK: 双向引用扩展

    /// 给定一批 nodeId，返回它们通过 article_references 引用或被引用的所有条文（双向），
    /// 排除已在 seenIds 中的节点。
    func referencedArticles(nodeIds: [Int], excludingIds: Set<Int>) -> [RAGArticle] {
        queue.sync { _referencedArticles(nodeIds: nodeIds, excludingIds: excludingIds) }
    }

    private func _referencedArticles(nodeIds: [Int], excludingIds: Set<Int>) -> [RAGArticle] {
        guard let db = db, !nodeIds.isEmpty else { return [] }
        let idList = nodeIds.map { String($0) }.joined(separator: ",")
        // 出向引用：当前条文 → 被引用条文（to_node_id 有值）
        // 入向引用：引用当前条文的其他条文（from_node_id）
        let sql = """
            SELECT DISTINCT n.id, n.law_id, l.title, l.category, l.legal_domain,
                   n.article_number, n.article_num, n.content
            FROM article_references ar
            JOIN nodes n ON (
                (ar.from_node_id IN (\(idList)) AND n.id = ar.to_node_id)
                OR
                (ar.to_node_id IN (\(idList)) AND n.id = ar.from_node_id)
            )
            JOIN laws l ON n.law_id = l.id
            WHERE ar.resolved = 1
              AND n.type = 'article'
              AND l.is_current = 1
            LIMIT 30
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [RAGArticle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let nodeId = Int(sqlite3_column_int(stmt, 0))
            guard !excludingIds.contains(nodeId) else { continue }
            result.append(RAGArticle(
                nodeId: nodeId,
                lawId:  Int(sqlite3_column_int(stmt, 1)),
                lawTitle: str(stmt, 2), category: str(stmt, 3), legalDomain: str(stmt, 4),
                articleNumber: str(stmt, 5),
                articleNum: sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 6)) : nil,
                content: str(stmt, 7), pinned: false
            ))
        }
        return result
    }

    // MARK: - 公报查询

    func gongbaoDocs(source: String?, query: String, limit: Int = 100) -> [GongbaoDoc] {
        queue.sync { _gongbaoDocs(source: source, query: query, limit: limit) }
    }

    private func _gongbaoDocs(source: String?, query: String, limit: Int) -> [GongbaoDoc] {
        guard let db = db else { return [] }
        var docs: [GongbaoDoc] = []

        if query.trimmingCharacters(in: .whitespaces).count >= 2 {
            // FTS 搜索
            let ftsQuery = query.trimmingCharacters(in: .whitespaces)
            var sourceClause = ""
            if let source = source {
                sourceClause = "AND d.source = '\(source)'"
            }
            let sql = """
                SELECT d.id, d.source, COALESCE(d.case_number,''), d.title,
                       COALESCE(d.issue,''), COALESCE(d.year,0),
                       COALESCE(d.pub_date,''), COALESCE(d.url,''),
                       COALESCE(d.ruling_gist,''), COALESCE(d.keywords,''),
                       COALESCE(d.full_text,'')
                FROM gongbao_docs_fts f
                JOIN gongbao_docs d ON f.rowid = d.id
                WHERE gongbao_docs_fts MATCH ?
                \(sourceClause)
                ORDER BY d.year DESC, d.issue_num DESC
                LIMIT \(limit)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                docs.append(GongbaoDoc(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    source: str(stmt, 1),
                    caseNumber: str(stmt, 2),
                    title: str(stmt, 3),
                    issue: str(stmt, 4),
                    year: Int(sqlite3_column_int(stmt, 5)),
                    pubDate: str(stmt, 6),
                    url: str(stmt, 7),
                    rulingGist: str(stmt, 8),
                    keywords: str(stmt, 9),
                    fullText: str(stmt, 10)
                ))
            }
        } else {
            // 无关键词，按 source 过滤浏览
            var whereParts: [String] = []
            if let source = source { whereParts.append("source = '\(source)'") }
            let whereClause = whereParts.isEmpty ? "" : "WHERE \(whereParts.joined(separator: " AND "))"
            let sql = """
                SELECT id, source, COALESCE(case_number,''), title,
                       COALESCE(issue,''), COALESCE(year,0),
                       COALESCE(pub_date,''), COALESCE(url,''),
                       COALESCE(ruling_gist,''), COALESCE(keywords,''),
                       COALESCE(full_text,'')
                FROM gongbao_docs
                \(whereClause)
                ORDER BY year DESC, issue_num DESC
                LIMIT \(limit)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                docs.append(GongbaoDoc(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    source: str(stmt, 1),
                    caseNumber: str(stmt, 2),
                    title: str(stmt, 3),
                    issue: str(stmt, 4),
                    year: Int(sqlite3_column_int(stmt, 5)),
                    pubDate: str(stmt, 6),
                    url: str(stmt, 7),
                    rulingGist: str(stmt, 8),
                    keywords: str(stmt, 9),
                    fullText: str(stmt, 10)
                ))
            }
        }
        return docs
    }

    // MARK: 工具

    private func str(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cstr)
    }
}
