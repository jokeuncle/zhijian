# 知间 macOS dictionary — approved design

The user approved the concept-desk proposal and native SwiftUI recommendation with “实现吧”, then explicitly required performance. This approval authorizes implementation without a second design gate.

## Experience

Three columns: library navigation, paginated concept index and an immersive reading surface. Paper-white ground, graphite text, restrained moss-green actions, native macOS controls and SF Symbols. Keep the full explanation readable rather than surrounding it with nested cards. A slim learning path keeps each article's original order.

Entry sections: plain-language summary, analogy, collapsible technical detail and analogy limits, source notes, linked concepts, and the user's own explanation. The supplied material is labeled as user-provided notes. A comparison learning unit may reference distinct entries rather than merging their names as aliases.

Review initially hides the explanation and asks the reader to recall it. The three ratings update persisted next-review times and mastery. Favorites, recency, collection filtering, trash recovery, history, an editor and import/export are real operations.

## Architecture and data contract

SwiftPM library DictionaryCore contains Codable domain models, system-SQLite persistence, import/export and initial content. ZhijianApp uses SwiftUI/AppKit; zhijian is a separate command-line executable with JSON output and newline-framed stdio MCP. Both use the same database under Application Support/Zhijian unless ZHIJIAN_DATABASE or --database overrides it.

Entries have stable IDs, revision numbers, title, English name, aliases, summary, analogy, detail, caveat, source metadata, personal note, relation IDs, mastery, review schedule, timestamps and soft-deletion. Collection membership has a stable position. Change history stores actor and snapshots. Writes use transactions and optimistic revision checks. Foreign-key and relation validation reject invalid batch input atomically.

SQLite uses WAL, busy timeout, prepared statements, indexes for navigation and FTS5 trigram substring search. Short Chinese searches use a bounded substring fallback. UI results are paginated with a page size of 60; search is debounced 160 ms and executed off the main actor. Stale async results cannot replace newer selections. The app notices agent changes using cheap data-version checks while active.

## Delivery and acceptance

macOS 14 or later; build with the available Swift toolchain and no external dependencies. Package a runnable build/知间.app and a CLI, provide scripts and documentation, and project-local Codex MCP configuration. Do not overwrite global Codex configuration.

Acceptance: swift test; release build; independent CLI persistence/CRUD/search/import/export/trash/version-conflict checks; real MCP initialize/list/call transport checks; native app launch and screenshot/accessibility inspection at regular and compact window sizes; a separate 10,000-entry benchmark reporting batch import, first-page reads and short/long query latency. No invented benchmarks or original-article citations.
