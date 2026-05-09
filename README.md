# 律疏 · 中国法律法规检索与咨询

面向 iPhone 和 iPad 的中文法律法规离线浏览、全文检索与 AI 法律咨询 App。内置完整 SQLite 数据库，支持完全离线阅读；法律顾问功能通过多专家协作 Agent 系统完成案情分析与法条检索。

---

## 功能概览

### 法律浏览
- 收录 1,526 部现行有效法律法规，按 7 个法律部门分组展开浏览
- 全文搜索：法律名称 + 条文内容双通道，支持中文数字与阿拉伯数字互转
- 短词（1–2 字）走 `LIKE` 模糊匹配；3 字以上走 FTS5 trigram 精确检索
- 法律详情页：编 / 章 / 节 / 条层级展示，右侧比例索引条，条内关键词过滤
- 条文交叉引用：彩色超链接跳转，记录返回栈，重启后可沿链路原路返回

### 法律顾问（AI 问答）
- 统一走专家 Agent 系统，根据问题类型自动路由（法条查询 / 知识问答 / 案情分析），无需手动选择模式
- 口语化问题自动规范化（"楼上噪音扰民" → 补充相邻关系、侵权责任等法律术语）
- 思考过程逐步展示，参考法条点击跳转
- 对话历史自动保存，重启后完整恢复（含专家上下文）
- 支持 Gemini Flash、DeepSeek、Groq、本地 Ollama

---

## Agent 路由架构

### 总体流程

```
用户输入
    │
    ▼
┌─────────────────────────────┐
│       问题法律化改写         │  口语 → 补充法律性质、当事人关系、适用领域
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│        意图分类器            │  LLM 4-way 分类（含关键词 fast-path）
└──────┬──────┬──────┬────────┘
       │      │      │      │
  off_topic  general  law_lookup  case / follow_up
       │      │      │      │
       ▼      ▼      ▼      ▼
   硬编码  General  LawLookup  Expert
   引导语  Pipeline  Pipeline   Pipeline
```

---

### 意图分类（`classifyIntent`）

| 意图 | 触发条件 | 路由目标 |
|------|---------|---------|
| `off_topic` | 问候、闲聊、App 使用说明类 | 硬编码引导语，零 LLM 调用 |
| `general` | 法律知识查询，不依赖具体案情 | General Pipeline |
| `law_lookup` | 查询某条具体法律规定或某部法律内容 | LawLookup Pipeline |
| `case` | 陈述具体纠纷事实（含日常纠纷：噪音、欠款、伤害等） | Expert Pipeline |
| `follow_up` | 基于已有案情的追问 | Expert Pipeline（复用上次专家） |

**Fast-path**：无历史对话 + 消息 < 15 字 + 不含法律关键词 → 直接判 `off_topic`，跳过 LLM。

---

### General Pipeline

```
general 问题
    │
    ▼
┌──────────────────┐
│   复杂度判断      │
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
  simple    complex
    │         │
    ▼         ▼
 宽域 FTS   Expert Pipeline
 + 单次     （跳过追问，
  LLM 回答    maxFollowUpRounds=0）
```

---

### LawLookup Pipeline

```
law_lookup 问题
    │
    ▼
Coordinator 定性 + 专家路由
    │
    ▼
每位专家用 LLM 知识定位法条 → 精确 DB 查询
    │
    ▼
汇总原文 → LLM 引用原文作答（不发表评论）
```

---

### Expert Pipeline（案情分析核心）

```
case / follow_up 问题
    │
    ├─ [follow_up] 合并 knownFacts + conversationHistory ────────────────────┐
    │                                                                         │
    ▼                                                                         │
┌──────────────────────────────────────────────────────────┐                 │
│               问题拆分（decomposeQuestion）               │                 │
│  多问题（含编号）→ 拆分子问题列表；单问题直接进入           │                 │
└──────────────────────────┬───────────────────────────────┘                 │
                           │                                                  │
                           ▼                                                  │
┌──────────────────────────────────────────────────────────┐                 │
│           Coordinator：法律定性 + 专家路由                │                 │
│  输出：characterization（法律性质）                       │                 │
│        experts（选中的 SubExpert 列表，可跨专家组）        │                 │
└──────────────────────────┬───────────────────────────────┘                 │
                           │                                                  │
              ┌────────────┼──────────────┐                                  │
              ▼            ▼     ...      ▼                                  │
          专家 A        专家 B         专家 N                                │
       ┌──────────┐  ┌──────────┐  ┌──────────┐                             │
       │ FTS 检索 │  │ FTS 检索 │  │ FTS 检索 │                             │
       │ 相关性   │  │ 相关性   │  │ 相关性   │                             │
       │  过滤    │  │  过滤    │  │  过滤    │                             │
       │ LLM 分析 │  │ LLM 分析 │  │ LLM 分析 │                             │
       └────┬─────┘  └────┬─────┘  └────┬─────┘                             │
            └─────────────┼──────────────┘                                   │
                          │                                                   │
                          ▼                                                   │
             ┌────────────────────────┐                                       │
             │      专家组综合         │  同组专家合并，消除重复               │
             └───────────┬────────────┘                                       │
                         │                                                    │
                         ▼                                                    │
             ┌────────────────────────┐                                       │
             │   Coordinator 整合     │  生成最终连贯回答（流式输出）         │
             └───────────┬────────────┘                                       │
                         │                                                    │
                         ▼                                                    │
             ┌────────────────────────┐                                       │
             │       追问判断          │  ◄──────────────────────────────────┘
             │  缺失关键事实 &&        │
             │  followUpRound <        │
             │  maxFollowUpRounds ？   │
             └──────┬─────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
      需要追问               直接输出
         │
         ▼
   clarifyingQuestion 事件
   → UI 展示问题，等待用户回复
   → 下一轮 followUpRound + 1
   （最后一轮：一次性列出所有剩余问题）
```

---

### 专家组与细分专家

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           6 个专家组                                     │
├──────────────┬──────────────────────────────────────────────────────────┤
│  民法专家组   │ 合同通则 · 买卖合同 · 租赁合同 · 借款合同                  │
│              │ 建设工程合同 · 服务委托合同                                 │
│              │ 侵权通则 · 产品责任 · 交通事故 · 医疗损害 · 特殊侵权        │
│              │ 人身伤害 · 生命健康权 · 名誉隐私权                          │
│              │ 物权 · 不动产所有权 · 用益物权 · 担保物权                   │
│              │ 民事法律行为效力 · 诉讼时效                                 │
│              │ 婚姻家庭（离婚财产 · 子女抚养 · 收养）                      │
│              │ 继承（法定继承 · 遗嘱继承）                                 │
├──────────────┼──────────────────────────────────────────────────────────┤
│  刑法专家组   │ 财产犯罪 · 经济犯罪 · 腐败职务犯罪                         │
├──────────────┼──────────────────────────────────────────────────────────┤
│  劳动法专家组 │ 劳动合同 · 劳动争议 · 工资福利 · 工伤职业病                │
├──────────────┼──────────────────────────────────────────────────────────┤
│  行政法专家组 │ 行政诉讼                                                   │
├──────────────┼──────────────────────────────────────────────────────────┤
│  经济法专家组 │ 消费者权益 · 产品质量 · 电子商务 · 公司商事                │
├──────────────┼──────────────────────────────────────────────────────────┤
│  诉讼专家组   │ 民事诉讼 · 刑事诉讼                                        │
└──────────────┴──────────────────────────────────────────────────────────┘

共 38 个细分专家，Coordinator 根据案情动态选取 1–N 个
```

---

### 问题改写流程

```
用户原始输入
    │
    ├─ 追问 / 极短问题（< 8 字）→ 跳过，原文传入
    │
    ▼
┌─────────────────────────────────────────────┐
│             rewriteToLegalForm              │
│  • 补充法律性质（侵权 / 违约 / 相邻关系等）  │
│  • 明确当事人关系（租户与房东 / 相邻业主等） │
│  • 补充适用法律领域关键词                   │
│  • 保留原始事实，不捏造细节                 │
│  • 已规范的问题 → 原文返回                  │
└─────────────────────────────────────────────┘
    │
    ▼
改写后的问题（用于后续所有检索步骤）
思考步骤展示「原始 → 改写」对比
```

---

## 项目结构

```
ChineseLawsSearch/
├── App/
│   ├── ChineseLawsSearchApp.swift   # @main 入口
│   ├── ContentView.swift            # 根视图，Tab 路由，导航状态，启动恢复
│   └── UserStore.swift              # 用户偏好 + 阅读记录（iCloud KV 同步）
│
├── Services/
│   ├── DatabaseManager.swift        # SQLite 封装（只读 bundle DB）
│   ├── LegalRAGService.swift        # RAG pipeline（事件流 RAGEvent）
│   ├── LLMProvider.swift            # LLM 多后端抽象
│   └── ChatHistory.swift            # 对话历史持久化（iCloud Documents 同步）
│
├── Agents/
│   ├── LegalExpertService.swift     # Expert pipeline 入口
│   │                                  （意图分类 / 问题改写 / 追问 / general / law_lookup）
│   ├── ExpertGroups.swift           # 6 个专家组注册表
│   ├── Core/
│   │   └── ExpertModels.swift       # SubExpert / ExpertGroup / RequiredInfo 模型
│   └── Experts/
│       ├── Civil/                   # 民事专家（合同 / 侵权 / 物权 / 家事 / 继承）
│       ├── Criminal/                # 刑事专家
│       ├── Labor/                   # 劳动法专家
│       ├── Economic/                # 经济法专家
│       └── Procedure/               # 诉讼程序专家
│
├── Views/
│   ├── TOCView.swift                # 目录浏览 + 内联搜索（常驻搜索栏）
│   ├── LawDetailView.swift          # 条文详情 + 交叉引用 + 索引条
│   ├── LegalChatView.swift          # 法律顾问 UI + ViewModel + 历史侧栏
│   └── WelcomeView.swift            # 使用说明页（首次启动自动展示）
│
└── Utilities/
    ├── KeychainHelper.swift          # Keychain 存取（iCloud Keychain 同步）
    ├── AppColors.swift               # 全局色彩配置
    └── Color+Adaptive.swift          # 深色模式适配
```

---

## 持久化与同步

| 数据 | 存储 | iCloud 同步 |
|------|------|------------|
| 用户偏好（模型、显示设置等） | `@AppStorage`（UserDefaults） | ✗ 本地 |
| 上次阅读法律 + 条文 + 返回栈 | `NSUbiquitousKeyValueStore` | ✓ KV Store |
| 对话历史 | iCloud Documents（降级至本地 Documents） | ✓ Documents |
| API Key | 系统 Keychain（`kSecAttrSynchronizable`） | ✓ iCloud Keychain |

---

## 数据库结构

数据库 `law_content.db`（SQLite，约 132 MB），只读，随 App Bundle 分发，`journal_mode=DELETE`。

### `laws` — 法律元数据

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | INTEGER PK | 稳定主键 |
| `title` | TEXT | 法律全称 |
| `category` | TEXT | 宪法 / 法律 / 行政法规 / 司法解释 / 修正案 / 法律解释 / 监察法规 |
| `legal_domain` | TEXT | 民法典 / 民法商法 / 刑法 / 行政法 / 经济法 / 社会法 / 宪法相关法 / 诉讼与非诉讼程序法 |
| `pub_date` | TEXT | 公布日期 `YYYY-MM-DD` |
| `issuing_org` | TEXT | 发布机关（白名单精确匹配） |
| `doc_number` | TEXT | 发文字号 |
| `is_current` | INTEGER | 1 = 现行版本 |
| `aliases` | TEXT | 逗号分隔别名 |

### `nodes` — 条文层级节点

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | TEXT | `part` / `chapter` / `section` / `article` |
| `parent_id` | INTEGER FK | 树形父节点 |
| `content` | TEXT | 节点完整文本 |
| `global_order` | INTEGER | 深度优先遍历序号，`ORDER BY global_order` 得正确展示顺序 |
| `article_num` | INTEGER | 条号数值（跳转定位用） |

**索引**：`(law_id, global_order)`、`(law_id, part_num, chapter_num, section_num, article_num)`

### `nodes_fts` / `nodes_fts_bigram` — 全文检索虚表

均为外部内容表（`content="nodes"`），不复制原文，节省约 175 MB。

| 表 | 分词器 | 适用场景 |
|----|--------|---------|
| `nodes_fts` | FTS5 `trigram` | 3+ 字中文子串精确匹配 |
| `nodes_fts_bigram` | FTS5 `unicode61` | 词边界匹配；1–2 字走 `LIKE` 兜底 |

### `article_references` — 条文引用关系

6,452 条引用记录，解析率 98.8%，支持跨法引用（`cross_law`）和本法内引用（`self_ref`）。

---

## 数据来源

法律原文来源于**[国家法律法规数据库](https://flk.npc.gov.cn/)**，由 [laws_data](https://github.com/doxie/laws_data) pipeline 结构化处理后打包。中华人民共和国法律法规原文属于国家公开文献，不受著作权保护。

---

## 技术栈

| 项目 | 说明 |
|------|------|
| 语言 | Swift 6 |
| UI | SwiftUI（iOS 17+） |
| 数据库 | SQLite（C API 直接调用） |
| 全文检索 | FTS5 trigram + unicode61 + LIKE 兜底 |
| LLM | Gemini Flash 2.0 / DeepSeek V3 / Groq Llama 3.3 70B / Ollama |
| 同步 | iCloud KV Store + iCloud Documents + iCloud Keychain |
| 最低系统 | iOS 17 / iPadOS 17 |
