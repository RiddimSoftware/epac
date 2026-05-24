# Journey Catalogue — Schema & Conventions

This document defines the folder layout, tag vocabulary, and authoring conventions for the user-journey catalogue living under `docs/journeys/`.

---

## Folder layout

```
docs/journeys/
  <tab>/                        # one directory per tab (see @tab: enum below)
    <feature-slug>.feature      # one .feature file per screen or feature area
  cross-cutting/                # flows that span multiple tabs
    <feature-slug>.feature
```

### Tab directories (fixed enum)

| Directory | Tab |
|---|---|
| `home/` | Home tab |
| `parliament/` | Parliament tab |
| `members/` | Members tab |
| `accountability/` | Accountability tab |
| `search/` | Search tab |
| `cross-cutting/` | Cross-cutting flows (multi-tab journeys) |

Every `.feature` file must live in exactly one of these directories. The `@tab:` tag value must match the parent directory name.

---

## Tag vocabulary

All tags appear on individual **Scenarios** (not on the `Feature:` block).

### Required tags — exactly one of each per Scenario

| Tag | Format | Description |
|---|---|---|
| `@tab:<value>` | enum (see below) | Which tab this scenario belongs to. Must match the parent folder name. |
| `@screen:<slug>` | kebab-case string | Identifies the specific screen within the tab. |
| `@state:<value>` | enum (see below) | The UI state class this scenario exercises. |

### Optional tags — zero or more per Scenario

| Tag | Format | Description |
|---|---|---|
| `@ticket:EPAC-<N>` | `EPAC-` followed by digits | Links the scenario to its implementing Jira ticket. |
| `@pr:<N>` | digits or `<owner>/<repo>#<N>` | Links the scenario to a pull request. |
| `@legacy` | flag | Marks scenarios that predate ticket tracking; suppresses the missing-ticket warning. |
| `@draft` | flag | Marks scenarios still being authored; suppresses the missing-ticket warning. |

---

## Controlled vocabulary

### `@tab:` (fixed enum)

```
home
parliament
members
accountability
search
cross-cutting
```

New values require updating this schema and the lint script together in the same PR.

### `@state:` (extensible starting set)

| Value | Meaning |
|---|---|
| `loading` | Data is being fetched; skeleton or spinner visible |
| `loaded` | Data fetched successfully; full content visible |
| `empty` | Fetch succeeded but returned zero results |
| `error` | Fetch failed with a recoverable error |
| `offline` | No network connection detected |
| `rate-limited` | API rate limit hit; back-off UI shown |

New state values may be added by any PR; update this table alongside the change.

---

## Authoring conventions

- **One Scenario per (screen × state class).** Each combination of `@screen:` and `@state:` should appear in at most one Scenario per `.feature` file.
- **`@screen:` must be kebab-case** — lowercase letters, digits, and hyphens only (e.g. `home-feed`, `mp-profile`, `bill-detail`).
- **`@ticket:` and `@pr:` are zero-or-more** — a Scenario may link to multiple tickets or PRs by repeating the tag.
- Scenarios without `@ticket:EPAC-<N>` and without `@legacy` emit a lint **warning** (not an error), unless `@draft` is present.
- The `Feature:` block should describe the screen or flow area in plain English; tags belong on Scenarios only.

---

## Example

```gherkin
Feature: Home feed

  @tab:home @screen:home-feed @state:loaded @ticket:EPAC-560
  Scenario: Renders feed cards when data has loaded
    Given the app has fetched feed data successfully
    When I open the Home tab
    Then I see a list of feed cards

  @tab:home @screen:home-feed @state:loading
  Scenario: Shows skeleton while feed data is loading
    Given the app has not yet received feed data
    When I open the Home tab
    Then I see skeleton placeholder cards

  @tab:home @screen:home-feed @state:empty @ticket:EPAC-560
  Scenario: Shows empty-state illustration when feed is empty
    Given the API returned an empty feed list
    When I open the Home tab
    Then I see the empty-state illustration and message
```
