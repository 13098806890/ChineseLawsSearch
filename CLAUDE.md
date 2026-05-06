# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `ChineseLawsSearch.xcodeproj` in Xcode and build with `Cmd+B`, or run via `Cmd+R`. Tests run with `Cmd+U`.

From the command line:
```bash
# Build
xcodebuild -project ChineseLawsSearch.xcodeproj -scheme ChineseLawsSearch -configuration Debug build

# Run tests
xcodebuild -project ChineseLawsSearch.xcodeproj -scheme ChineseLawsSearch -configuration Debug test

# Run a single test
xcodebuild -project ChineseLawsSearch.xcodeproj -scheme ChineseLawsSearch -configuration Debug test -only-testing:ChineseLawsSearchTests/ClassName/testMethodName
```

## Architecture

This is a macOS/iOS SwiftUI app for browsing and searching Chinese laws. The UI follows a split-view master-detail pattern (`NavigationSplitView`): `TOCView` in the sidebar lists laws, and a detail pane shows selected content.

**Data layer**: The app bundles a 106MB SQLite database (`law_content.db`) containing 1,902 laws. Rather than using SwiftData as the primary data source, the database is the source of truth. Key tables:

- `laws` — law metadata (title, category, legal_domain, pub_date, issuing_org, full_text)
- `nodes` — hierarchical structure of each law (parts → chapters → sections → articles), with `parent_id` for tree traversal and `global_order` for sequencing
- `article_references` — cross-law and intra-law references (4,994 entries), with `ref_type` of `"cross_law"` or `"self_ref"`
- `nodes_fts` — FTS5 virtual table with **trigram tokenization** for Chinese full-text search over node content

**Important**: The database access layer and model definitions are not yet implemented. SwiftData (`ModelContainer`) is configured in `ChineseLawsSearchApp.swift` but the models need to be created to map to the SQLite schema.

## Database Notes

- FTS5 search uses trigram tokenization — queries should use `nodes_fts MATCH '...'` syntax; character-level matching works without word boundaries
- `nodes` uses composite index `(law_id, part_num, chapter_num, section_num, article_num)` for hierarchical lookups
- `laws.is_current = 1` filters to active versions (some laws have superseded versions)
- The database is read-only (bundled resource); no write operations needed
