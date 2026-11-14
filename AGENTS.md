# Working on 知间

This is a native SwiftUI macOS application, not a website. The user prioritizes immersive reading and performance. PRODUCT.md, DESIGN.md and docs/superpowers/specs/2026-11-15-zhijian-design.md describe the product.

## Code discovery

Prefer codebase-memory-mcp: search_graph, trace_path, get_code_snippet, query_graph and get_architecture. Index the repository first if it is not indexed. Use direct source reads for exact known files when indexing is unavailable. The initial index attempt failed because an unverified/pre-coordination CBM generation was active; do not stop the user's other CBM processes to fix it.

## Maintaining the user's dictionary

Use the local CLI or the zhijian MCP tools. These work independently of the app window and share its SQLite library. Never modify SQLite rows or files directly: that bypasses history, relation checks, the search index and optimistic revisions.

```sh
./scripts/zhijian list --query '残差流'
./scripts/zhijian get residual-stream
./scripts/zhijian collections
```

The CLI returns JSON. Full entries contain a `content` object and a top-level `revision`. Search results are paginated summaries; fetch the complete entry before editing.

```sh
./scripts/zhijian create --json - <<'JSON'
{"title":"示例概念","english":"Example concept","summary":"一句话的大白话解释","sourceTitle":"用户提供的笔记"}
JSON
```

Read the current revision, then patch only the requested fields. Preserve personalNote and source context unless the user asks to change them. Pass the observed revision; on conflict, re-read and reconcile rather than guessing the next revision.

```sh
./scripts/zhijian update ENTRY_ID --revision OBSERVED_REVISION --json - <<'JSON'
{"summary":"更直白的解释"}
JSON
./scripts/zhijian delete ENTRY_ID --revision OBSERVED_REVISION
./scripts/zhijian restore ENTRY_ID --revision OBSERVED_REVISION
```

Delete is recoverable. Review ratings are 0 (not yet), 1 (uncertain), 2 (can explain). `history` and `revert` retain audit records. Never pass a guessed revision.

Batch import accepts JSON `{ "entries": [...], "collectionTitle": "文章名", "collectionSubtitle": "主线" }` or the user's numbered Markdown notes. Order becomes the collection's learning path. Duplicate names are skipped; existing explanations are not overwritten. Batch relation IDs may point to other entries in the same batch. Comparison groups contain distinct concepts; do not turn checkpoint, safetensors and GGUF into aliases.

Source identity matters: the seed is adapted from user-provided concept notes. It is not a verified quotation from an original article. Do not invent an article URL or source attribution.

## Development and verification

- `scripts/build.sh` builds a release .app with embedded CLI and seed data.
- `.build/release/DictionaryChecks` runs core behavior checks without XCTest (the installed CLT toolchain does not ship XCTest or Swift Testing).
- `python3 scripts/verify.py` checks actual packaged CLI processes and stdio MCP. Tests use temporary libraries.
- `scripts/zhijian benchmark --count 10000` measures a synthetic temporary library and removes it afterward.
- Use `--database /temporary/path.sqlite --no-seed` for mutations during tests. Never put synthetic test records into the user's default library.
- Keep result pages bounded, database work off the main actor, search debounced, collection progress rendering bounded and all writes transactional.

For native UI automation use computer-use tooling. For browser work prefer the installed ego-browser skill, read its complete SKILL.md first, and fall back only when unavailable.
