# 知间

<!-- impeccable:product-schema 1 -->

## Platform

macOS (native desktop; the skill's mobile/web platform enumeration does not cover this explicitly requested platform).

## Stack

User approved the recommended SwiftUI native macOS application. Swift Package Manager, system SQLite, Foundation and AppKit. No web wrapper, runtime downloads, external packages or API key required.

## Users

One person collecting unfamiliar concepts while reading AI articles, studying their plain-language explanations, connecting concepts and revisiting them over time.

## Product Purpose

A local personal concept dictionary: preserve plain-language explanations and source context, organize an article into a learning path, connect related concepts and practice explaining them independently.

## Operating Context

Immersive learning is the primary experience, explicitly selected by the user. Codex must be able to maintain the same dictionary through a native tool interface. App windows are not required for CLI/MCP access.

## Capabilities and Constraints

Native three-column reading workspace; entry CRUD; article collections with ordered learning units; concept relations; personal notes; favorites; recall-first review; recoverable trash; versioned history; JSON/Markdown import/export; CLI and local stdio MCP tools. All persist locally. Mutations must detect stale revisions. Performance is an explicit user requirement: paginated results, cancellable debounced background search, batch transactions, indexed queries and a reproducible 10,000-entry benchmark. Cloud sync and automatic AI generation are outside the first release.

## Evidence on Hand

The user supplied 15 numbered learning units in four categories, explaining model internals, rank-one weight edits, reproduction tools and thinking-loop metrics. These are user-provided notes, not excerpts verified against an original article. Some units compare distinct concepts; comparison titles must not turn those concepts into false synonyms. Missing article URLs must remain absent.

## Product Principles

- Lead with a plain-language explanation and reveal detail progressively.
- Preserve the article's reading order alongside the reusable dictionary.
- Treat desktop and agent operations as equal clients of one data core.
- Keep personal notes, source provenance and reversible edits.
- Measure performance with synthetic data in a separate temporary library.
