# Provincial Hansard Adapter Scaffold

Each provincial Hansard adapter implements `HansardRepository` for exactly one
`Jurisdiction` and lives under:

`ios/epac/Data/Adapters/Hansard/<Province>HansardAdapter.swift`

The adapter is responsible for source-specific delivery details only. The
application layer calls `JurisdictionRoutedHansardRepository`, which dispatches
requests by jurisdiction.

## Transport

Fetch only from the province's authoritative Hansard source. Keep URL building,
HTTP status handling, retry policy, and source metadata inside the adapter or a
small province-local helper. If multiple provinces need the same HTTP client
shape after the first implementation lands, extract it then; do not add a shared
network abstraction before there are two real callers.

## Parsing

Return `HansardTranscript` with stable `SubjectOfBusinessRecord` and
`SpeechMessageRecord` values. Reuse `HTMLHansardScaffold` for HTML-only sources
such as Nova Scotia, Manitoba, and Saskatchewan when its default transcript,
subject, speech, and whitespace helpers fit. For PDF or XML sources, write the
smallest province-local parser that preserves source IDs and source text.

## Speaker Resolution

Use `HansardSpeakerParser` for common speaker prefixes before mapping a speaker
line to the province's member list. The Quebec adapter can rely on the parser's
French prefixes (`L'hon.`, `L’hon.`, `Mme`, `M.`), but member identity still
belongs to the province-specific adapter because each legislature publishes a
different member list and stable identifier shape.

## Sitting Calendar Discovery

Implement `listSittingDates(jurisdiction:from:through:)` from the province's
authoritative sitting calendar or Hansard index. The returned dates must be
filtered to the requested range and sorted before returning. If a province has
only per-day Hansard pages and no separate calendar endpoint, document that in
the adapter and derive the date list from the source index.

## Boundary Rule

Files matching `ios/epac/Data/Adapters/Hansard/**/*Adapter.swift` must not
import `SwiftUI`, `SwiftData`, or `UIKit`. If an adapter needs UI state or
persistence, move that concern to a repository, ViewModel, or another outer
layer and keep the adapter focused on transport and parsing.
