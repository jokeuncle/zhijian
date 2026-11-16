---
name: "知间"
description: "A quiet native macOS concept dictionary for reading, connecting and recalling ideas."
colors:
  accent: "#3E624C"
  accent-dark: "#A6C4A2"
  on-accent: "#FFFFFF"
  on-accent-dark: "#18271C"
  rust: "#9B553B"
  rust-dark: "#E8AF91"
  paper: "#FCFBF7"
  paper-dark: "#20231F"
  sidebar: "#EEEFE7"
  sidebar-dark: "#191D19"
  index: "#F6F6F0"
  index-dark: "#1C201C"
  ink: "#27332C"
  ink-dark: "#E5E9DF"
  secondary: "#596456"
  secondary-dark: "#A2AC9F"
  selection: "#E5EBDF"
  selection-dark: "#303F31"
  rule: "#DDDFD4"
  rule-dark: "#3B4339"
  note: "#F0F0E7"
  note-dark: "#2B3128"
typography:
  display:
    fontFamily: "Songti SC"
    fontSize: "36pt"
    fontWeight: 400
  heading:
    fontFamily: "Songti SC"
    fontSize: "25pt"
    fontWeight: 400
  headline:
    fontFamily: "Songti SC"
    fontSize: "25pt"
    fontWeight: 400
  body:
    fontFamily: "system-ui"
    fontSize: "16pt"
    fontWeight: 400
  title:
    fontFamily: "system-ui"
    fontSize: "13pt"
    fontWeight: 500
  label:
    fontFamily: "system-ui"
    fontSize: "13pt"
    fontWeight: 600
  field:
    fontFamily: "system-ui"
    fontSize: "12pt"
    fontWeight: 400
  chip:
    fontFamily: "system-ui"
    fontSize: "12pt"
    fontWeight: 500
  note:
    fontFamily: "system-ui"
    fontSize: "14pt"
    fontWeight: 400
  meta:
    fontFamily: "system-ui"
    fontSize: "10pt"
    fontWeight: 400
rounded:
  path: "1.5pt"
  chip: "6pt"
  control: "7pt"
  button: "8pt"
  note: "9pt"
spacing:
  inline-gap: "7pt"
  concept-gap: "8pt"
  control-inset: "10pt"
  row-inset-y: "11pt"
  callout-inset: "16pt"
  primary-inset-x: "17pt"
  card-inset: "18pt"
  index-inset: "20pt"
  section-gap: "29pt"
  reading-inset: "40pt"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.title}"
    rounded: "{rounded.button}"
    padding: "10pt 17pt"
  button-quiet:
    textColor: "{colors.secondary}"
    width: "30pt"
    height: "30pt"
  search-field:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.field}"
    rounded: "{rounded.control}"
    padding: "{spacing.control-inset}"
  concept-row:
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.control}"
    padding: "11pt 10pt"
  concept-row-hover:
    backgroundColor: "{colors.paper}"
  concept-row-selected:
    backgroundColor: "{colors.selection}"
    typography: "{typography.label}"
  concept-link:
    backgroundColor: "{colors.index}"
    textColor: "{colors.accent}"
    typography: "{typography.chip}"
    rounded: "{rounded.chip}"
    padding: "8pt 11pt"
  note-card:
    backgroundColor: "{colors.note}"
    textColor: "{colors.ink}"
    rounded: "{rounded.note}"
    padding: "{spacing.card-inset}"
  caveat-card:
    backgroundColor: "{colors.note}"
    rounded: "{rounded.button}"
    padding: "{spacing.callout-inset}"
  path-position:
    backgroundColor: "{colors.rule}"
    rounded: "{rounded.path}"
    height: "5pt"
  path-position-selected:
    backgroundColor: "{colors.accent}"
  mastery-badge:
    backgroundColor: "{colors.selection}"
    textColor: "{colors.accent}"
    typography: "{typography.meta}"
    padding: "6pt 10pt"
---

# Design System: 知间

<!-- Native scan: macOS / SwiftUI and AppKit. Sources: PRODUCT.md; .impeccable/surfaces/library.md; Sources/ZhijianApp/Theme.swift, ConceptFlowLayout.swift, Workspace.swift, EntryListView.swift and EntryDetailView.swift. Supplied final captures: .impeccable/review/desktop-final.jpg, compact-final.jpg and review-final.jpg. This documentation pass inspected source and those captures; it did not run a build, launch the app, benchmark performance or capture dark appearance. -->

## Overview

**Creative North Star: "The Concept Desk"**

知间 is a quiet native macOS reading space. Warm paper, graphite text and moss accents make unfamiliar ideas approachable; Songti gives concept titles and plain-language explanations a bookish voice, while the system face keeps reading and controls familiar.

The interface recedes around the explanation. Tonal surfaces distinguish navigation, the index and the reading page. Detail unfolds on request, related concepts remain compact, and a personal note invites the reader to explain an idea in their own words. Controls, focus, menus and sheets retain native macOS behavior.

**Key Characteristics:**

- Warm paper, graphite and moss with explicit adaptive dark counterparts.
- Songti for concept language; the native system face and SF Symbols for reading and operation.
- Flat tonal layers, fine rules and restrained rounded controls.
- Progressive reading, intrinsic-width concept links and recall before reveal.

## Colors

The frontmatter records the exact sRGB values from Palette. Every base token has a matching dark token; NSColor selects the pair using the current Aqua or Dark Aqua appearance. These are deliberate pairs, not an automatic inversion.

### Primary

- **Moss** — accent and accent-dark: primary actions, links, active icons, selected path positions and mastery text.
- **On Moss** — on-accent and on-accent-dark: foreground for the filled primary button.

### Secondary

- **Rust** — rust and rust-dark: caveat headings, trash notices, unsaved notes and conflict messages.

### Neutral

- **Warm Paper** — paper and paper-dark: reading canvas, search field and hovered index rows.
- **Sage Paper** — sidebar and sidebar-dark: library navigation.
- **Index Paper** — index and index-dark: concept index and related-concept links.
- **Graphite** — ink and ink-dark: primary text; also the transient confirmation capsule.
- **Secondary Graphite** — secondary and secondary-dark: supporting text, metadata and quiet icons.
- **Selected Sage** — selection and selection-dark: selected rows and mastery capsules.
- **Fine Rule** — rule and rule-dark: separators, field strokes and inactive path positions.
- **Note Paper** — note and note-dark: personal notes, caveats and trash notices.

**The Meaning Before Color Rule.** Moss marks actions, concept links and selected meaning. Rust marks caveats, unsaved work and conflicts; it is not a second decorative accent.

## Typography

Songti SC is requested through the native custom-font API. The frontmatter's system-ui means SwiftUI's system font, with macOS owning its font and glyph fallback. There is no web-font dependency. Font weights 400, 500 and 600 represent native regular, medium and semibold.

| Role | Native use and spacing |
| --- | --- |
| display | Selected concept title; relative to largeTitle, with 4pt added line spacing. |
| heading | Index heading; relative to title2, with 4pt added line spacing. |
| headline | Leading plain-language explanation; direct Songti size, with 8pt added line spacing and moss text. |
| body | Reading paragraphs; 7pt added line spacing, selectable text and vertical expansion. |
| title / label | Medium list titles and primary-button text; semibold selected titles and section labels. |
| field / chip | Regular search text and medium concept-link text. |
| note | Personal-note editor; 5pt added line spacing. |
| meta | Counts, row summaries, hints and status labels. |

Added line spacing is SwiftUI lineSpacing, not a total line height. Supporting English names use regular system text (14pt); collection subtitles and context use smaller system text (11pt). Concept rows allow two title lines and one summary line. SF Symbols supply interface icons; quiet toolbar symbols use regular system sizing (15pt).

**The Two Voices Rule.** Use Songti for concept titles and the leading explanation. Use the native system face for body text, metadata, inputs and controls.

## Layout

The library is a resizable native HSplitView with three columns. Sidebar width is bounded (minimum 200pt, ideal 218pt, maximum 240pt); index width is bounded (minimum 270pt, ideal 314pt, maximum 340pt); the reader has a minimum width (540pt) and takes the remaining space. The library brief specifies a minimum window (1080 × 700pt), an ordinary window (1340 × 860pt) and a compact review size (1100 × 760pt). Compact windows keep the three columns and use vertical scrolling.

The detail content has a maximum width (700pt), horizontal padding (40pt), top padding (34pt) and bottom padding (32pt), centered in the available reader. Its context toolbar uses horizontal padding (30pt), top padding (24pt) and bottom padding (16pt). The index uses horizontal padding (20pt). Larger reading sections commonly finish with the section-gap token; these are extracted values, not a new universal spacing grid.

Related-concept links use ConceptFlowLayout. Each link is measured at its natural width; oversized labels are measured again against the available width. Links wrap with equal horizontal and vertical gaps (8pt), without stretching to fill a row.

The sidebar gives all remaining vertical space to its scrollable article collections. It has no promotional quote card; review remains available through “温故知新”. Collection titles show their full text on hover, and native scroll indicators make the list discoverable. An independent 11pt search field filters titles and subtitles after a 160ms debounce. The adjacent count and 10pt sort menu support recently read, newest and title order; changing this search never changes the selected entry or entry search. Trash and local storage controls stay at the bottom.

The collection path renders at most 24 nearby positions. It starts up to 12 positions before the current position, clamped to the collection ends. Markers have a visible height (5pt), an interaction height (17pt) and inter-marker gaps (3pt). Index rows use a lazy stack with row gaps (4pt), load in pages of 60 and scroll the selection into view. Preserve the product contract of debounced cancellable search and database work off the main actor; no runtime performance result is asserted here.

**The Reading First Rule.** Keep the reading pane flexible, the index bounded and related concepts at their intrinsic width. Resizing must preserve a readable column and vertical scrolling.

## Elevation & Depth

The inspected workspace defines no custom shadows. Paper, index, sidebar and note tones provide depth, while fine rules separate content. Reading separators are thin (1pt); the search field has a finer stroke (0.5pt), and concept links use a fine outline (0.7pt). Native menus, sheets, alerts and bordered controls retain system rendering.

**The Tonal Separation Rule.** Separate the main workspace with surface tone and fine rules. Preserve system-owned elevation for native menus, sheets and alerts.

## Shapes

Use the frontmatter's compact radius vocabulary: a slight curve for path markers, small curves for concept links, then control, button and note corners. Mastery labels and confirmation toasts are native Capsule shapes; their radius is derived from their bounds, not a fixed-radius token. Main reading sections remain open on the page rather than becoming repeated cards.

## Components

### Buttons

MossButtonStyle uses medium system text (13pt), horizontal padding (17pt), vertical padding (10pt) and the button radius. Only the background opacity changes: enabled at rest (1), enabled while pressed (0.8), disabled (0.4). The on-accent foreground remains unchanged. There is no custom hover treatment or explicit animation in this style.

QuietIconButton is a plain SF Symbol button with a square interaction frame (30 × 30pt), secondary color at rest and accent color when active. Its label is provided to help and accessibility. Preserve native keyboard and focus behavior; no custom focus-ring token is defined. The note-save action uses the native small bordered button.

Enabled buttons, menu triggers, navigation rows, path markers, concept links and disclosure headers show a pointing-hand cursor over their interaction area. Disabled controls use the default cursor; expanded reading content and text inputs keep native text selection. `pointingHandCursor()` uses the system pointer style on macOS 15 and later, with AppKit cursor rectangles for macOS 14, avoiding global cursor push/pop state. Disclosure headers expose expansion state and keep their content outside the cursor region.

### Search and Index Navigation

The search field combines a magnifier, a plain TextField, and either the empty-state Command-F hint or a clear action. It uses the paper surface, control radius, control-inset padding and the fine field stroke. Programmatic search focus is connected to FocusState. Filtering stays in the native menu beside the entry count; loading replaces the entry count with the current search status. Entry totals appear only beside this filter; navigation rows and heading copy do not repeat them. Generic index footer and introductory slogans are omitted.

Concept rows use horizontal padding (10pt), vertical padding (11pt) and the control radius. Default rows are transparent, hovered rows use paper, and selected rows use selection. Selected titles become semibold; selected state takes precedence over hover. Ordered-unit numbers use monospaced digits (10pt) in a fixed column (19pt). Favorite and understood icons use moss. The review section omits summaries for every queue row. Selection is exposed to accessibility.

### Progressive Reading

The concept title, optional English name and leading explanation precede the analogy. Technical detail and source context are collapsed on a newly selected entry and use native DisclosureGroup controls. Empty technical detail (including whitespace-only detail and caveats) has no disclosure. The rule beneath technical detail leaves 24pt before the note card. Caveats use note paper, the button radius and callout-inset padding, with a rust heading. Reading text remains selectable. Source links appear only when a stored URL exists; built-in user-note examples identify their unverified source context.

### Related-Concept Links

Compact plain buttons use the index surface, moss text, chip radius and the fine concept-link stroke. Their label uses medium system text (12pt), an arrow symbol (9pt), internal spacing (7pt), horizontal padding (11pt) and vertical padding (8pt). Labels may wrap to two lines. The surrounding flow preserves intrinsic width and the concept-gap token.

### Personal-Note Card

The note card uses note paper, the note radius and card-inset padding. The native NSTextView editor has a bounded height (110pt), 14pt system text and 5pt added line spacing. Placeholder and input use the same text container origin (0pt horizontal, 6pt vertical inset); the placeholder appears only when empty and unfocused, so it never collides with the caret. Dirty drafts show “尚未保存” and remain cached by entry when navigating. Save is disabled when unchanged, conflicted, already saving or in trash; the editor is disabled in trash.

If an external revision changes the note while a draft is dirty, keep the draft, show the latest note on request and offer “使用最新理解” or “保留我的草稿”. Saving stays disabled until that choice resolves the conflict. An unrelated revision can advance the observed revision without discarding the draft.

### Focused Reading

The book button in the reader header and ⌘⇧L toggle a single centered reading column at the existing maximum measure (700pt). Sidebar and concept index are removed from layout; returning restores the same selected section and entry. The focused header retains an explicit “返回词库” action, quiet source context, previous/next controls and a more menu. Edit, favorite and history actions move into that menu, and the mastery badge is omitted. Header insets shrink to 12pt above and 10pt below. Notes are disclosed on demand; dirty drafts remain visible and are retained through mode and entry switches. ⌘F leaves focus mode and focuses entry search. Recall remains a separate mode and continues to conceal answers. Focus mode is a transient presentation choice; reading positions continue to use the existing per-library preferences.

### Reading Continuity

The default workspace opens the complete library rather than a fixed seed collection. The last section and selected entry per section are stored in system preferences, scoped by a UUID held in the library metadata. Reader scroll offsets and technical/source disclosure states are stored per section and entry, with a maximum of 500 positions. Deleted or missing selections fall back to the first valid result. Restoration locates a bounded 60-entry page around the selected ID; previous pages remain available. Native scroll tracking coalesces preference writes for 200ms, flushes on termination, and clamps offsets to the current document height after layout. No machine path, account or seed entry is part of this state.

### Collection Path and Recall

Path positions use rule at rest and accent for the selected concept. Each marker has an accessible unit label and remains a plain native button. Previous and next controls appear in the reading header and footer for all lists. ⌘↑ and ⌘↓ switch entries using the current list order and filters; collection reading retains its article path when unfiltered. Reaching the loaded boundary fetches the next bounded page. The load-more control is centered in the index and uses 11pt text.

The supplied recall capture shows the concept identity, source context and a “看看解释” action before the answer. The queue remains title-only in review.

**The Recall Before Reveal Rule.** The review queue shows titles without summaries. Keep answer content behind the explicit reveal action in the reading pane.

### Workspace Feedback

Opening the library uses a native progress view. Empty library and trash states use ContentUnavailableView; only the library state offers first-concept creation. A confirmation toast uses an ink Capsule with paper text, horizontal padding (18pt), vertical padding (12pt) and bottom offset (22pt); it does not intercept input. Failures use the native “这次操作没有完成” alert with acknowledgement and refresh actions. Editing, import, agent connection and history use native sheets.

When the trash is empty, the reader owns the single empty-state message. The index retains its heading and global library actions, but omits zero counts, the disabled clear button, search, filters, list placeholder and reading footer. When trash contains entries, search and clear controls return; filtered no-results is distinct from an empty trash and offers clearing the filters.

## Do's and Don'ts

### Do

- Do use the paired adaptive palette, including the current secondary text token.
- Do keep Songti concept titles and explanations alongside native system reading text and SF Symbols.
- Do lead with the plain-language explanation and disclose technical detail and source context progressively.
- Do let concept links wrap at their natural width with 8pt horizontal and vertical gaps.
- Do preserve native focus and keyboard behavior, accessible icon labels, retained note drafts and conflict choices.
- Do preserve 60-entry pagination and the maximum 24-position collection path.

### Don't

- Don't stretch related-concept tags into equal-width grid cells.
- Don't expose summary answers in the review queue.
- Don't add decorative gradients, glows, backgrounds or motion to the reading workspace.
- Don't invent article links or turn user-provided notes into verified quotations.
- Don't replace a dirty personal-note draft when the entry refreshes.
