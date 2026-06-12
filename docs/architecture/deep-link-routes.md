# Deep-Link Routes

Reference catalog of every URL pattern the iOS app handles via `.onOpenURL`. Two delivery surfaces feed the same dispatch:

- **Custom-scheme URLs** (`cabinetdoor://…`) — registered URL scheme, used by widgets, intents, and other in-device clients.
- **Universal links** (`https://epac.riddimsoftware.com/…`) — associated-domain entitlements, used by web shares, email, and SMS.

Both surfaces land in `ContentView` (`ios/epac/Views/ContentView.swift`):

- `handleCustomScheme(_:)` → dispatches via `customSchemeHandlers[host]`
- `handleUniversalLink(_:)` → dispatches via `universalLinkHandlers[segments.first ?? "app"]`

Each entry below has a stable **route ID** (used as the screenshot name in regression evidence plans), a URL pattern, the resulting in-app state change, and the expected user-visible surface.

## Custom-scheme routes (`cabinetdoor://`)

| Route ID | URL pattern | Handler | Resulting state | Surface |
|---|---|---|---|---|
| `cs-member` | `cabinetdoor://member/{id}` | `handleMemberCustomScheme` | `navigateToMember(memberID: id)` — selectedTab=`.members`, pushes MP profile | Members tab → MP profile |
| `cs-vote` | `cabinetdoor://vote/…` | `handleVoteCustomScheme` | `selectedTab = .accountability` | Accountability tab |
| `cs-sitting` | `cabinetdoor://sitting/{yyyy-MM-dd}` | `handleSittingCustomScheme` | Rebuilds path-form URL, hands to `viewModel.onOpenURL`, sets `selectedTab = .parliament` | Parliament tab @ sitting date |
| `cs-event` | `cabinetdoor://event/{yyyy-MM-dd}` | `handleSittingCustomScheme` (alias) | Same as `cs-sitting` | Parliament tab @ sitting date |
| `cs-unrecognized` | `cabinetdoor://<unknown-host>/…` | nil dispatch — `customSchemeHandlers[host]?(url)` no-op | No state change | Wherever the app already was (in evidence mode: Home) |

## Universal-link routes (`https://epac.riddimsoftware.com/`)

| Route ID | Path pattern | Handler | Resulting state | Surface |
|---|---|---|---|---|
| `ul-member` | `/member/{id}` | `handleMemberUniversalLink` | `navigateToMember(memberID: id)` | Members tab → MP profile |
| `ul-vote` | `/vote/{parl}-{sess}/{num}` | `handleVoteUniversalLink` | `pendingSearchQuery = joined segments`, `selectedTab = .search` | Search tab with vote ref pre-filled |
| `ul-bill` | `/bill/{number}` | `handleBillUniversalLink` | `pendingSearchQuery = number`, `selectedTab = .search` | Search tab with bill number pre-filled |
| `ul-sitting` | `/sitting/{yyyy-MM-dd}` | `handleSittingUniversalLink` | `viewModel.onOpenURL(url)`, `selectedTab = .parliament` | Parliament tab @ sitting date |
| `ul-speech` | `/speech/…` | `handleSpeechUniversalLink` | `selectedTab = .parliament` | Parliament tab |
| `ul-topic` | `/topic/{slug}` | `handleTopicUniversalLink` | `pendingSearchQuery = searchQuery(fromWebSlug: slug)`, `selectedTab = .search` | Search tab with topic query |
| `ul-topics` | `/topics/{slug}` | `handleTopicUniversalLink` (alias) | Same as `ul-topic` | Search tab with topic query |
| `ul-riding` | `/riding/{slug}` | `handleRidingUniversalLink` | `pendingSearchQuery = searchQuery(fromWebSlug: slug)`, `selectedTab = .search` | Search tab with riding query |
| `ul-ridings` | `/ridings/{slug}` | `handleRidingUniversalLink` (alias) | Same as `ul-riding` | Search tab with riding query |
| `ul-setup-postal-code` | `/setup/postal-code` | `handleSetupUniversalLink` | `pendingShowPostalCodeSetup = true`, `selectedTab = .home` | Home tab + postal-code setup sheet |
| `ul-app-legacy` | `/app?date=…&subjectID=…` | `handleAppUniversalLink` (legacy branch) | `viewModel.onOpenURL(url)` (legacy date/subject routing) | Parliament tab @ date / subject |
| `ul-app-encoded-path` | `/app?path=…` | `handleAppUniversalLink` (recursive branch) | Decodes `path` query item, recurses through `handleUniversalLink` | Whatever the encoded path resolves to |
| `ul-unknown-fallback` | `/<anything-else>` | nil dispatch in `universalLinkHandlers` | `selectedTab = .home` | Home tab (safe fallback) |

## Asymmetric behaviors worth pinning

These are quiet semantic differences between handlers that are easy to break in a switch-to-dispatch refactor. Regression plans should include scenes that exercise each one so the asymmetry is detected if it ever drifts:

- **`vote` and `bill`** set `selectedTab = .search` **unconditionally**, including when the URL has no payload (`/vote`, `/bill`). The query may be empty but the tab still flips.
- **`topic` and `riding`** set `selectedTab = .search` **only when a slug is present** (`/topic/foo` switches; `/topic` does not). This is intentional — bare `/topic` is treated as malformed and falls through to no-op without changing tab.
- **`event` alias** must read `url.host?.lowercased()` inside `handleSittingCustomScheme` (not capture from the call site) so both `cabinetdoor://sitting/2024-09-16` and `cabinetdoor://event/2024-09-16` rebuild the path-form URL with the correct host segment.
- **`/app` and empty path** are coerced to the same handler: `segments.first ?? "app"`. A URL with no path (e.g. `https://epac.riddimsoftware.com/`) routes through `handleAppUniversalLink`, not the unknown-fallback path.
- **Encoded-path recursion** in `handleAppUniversalLink` parses `?path=…`, rebuilds the URL with that path on the same host, and re-enters `handleUniversalLink`. A malformed `path` value falls through to legacy `viewModel.onOpenURL`.

## What changed in EPAC-1985

PR [#542](https://github.com/RiddimSoftware/epac/pull/542) (EPAC-1985, merged 2026-05-24) decomposed two large `switch` statements into two dispatch tables:

- `customSchemeHandlers: [String: (URL) -> Void]` — host → handler
- `universalLinkHandlers: [String: ([String], URL) -> Void]` — route segment → handler

Plus 11 new private handler methods (one per route) and 2 typealiases. The refactor's explicit contract is *behavior preservation*: every URL that resolved to a surface before the refactor still resolves to the same surface after.

The 18 routes in the tables above are the complete enumeration of routing behavior that the refactor is asserted to preserve. Regression evidence for this PR must show before/after equivalence for every route.

## How route IDs map to regression evidence

The route ID is used as the screenshot name in `.evidence/*.json` plans. For PR-542 specifically:

- `.evidence/pr-542.json` contains 18 scenes, one per route ID.
- Each scene: cold-launch the app with `EPAC_EVIDENCE_MODE=1` for determinism, `simctl openurl` the route's URL, brief settle wait, screenshot named `{route-id}.png`.
- `evidence capture-pr` runs the plan against the merge commit and its first parent, writing `docs/build-evidence/pr-542/before/{route-id}.png` and `…/after/{route-id}.png`.
- The regression assertion is: **for every route ID, `before/{id}.png` and `after/{id}.png` are pixel-identical**, modulo dynamic content masked by `EPAC_EVIDENCE_MODE` (in-memory store, no network re-fetch, suppressed onboarding/setup sheets).

## Determinism scaffolding already in the app

`AppEnvironment.isEvidenceCaptureMode` (`ios/epac/Util/AppEnvironment.swift`) is true when either `--evidence-mode` is in the launch arguments or `EPAC_EVIDENCE_MODE=1` is set. It flows into `isMarketingCaptureMode` and produces the following deterministic behaviors:

- `ModelContainer` uses an in-memory store (`ios/epac/epacApp.swift:38`)
- Onboarding sheet suppressed (`ios/epac/Views/ContentView.swift:30`)
- MyMP postal-code setup sheet suppressed at launch (`ios/epac/Views/ContentView.swift:29`)
- `selectedTab` defaults to `.home` (`ios/epac/Util/NavigationRouter.swift:54`)
- App-open registration tasks skipped (`ios/epac/epacApp.swift:52`, `:84`, `ios/epac/Views/ContentView.swift:90`)

Routes that activate the postal-code setup sheet (`ul-setup-postal-code`) deliberately exercise the path that *would* present that sheet — the deep-link itself sets `pendingShowPostalCodeSetup = true`, distinct from the launch-default suppression.
