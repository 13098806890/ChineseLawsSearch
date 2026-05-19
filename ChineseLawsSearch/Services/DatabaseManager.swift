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
    /// "flk"（主库）或 "gongbao"（最高人民法院公报）
    var source: String = "flk"
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
    let lawCategory: String
    let articleNumber: String
    let content: String
    let nodeArticleNum: Int?
    /// "flk" or "gongbao"
    var source: String = "flk"
}

struct GazetteDoc: Identifiable {
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
    /// 结构化关键词，key = 维度名，value = 该维度的词列表
    /// 例：["法律类型": ["民事"], "审级": ["二审"], "地区": ["浙江省"], ...]
    let keywordsMeta: [String: [String]]
    let fullText: String
    /// 结构化案情概括，key = 维度名（legal_relationship/parties/core_dispute/key_facts/
    /// special_circumstances/outcome/region/dispute_amount/procedure_stage）
    let caseBrief: [String: String]
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

// 某条文被公报案例引用的统计
struct GazetteRef: Identifiable {
    let id: Int          // article_num (用作 map key)
    let articleNum: Int
    let count: Int       // 引用该条文的公报案例数量
}

struct GazetteDocLink: Identifiable {
    let id: Int          // doc_id (negative for sfjs)
    let title: String
    let isSfjs: Bool
    let sfjsArticleNum: Int?  // sfjs 中的具体条文序号（可为 nil）
}

struct GazetteSfjsArticle: Identifiable {
    let id: Int
    let sfjsId: Int
    let articleNum: Int
    let articleNumber: String
    let content: String
    let globalOrder: Int
}

struct GazetteSfjs: Identifiable, Hashable {
    let id: Int
    let title: String
    let docNumber: String
    let pubDate: String
    let effectiveDate: String
    let url: String
    let fullText: String
}

final class DatabaseManager {
    nonisolated(unsafe) static let shared = DatabaseManager()

    nonisolated(unsafe) private var db: OpaquePointer?
    nonisolated(unsafe) private var enhDb: OpaquePointer?

    /// 所有 SQLite 操作必须在此队列上执行，保证线程安全。
    // TODO: upgrade to concurrent queue with barrier writes for better read throughput
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
                // Force re-copy if: sizes differ, bundle is newer, or key tables are missing
                let bundleAttrs = try? fm.attributesOfItem(atPath: bundleURL.path)
                let destAttrs   = try? fm.attributesOfItem(atPath: destURL.path)
                let bundleMod   = bundleAttrs?[.modificationDate] as? Date ?? .distantPast
                let destMod     = destAttrs?[.modificationDate]   as? Date ?? .distantPast
                let bundleSize  = bundleAttrs?[.size] as? Int ?? 0
                let destSize    = destAttrs?[.size]   as? Int ?? 0
                var needsCopy   = bundleSize != destSize || bundleMod > destMod
                // Definitive check: compare user_version (YYYYMMDD) between bundle and Documents db
                if !needsCopy && resource == "law_content" {
                    let bundleVersion = DatabaseManager.readUserVersion(bundleURL.path)
                    let destVersion   = DatabaseManager.readUserVersion(destURL.path)
                    if bundleVersion > 0 && bundleVersion != destVersion {
                        needsCopy = true
                    } else if destVersion == 0 {
                        // Fallback: check required tables
                        var checkPtr: OpaquePointer?
                        if sqlite3_open_v2(destURL.path, &checkPtr, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                            let requiredTables = ["gongbao_docs", "gongbao_case_law_links"]
                            for tbl in requiredTables {
                                var checkStmt: OpaquePointer?
                                let checkSQL = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='\(tbl)'"
                                if sqlite3_prepare_v2(checkPtr, checkSQL, -1, &checkStmt, nil) == SQLITE_OK {
                                    if sqlite3_step(checkStmt) == SQLITE_ROW && sqlite3_column_int(checkStmt, 0) == 0 {
                                        needsCopy = true
                                    }
                                    sqlite3_finalize(checkStmt)
                                }
                                if needsCopy { break }
                            }
                            sqlite3_close(checkPtr)
                        }
                    }
                }
                if needsCopy { try fm.removeItem(at: destURL) }
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

    private static func readUserVersion(_ path: String) -> Int32 {
        var ptr: OpaquePointer?
        guard sqlite3_open_v2(path, &ptr, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(ptr) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(ptr, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : 0
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

    func loadLawsExamMenu() -> LawMenu? { loadMenuResource("flk_menu") }

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
                   COALESCE(aliases, '') AS aliases,
                   COALESCE(source, 'flk') AS source
            FROM laws
            WHERE id = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(id))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let aliasStr = str(stmt, 10)
        var meta = LawMeta(
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
        meta.source = str(stmt, 11)
        return meta
    }

    // MARK: 某部法律的全部出向引用（按条文分组用）

    nonisolated func outgoingRefsForLaw(lawId: Int, lawsExamOnly: Bool = false) -> [OutgoingRef] {
        queue.sync { _outgoingRefsForLaw(lawId: lawId, lawsExamOnly: lawsExamOnly) }
    }

    private func _outgoingRefsForLaw(lawId: Int, lawsExamOnly: Bool) -> [OutgoingRef] {
        let lawsExamFilter = lawsExamOnly ? "AND l.is_flk = 1" : ""
        let sql = """
            SELECT ar.id, ar.from_article_num, ar.raw_text, ar.to_law_id, l.title, ar.to_article_num
            FROM article_references ar
            JOIN laws l ON ar.to_law_id = l.id
            WHERE ar.from_law_id = ?
              AND ar.resolved = 1 AND ar.to_article_num IS NOT NULL
              \(lawsExamFilter)
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

    nonisolated func incomingRefsForLaw(lawId: Int, lawsExamOnly: Bool = false) -> [IncomingRef] {
        queue.sync { _incomingRefsForLaw(lawId: lawId, lawsExamOnly: lawsExamOnly) }
    }

    /// 查询某部法律中被公报案例引用的条文，按 article_num 分组返回引用数量
    func gazetteRefsForLaw(lawId: Int) -> [GazetteRef] {
        queue.sync {
            guard let db = db else { return [] }
            let sql = """
                SELECT article_num, COUNT(DISTINCT doc_id) as cnt
                FROM gongbao_case_law_links
                WHERE law_id = ? AND article_num > 0
                GROUP BY article_num
                """
            var stmt: OpaquePointer?
            var result: [GazetteRef] = []
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(lawId))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let artNum = Int(sqlite3_column_int(stmt, 0))
                let cnt    = Int(sqlite3_column_int(stmt, 1))
                result.append(GazetteRef(id: artNum, articleNum: artNum, count: cnt))
            }
            return result
        }
    }

    /// articleNum → [GazetteDocLink]，用于法条视图内跳转公报
    nonisolated func gazetteLinksForLaw(lawId: Int) -> [Int: [GazetteDocLink]] {
        queue.sync {
            guard let db = db else { return [:] }
            let sql = """
                SELECT l.article_num, d.id, d.title
                FROM gongbao_case_law_links l
                JOIN gongbao_docs d ON d.id = l.doc_id
                WHERE l.law_id = ? AND l.article_num > 0
                ORDER BY l.article_num, d.title
                """
            var stmt: OpaquePointer?
            var result: [Int: [GazetteDocLink]] = [:]
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(lawId))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let artNum = Int(sqlite3_column_int(stmt, 0))
                let docId  = Int(sqlite3_column_int(stmt, 1))
                let title  = str(stmt, 2)
                result[artNum, default: []].append(GazetteDocLink(id: docId, title: title, isSfjs: false, sfjsArticleNum: nil))
            }
            return result
        }
    }

    private func _incomingRefsForLaw(lawId: Int, lawsExamOnly: Bool) -> [IncomingRef] {
        let lawsExamFilter = lawsExamOnly ? "AND l.is_flk = 1" : ""
        let sql = """
            SELECT ar.id, ar.to_article_num, ar.from_law_id, l.title, ar.from_article_num, n.article_number
            FROM article_references ar
            JOIN laws l ON ar.from_law_id = l.id
            JOIN nodes n ON ar.from_node_id = n.id
            WHERE ar.to_law_id = ?
              AND ar.resolved = 1 AND ar.ref_type = 'cross_law'
              \(lawsExamFilter)
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

    nonisolated func searchByTitle(query: String, limit: Int = 50, categories: [String] = [], lawsExamOnly: Bool = false) -> [LawMeta] {
        queue.sync { _searchByTitle(query: query, limit: limit, categories: categories, lawsExamOnly: lawsExamOnly) }
    }

    private nonisolated func _searchByTitle(query: String, limit: Int = 50, categories: [String] = [], lawsExamOnly: Bool = false) -> [LawMeta] {
        let catFilter = categories.isEmpty ? "" : "AND category IN (\(categories.map { _ in "?" }.joined(separator: ",")))"
        let lawsExamFilter = lawsExamOnly ? "AND is_flk = 1" : ""
        let sql = """
            SELECT id, title, category, legal_domain, pub_date, effective_date,
                   issuing_org, doc_number, total_articles,
                   COALESCE(subject_area, '') AS subject_area,
                   COALESCE(aliases, '') AS aliases,
                   COALESCE(source, 'flk') AS source
            FROM laws
            WHERE is_current = 1 AND (title LIKE ? OR aliases LIKE ?) \(catFilter) \(lawsExamFilter)
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
            var meta = LawMeta(
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
            meta.source = str(stmt, 11)
            result.append(meta)
        }

        return result
    }

    // MARK: 条文内容搜索（自动选择索引）
    // 1-2字走 bigram FTS，3字以上走 trigram FTS，均为毫秒级
    // excludeArticleNumber: 屏蔽条号前缀匹配（3字以上走 content_body 列，短词在 Swift 过滤）

    nonisolated func searchContent(query: String, limit: Int = 100,
                       excludeArticleNumber: Bool = false,
                       categories: [String] = [],
                       lawsExamOnly: Bool = false) -> [SearchResult] {
        queue.sync { _searchContent(query: query, limit: limit,
                                    excludeArticleNumber: excludeArticleNumber,
                                    categories: categories,
                                    lawsExamOnly: lawsExamOnly) }
    }

    private nonisolated func _searchContent(query: String, limit: Int = 100,
                       excludeArticleNumber: Bool = false,
                       categories: [String] = [],
                       lawsExamOnly: Bool = false) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let cjkChars = query.unicodeScalars.filter {
            $0.value >= 0x4E00 && $0.value <= 0x9FFF
        }
        let useLike = cjkChars.count < 3   // 短词用 LIKE，避免 bigram 单字拆开无结果

        let catFilter = categories.isEmpty ? "" : "AND l.category IN (\(categories.map { _ in "?" }.joined(separator: ",")))"
        let lawsExamFilter = lawsExamOnly ? "AND l.is_flk = 1" : ""
        let sql: String
        let ftsQuery: String

        if useLike {
            // 短词（1-2字）：LIKE '%keyword%' 全扫，准确可靠
            let col = excludeArticleNumber ? "n.content" : "(n.article_number || n.content)"
            sql = """
                SELECT n.id, n.law_id, l.title, l.category, n.article_number, n.content, n.article_num
                FROM nodes n
                JOIN laws l ON n.law_id = l.id
                WHERE \(col) LIKE ? AND n.type = 'article' AND l.is_current = 1 \(catFilter) \(lawsExamFilter)
                LIMIT ?
                """
            ftsQuery = "%\(query)%"
        } else {
            ftsQuery = query
            // 屏蔽条号时搜 content_body 列，否则搜全文
            let col = excludeArticleNumber ? "content_body" : "nodes_fts"
            sql = """
                SELECT n.id, n.law_id, l.title, l.category, n.article_number, n.content, n.article_num
                FROM nodes_fts f
                JOIN nodes n ON f.rowid = n.id
                JOIN laws  l ON n.law_id = l.id
                WHERE \(col) MATCH ? AND n.type = 'article' AND l.is_current = 1 \(catFilter) \(lawsExamFilter)
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
            let content = str(stmt, 5)
            let artNumCol = sqlite3_column_type(stmt, 6)
            let artNum: Int? = artNumCol == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6))
            result.append(SearchResult(
                id:             Int(sqlite3_column_int(stmt, 0)),
                lawId:          Int(sqlite3_column_int(stmt, 1)),
                lawTitle:       str(stmt, 2),
                lawCategory:    str(stmt, 3),
                articleNumber:  str(stmt, 4),
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

    /// Converts "第5条" → "第五条", leaves "第五条" unchanged.
    private nonisolated static func arabicToChineseArticleNumber(_ s: String) -> String {
        guard let m = s.range(of: #"第(\d+)条"#, options: .regularExpression) else { return s }
        let numStr = s[m].dropFirst(1).dropLast(1) // strip 第…条
        guard let n = Int(numStr) else { return s }
        return "第\(intToChinese(n))条"
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
    nonisolated func ftsSearch(keyword: String, domains: [String], categories: [String], limit: Int = 10) -> [RAGArticle] {
        queue.sync { _ftsSearch(keyword: keyword, domains: domains, categories: categories, limit: limit) }
    }

    private nonisolated func _ftsSearch(keyword: String, domains: [String], categories: [String], limit: Int = 10) -> [RAGArticle] {
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
    nonisolated func ftsSearchInLaw(keyword: String, lawTitle: String, categories: [String], limit: Int = 10) -> [RAGArticle] {
        queue.sync { _ftsSearchInLaw(keyword: keyword, lawTitle: lawTitle, categories: categories, limit: limit) }
    }

    private nonisolated func _ftsSearchInLaw(keyword: String, lawTitle: String, categories: [String], limit: Int = 10) -> [RAGArticle] {
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

    /// Normalize a law title fragment from LLM output to match DB storage conventions.
    /// DB stores fullwidth parens as halfwidth: （一）→ (一)
    private nonisolated static func normalizeLawTitle(_ s: String) -> String {
        s.replacingOccurrences(of: "〈", with: "《")
         .replacingOccurrences(of: "〉", with: "》")
         .replacingOccurrences(of: "（", with: "(")
         .replacingOccurrences(of: "）", with: ")")
    }

    nonisolated func lawId(title: String) -> Int? {
        queue.sync { _lawId(title: Self.normalizeLawTitle(title)) }
    }

    /// Fuzzy law ID lookup for linking bare 《法律名》 spans (LLM may omit words like 案件/若干).
    /// Tries: exact → substring LIKE → 2-char token AND match.
    nonisolated func lawId(titleFragment: String) -> Int? {
        queue.sync { _lawIdFuzzy(titleFragment: Self.normalizeLawTitle(titleFragment)) }
    }

    private nonisolated func _lawIdFuzzy(titleFragment: String) -> Int? {
        if let id = _lawId(title: titleFragment) { return id }
        guard let db = db else { return nil }
        if let id = _lawIdLike(db: db, fragment: titleFragment) { return id }
        let tokens = Self.titleTokens(titleFragment)
        guard tokens.count >= 2 else { return nil }
        return _lawIdTokenAnd(db: db, tokens: tokens)
    }

    private nonisolated func _lawIdLike(db: OpaquePointer, fragment: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT id FROM laws WHERE (title LIKE ? OR ? LIKE '%' || title || '%') AND is_current = 1 ORDER BY length(title) DESC LIMIT 1",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "%\(fragment)%", -1, t)
        sqlite3_bind_text(stmt, 2, fragment, -1, t)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private nonisolated func _lawIdTokenAnd(db: OpaquePointer, tokens: [String]) -> Int? {
        let conditions = tokens.map { _ in "title LIKE ?" }.joined(separator: " AND ")
        let sql = "SELECT id FROM laws WHERE (\(conditions)) AND is_current = 1 ORDER BY length(title) DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, tok) in tokens.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), "%\(tok)%", -1, t)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Split normalized title into 2-char CJK windows + optional (X) suffix for AND matching.
    private nonisolated static func titleTokens(_ title: String) -> [String] {
        let chars = Array(title.unicodeScalars)
        var tokens: [String] = []
        var seen = Set<String>()
        var i = 0
        while i + 1 < chars.count {
            let window = chars[i..<(i+2)]
            if window.allSatisfy({ $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
                let s = String(String.UnicodeScalarView(window))
                if seen.insert(s).inserted { tokens.append(s) }
            }
            i += 2
        }
        // Include (X) suffix to disambiguate numbered versions e.g. (一)/(二)
        if let m = title.range(of: #"\([^)]+\)$"#, options: .regularExpression) {
            let suffix = String(title[m])
            if seen.insert(suffix).inserted { tokens.append(suffix) }
        }
        return tokens
    }

    private nonisolated func _lawId(title: String) -> Int? {
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

    nonisolated func lawStructure(lawId: Int) -> [LawStructureNode] {
        queue.sync { _lawStructure(lawId: lawId) }
    }

    private nonisolated func _lawStructure(lawId: Int) -> [LawStructureNode] {
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

    nonisolated func articlesInNode(_ nodeId: Int) -> [RAGArticle] {
        queue.sync { _articlesInNode(nodeId, depth: 0) }
    }

    private nonisolated func _articlesInNode(_ nodeId: Int, depth: Int) -> [RAGArticle] {
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

    nonisolated func articleByRef(lawTitleFragment: String, articleNumber: String) -> RAGArticle? {
        queue.sync { _articleByRef(lawTitleFragment: lawTitleFragment, articleNumber: articleNumber) }
    }

    private nonisolated func _articleByRef(lawTitleFragment: String, articleNumber: String) -> RAGArticle? {
        guard let db = db else { return nil }
        let normalizedFrag = Self.normalizeLawTitle(lawTitleFragment)
        let normalizedArtNum = Self.arabicToChineseArticleNumber(articleNumber)
        // Pass 1: substring LIKE match
        if let r = _articleByRefLike(db: db, fragment: "%\(normalizedFrag)%", artNum: normalizedArtNum) { return r }
        // Pass 2: token-split AND match (handles LLM omitting words like 案件/若干)
        let tokens = Self.titleTokens(normalizedFrag)
        guard tokens.count >= 2 else { return nil }
        return _articleByRefTokenAnd(db: db, tokens: tokens, artNum: normalizedArtNum)
    }

    private nonisolated func _articleByRefLike(db: OpaquePointer, fragment: String, artNum: String) -> RAGArticle? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT n.id, n.law_id, l.title, l.category, l.legal_domain, n.article_number, n.article_num, n.content FROM nodes n JOIN laws l ON n.law_id = l.id WHERE l.title LIKE ? AND n.article_number = ? AND l.is_current = 1 LIMIT 1",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, fragment, -1, t)
        sqlite3_bind_text(stmt, 2, artNum, -1, t)
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

    private nonisolated func _articleByRefTokenAnd(db: OpaquePointer, tokens: [String], artNum: String) -> RAGArticle? {
        let conditions = tokens.map { _ in "l.title LIKE ?" }.joined(separator: " AND ")
        let sql = "SELECT n.id, n.law_id, l.title, l.category, l.legal_domain, n.article_number, n.article_num, n.content FROM nodes n JOIN laws l ON n.law_id = l.id WHERE (\(conditions)) AND n.article_number = ? AND l.is_current = 1 LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, tok) in tokens.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), "%\(tok)%", -1, t)
        }
        sqlite3_bind_text(stmt, Int32(tokens.count + 1), artNum, -1, t)
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

    // MARK: 条文目录（用于 Round 0 Pull 模式）

    /// 法律章节目录条目，用于大型法典的两阶段选条（Phase A：选章节）
    struct ChapterIndexEntry {
        let nodeId: Int
        let type: String     // "part" / "chapter" / "section"
        let title: String
        let articleCount: Int
    }

    /// 返回指定法律的章节目录（part/chapter/section），附带每章条文数。
    /// 供 LLM 先选章节，再拉取章节内全部条文目录（Phase A）。
    nonisolated func chapterIndex(lawTitle: String) -> [ChapterIndexEntry] {
        queue.sync { _chapterIndex(lawTitle: lawTitle) }
    }

    private nonisolated func _chapterIndex(lawTitle: String) -> [ChapterIndexEntry] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
            SELECT n.id, n.type, COALESCE(NULLIF(n.title,''), substr(n.content,1,30)),
                   (SELECT COUNT(*) FROM nodes c
                    WHERE c.law_id = n.law_id AND c.type = 'article'
                      AND (c.parent_id = n.id
                        OR c.parent_id IN (SELECT id FROM nodes WHERE parent_id = n.id)
                        OR c.parent_id IN (SELECT id FROM nodes WHERE parent_id IN (SELECT id FROM nodes WHERE parent_id = n.id))
                      )
                   ) as art_cnt
            FROM nodes n JOIN laws l ON n.law_id = l.id
            WHERE l.title = ? AND l.is_current = 1 AND n.type IN ('part','chapter','section')
            ORDER BY n.global_order
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, lawTitle, -1, t)
        var result: [ChapterIndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(ChapterIndexEntry(
                nodeId: Int(sqlite3_column_int(stmt, 0)),
                type:   str(stmt, 1),
                title:  str(stmt, 2),
                articleCount: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return result
    }

    /// 返回指定法律的条文目录：条号 + 正文前 60 字，供 LLM 浏览后主动选条。
    /// lawTitle 需精确匹配（同 lawId(:)）。
    struct ArticleIndexEntry {
        let nodeId: Int
        let lawTitle: String
        let category: String
        let articleNumber: String
        let articleNum: Int?
        let snippet: String   // 条文正文前 60 字
    }

    nonisolated func articleIndex(lawTitle: String, chapterNodeIds: [Int] = []) -> [ArticleIndexEntry] {
        queue.sync { _articleIndex(lawTitle: lawTitle, chapterNodeIds: chapterNodeIds) }
    }

    private nonisolated func _articleIndex(lawTitle: String, chapterNodeIds: [Int]) -> [ArticleIndexEntry] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        let sql: String
        if chapterNodeIds.isEmpty {
            sql = """
                SELECT n.id, l.title, l.category, n.article_number, n.article_num, n.content
                FROM nodes n JOIN laws l ON n.law_id = l.id
                WHERE l.title = ? AND l.is_current = 1 AND n.type = 'article'
                ORDER BY n.global_order
                """
        } else {
            let idsPH = chapterNodeIds.map { String($0) }.joined(separator: ",")
            sql = """
                SELECT n.id, l.title, l.category, n.article_number, n.article_num, n.content
                FROM nodes n JOIN laws l ON n.law_id = l.id
                WHERE l.title = ? AND l.is_current = 1 AND n.type = 'article'
                  AND (
                    n.parent_id IN (\(idsPH))
                    OR n.parent_id IN (SELECT id FROM nodes WHERE parent_id IN (\(idsPH)))
                    OR n.parent_id IN (SELECT id FROM nodes WHERE parent_id IN (SELECT id FROM nodes WHERE parent_id IN (\(idsPH))))
                  )
                ORDER BY n.global_order
                """
        }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, lawTitle, -1, t)
        var result: [ArticleIndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let content = str(stmt, 5)
            let snippet = String(content.prefix(60))
            let artNum = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
            result.append(ArticleIndexEntry(
                nodeId: Int(sqlite3_column_int(stmt, 0)),
                lawTitle: str(stmt, 1),
                category: str(stmt, 2),
                articleNumber: str(stmt, 3),
                articleNum: artNum,
                snippet: snippet
            ))
        }
        return result
    }

    /// 按 nodeId 批量取完整条文（用于 Round 0 LLM 选出条号后的精确拉取）
    nonisolated func articlesByNodeIds(_ ids: [Int]) -> [RAGArticle] {
        guard !ids.isEmpty else { return [] }
        return queue.sync { _articlesByNodeIds(ids) }
    }

    private nonisolated func _articlesByNodeIds(_ ids: [Int]) -> [RAGArticle] {
        guard let db = db else { return [] }
        // ids are internal integers — safe to inline
        let ph = ids.map { String($0) }.joined(separator: ",")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
            SELECT n.id, n.law_id, l.title, l.category, l.legal_domain,
                   n.article_number, n.article_num, n.content
            FROM nodes n JOIN laws l ON n.law_id = l.id
            WHERE n.id IN (\(ph)) AND n.type = 'article'
            ORDER BY n.global_order
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [RAGArticle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let artNum = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 6)) : nil
            result.append(RAGArticle(
                nodeId: Int(sqlite3_column_int(stmt, 0)),
                lawId: Int(sqlite3_column_int(stmt, 1)),
                lawTitle: str(stmt, 2),
                category: str(stmt, 3),
                legalDomain: str(stmt, 4),
                articleNumber: str(stmt, 5),
                articleNum: artNum,
                content: str(stmt, 7),
                pinned: false
            ))
        }
        return result
    }

    // MARK: 双向引用扩展

    /// 给定一批 nodeId，返回它们通过 article_references 引用或被引用的所有条文（双向），
    /// 排除已在 seenIds 中的节点。
    nonisolated func referencedArticles(nodeIds: [Int], excludingIds: Set<Int>) -> [RAGArticle] {
        queue.sync { _referencedArticles(nodeIds: nodeIds, excludingIds: excludingIds) }
    }

    private nonisolated func _referencedArticles(nodeIds: [Int], excludingIds: Set<Int>) -> [RAGArticle] {
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

    nonisolated func gazetteDocs(source: String?, query: String, limit: Int = 500) -> [GazetteDoc] {
        queue.sync { _gazetteDocs(source: source, query: query, limit: limit) }
    }

    nonisolated func gazetteCount(source: String, query: String) -> Int {
        queue.sync {
            guard let db = db else { return 0 }
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                let sql = "SELECT COUNT(*) FROM gongbao_docs WHERE source = ?"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, source, -1, t)
                return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
            } else {
                let like = "%\(q)%"
                let sql = """
                    SELECT COUNT(*) FROM gongbao_docs
                    WHERE source = ?
                      AND (title LIKE ? OR ruling_gist LIKE ? OR keywords LIKE ?
                           OR case_number LIKE ? OR full_text LIKE ?)
                    """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, source, -1, t)
                for i in 2...6 { sqlite3_bind_text(stmt, Int32(i), like, -1, t) }
                return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
            }
        }
    }

    nonisolated func gazetteDoc(id: Int) -> GazetteDoc? {
        queue.sync {
            guard let db = db else { return nil }
            let sql = """
                SELECT id, source, COALESCE(case_number,''), title,
                       COALESCE(issue,''), COALESCE(year,0),
                       COALESCE(pub_date,''), COALESCE(url,''),
                       COALESCE(ruling_gist,''), COALESCE(keywords,''),
                       keywords_meta, COALESCE(full_text,''), case_brief
                FROM gongbao_docs WHERE id = ?
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(id))
            if sqlite3_step(stmt) == SQLITE_ROW { return _rowToGazetteDoc(stmt) }
            return nil
        }
    }

    nonisolated func gazetteDocByTitle(_ title: String) -> GazetteDoc? {
        queue.sync {
            guard let db = db else { return nil }
            let sql = """
                SELECT id, source, COALESCE(case_number,''), title,
                       COALESCE(issue,''), COALESCE(year,0),
                       COALESCE(pub_date,''), COALESCE(url,''),
                       COALESCE(ruling_gist,''), COALESCE(keywords,''),
                       keywords_meta, COALESCE(full_text,''), case_brief
                FROM gongbao_docs WHERE title = ? LIMIT 1
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW { return _rowToGazetteDoc(stmt) }
            return nil
        }
    }

    /// 策略 A：复用 FTS+LIKE 逻辑，不限 source，供 AI agent 使用
    func searchGazetteDocs(query: String, sourceFilter: String? = nil, limit: Int = 10) -> [GazetteDoc] {
        queue.sync { _gazetteDocs(source: sourceFilter, query: query, limit: limit) }
    }

    /// 策略 A 多词版：对多个扩展词分别搜索后合并去重（绕过 FTS 短词限制）
    nonisolated func searchGazetteDocsMultiTerm(terms: [String], sourceFilter: String? = nil, limit: Int = 20) -> [GazetteDoc] {
        queue.sync {
            var seen = Set<Int>()
            var results: [GazetteDoc] = []
            for term in terms {
                let docs = _gazetteDocs(source: sourceFilter, query: term, limit: limit)
                for doc in docs where seen.insert(doc.id).inserted {
                    results.append(doc)
                }
                if results.count >= limit { break }
            }
            return Array(results.prefix(limit))
        }
    }

    /// 策略 B：按 keywords 平铺字段 LIKE 检索（多词 OR）
    nonisolated func searchGazetteByKeywords(terms: [String], sourceFilter: String? = nil, limit: Int = 10) -> [GazetteDoc] {
        queue.sync {
            guard let db = db, !terms.isEmpty else { return [] }
            let clauses = terms.map { _ in "keywords LIKE ?" }.joined(separator: " OR ")
            let sourceClause = sourceFilter != nil ? " AND source = ?" : ""
            let sql = """
                SELECT id, source, COALESCE(case_number,''), title,
                       COALESCE(issue,''), COALESCE(year,0),
                       COALESCE(pub_date,''), COALESCE(url,''),
                       COALESCE(ruling_gist,''), COALESCE(keywords,''),
                       keywords_meta, COALESCE(full_text,''), case_brief
                FROM gongbao_docs WHERE (\(clauses))\(sourceClause)
                ORDER BY year DESC, issue_num DESC LIMIT \(limit)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, term) in terms.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), "%\(term)%", -1, t)
            }
            if let sf = sourceFilter {
                sqlite3_bind_text(stmt, Int32(terms.count + 1), sf, -1, t)
            }
            var docs: [GazetteDoc] = []
            while sqlite3_step(stmt) == SQLITE_ROW { docs.append(_rowToGazetteDoc(stmt)) }
            return docs
        }
    }

    /// 策略 C：通过 gongbao_case_law_links 反查引用了指定条文节点的公报文书
    nonisolated func searchGazetteByNodeIds(_ nodeIds: [Int], limit: Int = 10) -> [GazetteDoc] {
        queue.sync {
            guard let db = db, !nodeIds.isEmpty else { return [] }
            let placeholders = nodeIds.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT DISTINCT d.id, d.source, COALESCE(d.case_number,''), d.title,
                       COALESCE(d.issue,''), COALESCE(d.year,0),
                       COALESCE(d.pub_date,''), COALESCE(d.url,''),
                       COALESCE(d.ruling_gist,''), COALESCE(d.keywords,''),
                       d.keywords_meta, COALESCE(d.full_text,''), d.case_brief
                FROM gongbao_case_law_links l
                JOIN gongbao_docs d ON l.doc_id = d.id
                WHERE l.node_id IN (\(placeholders))
                ORDER BY d.year DESC, d.issue_num DESC LIMIT \(limit)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            for (i, nid) in nodeIds.enumerated() {
                sqlite3_bind_int(stmt, Int32(i + 1), Int32(nid))
            }
            var docs: [GazetteDoc] = []
            while sqlite3_step(stmt) == SQLITE_ROW { docs.append(_rowToGazetteDoc(stmt)) }
            return docs
        }
    }

    private nonisolated func _gazetteDocs(source: String?, query: String, limit: Int) -> [GazetteDoc] {        guard let db = db else { return [] }
        var docs: [GazetteDoc] = []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        if trimmed.count >= 3 {
            let escaped = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let sql: String
            if let _ = source {
                sql = """
                    SELECT d.id, d.source, COALESCE(d.case_number,''), d.title,
                           COALESCE(d.issue,''), COALESCE(d.year,0),
                           COALESCE(d.pub_date,''), COALESCE(d.url,''),
                           COALESCE(d.ruling_gist,''), COALESCE(d.keywords,''),
                           d.keywords_meta, COALESCE(d.full_text,''), d.case_brief
                    FROM gongbao_docs_fts f
                    JOIN gongbao_docs d ON f.rowid = d.id
                    WHERE gongbao_docs_fts MATCH ? AND d.source = ?
                    ORDER BY d.year DESC, d.issue_num DESC
                    LIMIT \(limit)
                    """
            } else {
                sql = """
                    SELECT d.id, d.source, COALESCE(d.case_number,''), d.title,
                           COALESCE(d.issue,''), COALESCE(d.year,0),
                           COALESCE(d.pub_date,''), COALESCE(d.url,''),
                           COALESCE(d.ruling_gist,''), COALESCE(d.keywords,''),
                           d.keywords_meta, COALESCE(d.full_text,''), d.case_brief
                    FROM gongbao_docs_fts f
                    JOIN gongbao_docs d ON f.rowid = d.id
                    WHERE gongbao_docs_fts MATCH ?
                    ORDER BY d.year DESC, d.issue_num DESC
                    LIMIT \(limit)
                    """
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, escaped, -1, t)
            if let src = source { sqlite3_bind_text(stmt, 2, src, -1, t) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                docs.append(_rowToGazetteDoc(stmt))
            }

        } else if trimmed.count >= 1 {
            let pattern = "%\(trimmed)%"
            let sql: String
            if let _ = source {
                sql = """
                    SELECT id, source, COALESCE(case_number,''), title,
                           COALESCE(issue,''), COALESCE(year,0),
                           COALESCE(pub_date,''), COALESCE(url,''),
                           COALESCE(ruling_gist,''), COALESCE(keywords,''),
                           keywords_meta, COALESCE(full_text,''), case_brief
                    FROM gongbao_docs
                    WHERE (title LIKE ? OR keywords LIKE ? OR case_number LIKE ?) AND source = ?
                    ORDER BY year DESC, issue_num DESC
                    LIMIT \(limit)
                    """
            } else {
                sql = """
                    SELECT id, source, COALESCE(case_number,''), title,
                           COALESCE(issue,''), COALESCE(year,0),
                           COALESCE(pub_date,''), COALESCE(url,''),
                           COALESCE(ruling_gist,''), COALESCE(keywords,''),
                           keywords_meta, COALESCE(full_text,''), case_brief
                    FROM gongbao_docs
                    WHERE (title LIKE ? OR keywords LIKE ? OR case_number LIKE ?)
                    ORDER BY year DESC, issue_num DESC
                    LIMIT \(limit)
                    """
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pattern, -1, t)
            sqlite3_bind_text(stmt, 2, pattern, -1, t)
            sqlite3_bind_text(stmt, 3, pattern, -1, t)
            if let src = source { sqlite3_bind_text(stmt, 4, src, -1, t) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                docs.append(_rowToGazetteDoc(stmt))
            }

        } else {
            let sql: String
            if let _ = source {
                sql = """
                    SELECT id, source, COALESCE(case_number,''), title,
                           COALESCE(issue,''), COALESCE(year,0),
                           COALESCE(pub_date,''), COALESCE(url,''),
                           COALESCE(ruling_gist,''), COALESCE(keywords,''),
                           keywords_meta, COALESCE(full_text,''), case_brief
                    FROM gongbao_docs
                    WHERE source = ?
                    ORDER BY year DESC, issue_num DESC
                    LIMIT \(limit)
                    """
            } else {
                sql = """
                    SELECT id, source, COALESCE(case_number,''), title,
                           COALESCE(issue,''), COALESCE(year,0),
                           COALESCE(pub_date,''), COALESCE(url,''),
                           COALESCE(ruling_gist,''), COALESCE(keywords,''),
                           keywords_meta, COALESCE(full_text,''), case_brief
                    FROM gongbao_docs
                    ORDER BY year DESC, issue_num DESC
                    LIMIT \(limit)
                    """
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            if let src = source { sqlite3_bind_text(stmt, 1, src, -1, t) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                docs.append(_rowToGazetteDoc(stmt))
            }
        }
        return docs
    }

    private nonisolated func _rowToGazetteDoc(_ stmt: OpaquePointer?) -> GazetteDoc {
        // col 10 = keywords_meta (JSON), col 11 = full_text, col 12 = case_brief (JSON)
        let metaJson = str(stmt, 10)
        let keywordsMeta: [String: [String]]
        if !metaJson.isEmpty,
           let data = metaJson.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result: [String: [String]] = [:]
            for (k, v) in parsed {
                if let arr = v as? [String] {
                    result[k] = arr
                } else if let s = v as? String, !s.isEmpty {
                    result[k] = [s]
                }
            }
            keywordsMeta = result
        } else {
            keywordsMeta = [:]
        }
        let briefJson = str(stmt, 12)
        let caseBrief: [String: String]
        if !briefJson.isEmpty,
           let data = briefJson.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            caseBrief = parsed
        } else {
            caseBrief = [:]
        }
        return GazetteDoc(
            id: Int(sqlite3_column_int(stmt, 0)),
            source: str(stmt, 1),
            caseNumber: str(stmt, 2),
            title: cleanStr(stmt, 3),
            issue: str(stmt, 4),
            year: Int(sqlite3_column_int(stmt, 5)),
            pubDate: str(stmt, 6),
            url: str(stmt, 7),
            rulingGist: str(stmt, 8),
            keywords: str(stmt, 9),
            keywordsMeta: keywordsMeta,
            fullText: str(stmt, 11),
            caseBrief: caseBrief
        )
    }

    // MARK: 工具

    private nonisolated func str(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cstr)
    }

    /// Like str() but strips zero-width and default-ignorable Unicode code points (e.g. U+200B).
    private nonisolated func cleanStr(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        let s = str(stmt, col)
        let cleaned = s.unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint }
            .reduce(into: "") { $0.append(Character($1)) }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 公报司法解释（现已迁移至 laws 表 source='gongbao'）

    func gazetteSfjsDocs(query: String, limit: Int = 500) -> [GazetteSfjs] {
        queue.sync { _gazetteSfjsDocs(query: query, limit: limit) }
    }

    func gazetteSfjsCount(query: String) -> Int {
        queue.sync {
            guard let db = db else { return 0 }
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            var stmt: OpaquePointer?
            let count: Int
            if query.isEmpty {
                guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM laws WHERE source='gongbao' AND is_current=1", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            } else {
                guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM laws WHERE source='gongbao' AND is_current=1 AND title LIKE ?", -1, &stmt, nil) == SQLITE_OK else { return 0 }
                sqlite3_bind_text(stmt, 1, "%\(query)%", -1, t)
            }
            defer { sqlite3_finalize(stmt) }
            count = sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
            return count
        }
    }

    func gazetteSfjsArticles(sfjsId: Int) -> [GazetteSfjsArticle] {
        queue.sync {
            guard let db = db else { return [] }
            let sql = """
                SELECT id, law_id, article_num, article_number, content, global_order
                FROM nodes
                WHERE law_id = ? AND type = 'article'
                ORDER BY global_order
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(sfjsId))
            var results: [GazetteSfjsArticle] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let artNumCol = sqlite3_column_type(stmt, 2)
                let artNum = artNumCol == SQLITE_NULL ? 0 : Int(sqlite3_column_int(stmt, 2))
                results.append(GazetteSfjsArticle(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    sfjsId: Int(sqlite3_column_int(stmt, 1)),
                    articleNum: artNum,
                    articleNumber: sqlite3_column_type(stmt, 3) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 3)) : "",
                    content: sqlite3_column_type(stmt, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 4)) : "",
                    globalOrder: Int(sqlite3_column_int(stmt, 5))
                ))
            }
            return results
        }
    }

    func gazetteSfjsDoc(id: Int) -> GazetteSfjs? {
        queue.sync {
            guard let db = db else { return nil }
            let sql = """
                SELECT id, title, doc_number, pub_date, effective_date, '' as url, full_text
                FROM laws WHERE id = ? AND source = 'gongbao'
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(id))
            let result: GazetteSfjs? = sqlite3_step(stmt) == SQLITE_ROW ? self._rowToGazetteSfjs(stmt) : nil
            return result
        }
    }

    func searchGazetteSfjs(query: String, limit: Int = 10) -> [GazetteSfjs] {
        queue.sync { _gazetteSfjsDocs(query: query, limit: limit) }
    }

    private nonisolated func _gazetteSfjsDocs(query: String, limit: Int) -> [GazetteSfjs] {
        guard let db = db else { return [] }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        let sql: String
        if query.isEmpty {
            sql = """
                SELECT id, title, doc_number, pub_date, effective_date, '' as url, full_text
                FROM laws WHERE source='gongbao' AND is_current=1
                ORDER BY pub_date DESC LIMIT ?
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(limit))
        } else {
            sql = """
                SELECT id, title, doc_number, pub_date, effective_date, '' as url, full_text
                FROM laws WHERE source='gongbao' AND is_current=1 AND title LIKE ?
                ORDER BY pub_date DESC LIMIT ?
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_text(stmt, 1, "%\(query)%", -1, t)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
        defer { sqlite3_finalize(stmt) }
        var results: [GazetteSfjs] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(_rowToGazetteSfjs(stmt))
        }
        return results
    }

    private nonisolated func _rowToGazetteSfjs(_ stmt: OpaquePointer?) -> GazetteSfjs {
        GazetteSfjs(
            id:            Int(sqlite3_column_int(stmt, 0)),
            title:         str(stmt, 1),
            docNumber:     str(stmt, 2),
            pubDate:       str(stmt, 3),
            effectiveDate: str(stmt, 4),
            url:           str(stmt, 5),
            fullText:      str(stmt, 6)
        )
    }
}
