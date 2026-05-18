# S3 Artifact Migration Plan (EPAC-1905)

**Status:** Design spike — not yet implemented  
**Parent project:** [epac: Retire Aurora](https://linear.app/riddimsoftware/project/epac-retire-aurora-by-moving-to-s3cloudfront-9fcb458f1570)  
**Date:** 2026-05-17

## Summary

This document catalogues every Postgres-bound backend endpoint and Python statistics pipeline, then designs the S3 artifact schema each will publish to after Aurora is retired. It is the primary input for the four backend migration issues.

**Total estimated S3 storage (all artifacts, gzipped):** ~90–150 MB  
**Maximum single-artifact size (gzipped):** ~200 KB per riding boundary file (338 ridings total); ~40 KB for the largest speech-per-member file  
**Endpoints requiring design work before migration:** `/api/v1/on-this-day` (ranking bakes in current-MP state at publish time — see §6), `/api/v1/ridings/{slug}/boundary` (needs a new pre-build pipeline — see §9), `/api/v1/sittings/{date}/speeches` (corpus size decision — see §5)

---

## Implementation status key

| Symbol | Meaning |
|---|---|
| ✅ Lambda deployed | Lambda exists and is wired to API Gateway in production |
| ⚠️ Lambda unrouted | Lambda code exists but not wired to API Gateway (staging or production) |
| 🔷 iOS direct | No backend Lambda; iOS fetches the data directly from the government source |
| 🚫 Out of scope | Excluded from this migration |

---

## Out of migration scope

| Endpoint | Reason |
|---|---|
| `GET /api/v1/live` | Being removed entirely — live session polling is not S3-compatible |
| `POST /api/v1/device/register` | Being removed — push notification device registry is not a static artifact |
| `GET /search` | Dead code — no iOS, website, or dashboard callers |
| `GET /search/speeches` | Dead code — no iOS, website, or dashboard callers |

These four endpoints have no S3 artifact equivalent and will be decommissioned alongside Aurora.

---

## 1. `GET /api/v1/members` — MP list 🔷 (iOS direct today → backend planned)

**Current implementation status:** No backend Lambda. iOS `Fetch.swift` calls `https://www.ourcommons.ca/Members/en/search/XML?parliament=all&caucusId=all` directly and parses the XML response.

**Postgres tables:** `members` (populated by `backend/loader` from ourcommons.ca XML)  
**Primary query:**
```sql
SELECT person_id, honorific, first_name, last_name,
       constituency AS riding, province, caucus AS party,
       from_date, to_date
FROM members
WHERE to_date IS NULL   -- current MPs only (optionally relaxed)
ORDER BY last_name, first_name
```
Optional filters: `province` (equality), `party`/`caucus` (equality).

**Current response payload shape:**
```json
{
  "members": [
    {
      "id": "278707",
      "name": "Jane Example",
      "riding": "Ottawa Centre",
      "province": "ON",
      "party": "Liberal",
      "source_url": "https://www.ourcommons.ca/members/en"
    }
  ]
}
```

**Estimated corpus size:**  
338 current MPs × ~400 bytes/record = ~135 KB uncompressed; **~25 KB gzipped**

**Update frequency:** Weekly (members change on election, resignation, by-election)  
**Update trigger:** `members-sync` pipeline run (168-hour expected interval, `pipeline_health` seeded)  
**Pipeline transition:** `backend/loader --members` currently loads from ourcommons.ca XML into Postgres. Post-migration it publishes `members/v1/all.json` to S3 directly after the same XML parse step.

**Proposed S3 key layout:**
```
members/v1/all.json                  # all current MPs, ~25 KB gzipped
members/v1/all-with-history.json     # all MPs including historical, ~80 KB gzipped
```
Client-side province/party filtering is trivially fast on 338 records. No per-province or per-party sharding needed.

**Proposed JSON schema:** Matches `#/components/schemas/MembersResponse` in `backend/openapi/openapi.json`. No structural changes needed.

**iOS consumer service:** `ios/epac/Model/Fetch.swift` (`members()` method) — will be redirected from ourcommons.ca XML to S3 JSON.

---

## 2. `GET /api/v1/members/{id}/speeches` — Member speech history ✅

**Lambda directory:** `backend/member-speeches`  
**Postgres tables:** `speeches`  
**Primary query:**
```sql
-- Paginated (current Lambda)
SELECT intervention_id, sitting_date, parliament_num, session_num,
       subject_title, content, word_count, filename
FROM speeches
WHERE member_id = $1 [AND subject_title ILIKE $2]
ORDER BY sitting_date DESC NULLS LAST, intervention_seq ASC
LIMIT $3 OFFSET $4

-- Stats (always over full history)
SELECT COUNT(*), COALESCE(AVG(word_count)::int, 0) FROM speeches WHERE member_id = $1
SELECT subject_title FROM speeches WHERE member_id = $1 ... GROUP BY subject_title ORDER BY COUNT(*) DESC LIMIT 1
```

**Current response payload shape:**
```json
{
  "member_id": "278707",
  "page": 1,
  "per_page": 20,
  "total": 142,
  "pages": 8,
  "stats": { "total_speeches": 142, "avg_word_count": 215, "top_topic": "Housing" },
  "speeches": [
    {
      "id": "12345678",
      "sitting_date": "2026-04-27",
      "parliament_num": 45,
      "session_num": 1,
      "subject_title": "Housing",
      "preview": "Madam Speaker, housing affordability matters...",
      "word_count": 312,
      "filename": "HAN001-E.XML"
    }
  ]
}
```

**Per-member vs combined tradeoff:**

| Option | Artifact size | iOS download | Notes |
|---|---|---|---|
| Per-member file (`by-member/{id}.json`) | ~200 KB uncompressed / ~40 KB gzipped per MP | Fetch only needed member | 338 files × 40 KB = ~13 MB total |
| Single combined (`all-speeches.json`) | ~100 MB uncompressed / ~15 MB gzipped | Must download full corpus | Impractical for mobile |

**Decision: per-member files.** One artifact per member containing all speeches (unpaginated) plus embedded stats. iOS loads on first member-profile tap, then caches locally via SwiftData. The current pagination structure exists only to manage Lambda/DB query cost; S3 removes that constraint.

**Estimated corpus size:** ~13 MB gzipped across 338 files  
**Max single artifact:** ~40 KB gzipped (active MPs with long Hansard histories)

**Update frequency:** On-sitting (new speeches ingest daily after Hansard publishes)  
**Update trigger:** `daily-fetch` Lambda currently upserts speeches into Postgres; post-migration it publishes each updated member's artifact after ingest.

**Proposed S3 key layout:**
```
speeches/v1/by-member/{member_id}.json   # full history, all speeches + stats
speeches/v1/member-index.json            # lightweight index: member_id → total_speeches, top_topic
```

**Proposed artifact JSON schema** (explicit — `MemberSpeechesResponse` is incompatible because it requires `page`, `per_page`, `pages`, `total`):
```json
{
  "member_id": "string (required)",
  "stats": {
    "total_speeches": "integer (required)",
    "avg_word_count": "integer (required)",
    "top_topic": "string (required)"
  },
  "speeches": [
    {
      "id": "string (required)",
      "sitting_date": "string | null (date)",
      "parliament_num": "integer | null",
      "session_num": "integer | null",
      "subject_title": "string | null",
      "preview": "string (required)",
      "word_count": "integer | null",
      "filename": "string (required)"
    }
  ]
}
```
Matches `#/components/schemas/MemberStats` for the `stats` field and `#/components/schemas/MemberSpeech` for each array entry. Pagination fields (`page`, `per_page`, `pages`, `total`) are absent — the artifact is always the complete speech history.

**iOS consumer service:** `ios/epac/Util/MemberSpeechService.swift`

---

## 3. `GET /api/v1/members/{id}/votes` — MP voting record 🔷 (iOS direct today → backend planned)

**Current implementation status:** No backend Lambda. iOS `Fetch.swift` calls `https://www.ourcommons.ca/ocd/members/{member_id}/votes/` and related endpoints directly.

**Postgres tables:** None currently. `pipeline_health` seeds a `votes-sync` entry (24-hour interval) indicating a votes pipeline is planned.

**Current response payload shape:**
```json
{
  "member_id": "278707",
  "page": 1,
  "per_page": 20,
  "total": 87,
  "votes": [
    {
      "vote_id": "1234",
      "date": "2026-04-27",
      "bill_number": "C-1",
      "summary": "An Act respecting example data",
      "vote": "Yea",
      "source_url": "https://www.ourcommons.ca/members/en/votes"
    }
  ]
}
```

**Estimated corpus size:** 338 MPs × ~50 votes each × 300 bytes = ~5 MB uncompressed; **~600 KB gzipped** across all files

**Update frequency:** Daily (votes recorded per sitting day)  
**Update trigger:** `votes-sync` pipeline (not yet implemented — cron daily)

**Proposed S3 key layout:**
```
votes/v1/by-member/{member_id}.json    # all votes for one MP (complete, unpaginated)
votes/v1/vote-index.json               # all votes metadata for cross-MP lookup
```

**Proposed artifact JSON schema** (explicit — `MemberVotesResponse` requires `page`, `per_page`, `total` which the artifact omits):
```json
{
  "member_id": "string (required)",
  "votes": [
    {
      "vote_id": "string (required)",
      "date": "string (required, date)",
      "bill_number": "string | null",
      "summary": "string | null",
      "vote": "string (required, enum: Yea | Nay | Paired | Absent)",
      "source_url": "string | null (uri)"
    }
  ]
}
```
Each `votes` entry matches `#/components/schemas/Vote`. Pagination fields are absent.

**iOS consumer service:** `ios/epac/Model/Fetch.swift` (votes-related methods)

---

## 4. `GET /api/v1/sittings` — Sitting list 🔷 (iOS direct today → backend planned)

**Current implementation status:** No backend Lambda. iOS `Fetch.swift` calls the ourcommons.ca sitting calendar HTML directly and parses dates from it. The `live_sitting_day` Postgres table caches the annual calendar (populated by `live-status` Lambda).

**Postgres tables:** `live_sitting_day` (annual calendar cache); `speeches` (distinct `sitting_date` values for confirmed past sittings)

**Primary query (proposed):**
```sql
SELECT DISTINCT sitting_date, parliament_num, session_num,
       filename  -- to derive sitting_num and source_url
FROM speeches
ORDER BY sitting_date DESC
```

**Current response payload shape:**
```json
{
  "page": 1,
  "per_page": 20,
  "total": 847,
  "sittings": [
    {
      "date": "2026-04-27",
      "parliament_num": 45,
      "session_num": 1,
      "sitting_num": 1,
      "source_url": "https://www.ourcommons.ca/documentviewer/en/45-1/house/sitting-1/hansard"
    }
  ]
}
```

**Estimated corpus size:** ~1,000 sittings × 250 bytes = ~250 KB uncompressed; **~30 KB gzipped**

**Update frequency:** Daily (new sittings added as Hansard publishes)  
**Update trigger:** `daily-fetch` Lambda — publish after each Hansard ingest

**Proposed S3 key layout:**
```
sittings/v1/all.json    # complete sitting list, unpaginated (~30 KB gzipped)
```

**Proposed artifact JSON schema** (explicit — `SittingsResponse` requires `page`, `per_page`, `total` which the artifact omits):
```json
{
  "sittings": [
    {
      "date": "string (required, date)",
      "parliament_num": "integer | null",
      "session_num": "integer | null",
      "sitting_num": "integer | null",
      "source_url": "string (required, uri)"
    }
  ]
}
```
Each `sittings` entry matches `#/components/schemas/Sitting`. Pagination fields are absent.

**iOS consumer service:** `ios/epac/Model/Fetch.swift` (`sittingDates()` / calendar methods)

---

## 5. `GET /api/v1/sittings/{date}/speeches` — Speeches for a sitting date 🔷 (no Lambda; data in speeches table → publish to S3)

**Current implementation status:** No dedicated Lambda, but the data lives in the `speeches` Postgres table populated by `daily-fetch`. This endpoint is listed in the OpenAPI spec as planned; the data would be served from the same `speeches` table.

**Postgres tables:** `speeches`  
**Primary query (proposed):**
```sql
SELECT intervention_id, speaker_name, member_id,
       subject_title, content, source_url
FROM speeches
WHERE sitting_date = $1
ORDER BY intervention_seq ASC
```

**Current response payload shape:**
```json
{
  "date": "2026-04-27",
  "page": 1,
  "per_page": 20,
  "total": 187,
  "speeches": [
    {
      "id": "12345678",
      "speaker_name": "Example MP",
      "member_id": "278707",
      "subject_title": "The Economy",
      "content": "Madam Speaker, ...",
      "source_url": "https://www.ourcommons.ca/documentviewer/en/45-1/house/sitting-1/hansard"
    }
  ]
}
```

**Per-date size analysis:**

| Granularity | File count | Avg size (gzipped) | Total |
|---|---|---|---|
| Per sitting date | ~1,000 dates | ~60 KB/file | ~60 MB |
| All speeches combined | 1 file | ~15 MB | ~15 MB |

**Decision: per-date files.** iOS loads one date at a time when displaying a sitting's Hansard. The 60 KB per-file payload is appropriate for mobile. The combined 60 MB total is manageable for S3 but would be prohibitive as a single download. iOS can prefetch recent dates and cache indefinitely (Hansard does not change after publication).

**Estimated corpus size:** ~60 MB gzipped total  
**Max single artifact:** ~120 KB gzipped (a very full sitting day with 300+ interventions)

**Update frequency:** On-sitting (once per sitting day, after Hansard publishes)  
**Update trigger:** `daily-fetch` Lambda publishes the sitting's artifact on successful ingest

**Proposed S3 key layout:**
```
sittings/v1/by-date/{YYYY-MM-DD}.json    # all speeches for one sitting date
```

**Proposed artifact JSON schema** (explicit — `SpeechesResponse` requires `page`, `per_page`, `total` which the artifact omits):
```json
{
  "date": "string (required, date)",
  "speeches": [
    {
      "id": "string (required)",
      "speaker_name": "string | null",
      "member_id": "string | null",
      "subject_title": "string | null",
      "content": "string | null",
      "source_url": "string | null (uri)"
    }
  ]
}
```
Each `speeches` entry matches `#/components/schemas/Speech`. Pagination fields are absent; the artifact contains all interventions for the sitting date.

**iOS consumer service:** `ios/epac/Model/Fetch.swift` (Hansard sitting fetch methods); `ios/epac/Views/Calendar/SittingCalendarViewModel.swift`

---

## 6. `GET /api/v1/on-this-day` — Historical Parliament moments ✅

**Lambda directory:** `backend/on-this-day`  
**Postgres tables:** `speeches`, `members`  
**Primary query:**
```sql
SELECT intervention_id, EXTRACT(YEAR FROM sitting_date)::int, sitting_date,
       speaker_name, subject_title, content, member_id, source_url
FROM speeches
LEFT JOIN members ON speeches.member_id = members.person_id
WHERE EXTRACT(MONTH FROM sitting_date) = EXTRACT(MONTH FROM $1::date)
  AND EXTRACT(DAY FROM sitting_date) = EXTRACT(DAY FROM $1::date)
  AND sitting_date < $1::date
ORDER BY (to_date IS NULL) DESC,  -- current MPs ranked first
         sitting_date DESC, intervention_seq ASC
LIMIT $2
```

**Current response payload shape:**
```json
{
  "date": "2026-04-29",
  "items": [
    {
      "id": "speech:12345678",
      "kind": "speech",
      "year": 2021,
      "date": "2021-04-29",
      "title": "Housing",
      "excerpt": "Madam Speaker, housing affordability matters...",
      "speaker_name": "Jane Example",
      "member_id": "278707",
      "subject_title": "Housing",
      "intervention_id": "12345678",
      "source_url": "https://www.ourcommons.ca/documentviewer/en/44-1/house/sitting-1/hansard"
    }
  ]
}
```

**EPAC-1916 implementation note:** The publisher writes one full ranked historical index. The Lambda filters the artifact by month/day and applies the request `limit`, so the API response shape stays unchanged while request-time Postgres reads are removed.

**Estimated corpus size:** 366 calendar days × top-20 items × ~500 bytes = ~3.7 MB uncompressed; **~800 KB gzipped** total

**Update frequency:** Daily during sitting season; on-member-change for re-ranking  
**Update trigger:** `publish-artifacts` regenerates the full index from Aurora; members sync or Hansard ingest changes trigger a fresh publish

**Proposed S3 key layout:**
```
on-this-day/v1/all.json    # full ranked historical index, filtered by Lambda
```

**Proposed JSON schema:** `{ "items": [...] }`, where each item matches `#/components/schemas/OnThisDayItem`. The Lambda wraps filtered items in `OnThisDayResponse`.

**iOS consumer service:** Removed from Home in EPAC-1933; the backend endpoint and publisher remain until separately retired.

---

## 7. `GET /api/v1/bills` — Bill list 🔷 (iOS direct today → backend planned)

**Current implementation status:** No backend Lambda. iOS `BillsService.swift` calls `https://www.parl.ca/legisinfo/en/bills/json?parlsession={parliament}-{session}&load=yes` directly and parses the LegisInfo JSON.

**Postgres tables:** None currently. `pipeline_health` seeds a `bills-sync` entry (24-hour interval) indicating a bills pipeline is planned.

**Current response payload shape:**
```json
{
  "bills": [
    {
      "id": "C-1-45-1",
      "number": "C-1",
      "title": "An Act respecting example data",
      "current_stage": "Second Reading",
      "introduced_on": "2026-04-27",
      "source_url": "https://www.parl.ca/legisinfo/en/bill/45-1/c-1"
    }
  ]
}
```

**Estimated corpus size:** ~100 bills per parliament session × 500 bytes = ~50 KB uncompressed; **~10 KB gzipped**

**Update frequency:** Daily (bill stages advance on sitting days)  
**Update trigger:** `bills-sync` pipeline (not yet implemented — cron daily, or on-sitting)

**Proposed S3 key layout:**
```
bills/v1/by-parliament/{parliament}-{session}.json    # e.g. bills/v1/by-parliament/45-1.json
bills/v1/current.json                                 # symlink-equivalent: latest parliament/session
```

**Proposed JSON schema:** Matches `#/components/schemas/BillsResponse`. No structural changes needed.

**iOS consumer service:** `ios/epac/Util/BillsService.swift`

---

## 8. `GET /api/v1/config` — App configuration and feature flags ✅

**Current implementation status:** EPAC-1916 adds a thin `backend/config` Lambda and publisher. No Postgres table is involved.

**Proposed approach:** A S3 artifact written by the artifact publish workflow. Environment-specific values should be isolated by artifact bucket or prefix, not by changing the response shape.

**Proposed S3 key layout:**
```
config/v1/app.json    # generated on deploy or feature-flag changes
```

**Proposed JSON schema:** Matches `#/components/schemas/AppConfig`:
```json
{
  "minimum_supported_version": "1.0.0",
  "features": {
    "search": false,
    "topic_notifications": true
  }
}
```

**Estimated size:** < 1 KB  
**Update frequency:** Manual (on release or feature-flag change)  
**Update trigger:** `publish-artifacts` workflow

**iOS consumer service:** `ios/epac/Util/BackendConfig.swift` (no dedicated config service today — needs new `AppConfigService.swift`)

---

## 9. `GET /api/v1/ridings/{slug}/boundary` — Riding GeoJSON boundary ✅ (not Postgres today)

**Lambda directory:** `backend/riding-boundary`  
**Current implementation status:** This endpoint does **not** hit Postgres. It is a real-time proxy to `https://represent.opennorth.ca/boundaries/federal-electoral-districts-2023-representation-order/`. The Lambda applies Douglas-Peucker simplification (tolerance 0.00012) at request time and returns GeoJSON.

**Design work required:** The S3 migration requires a new pre-build pipeline that:
1. Fetches all 338 riding boundaries from represent.opennorth.ca
2. Applies the same Douglas-Peucker simplification currently done at Lambda runtime
3. Publishes one JSON file per riding to S3

**Size analysis:**

| Option | Per-file size (gzipped) | 338 files total |
|---|---|---|
| Full-res GeoJSON (unprocessed) | 300 KB – 2 MB | 100 – 670 MB |
| Simplified (tolerance 0.00012, current Lambda) | 20 – 200 KB | 7 – 68 MB |
| Highly simplified (tolerance 0.001) | 5 – 30 KB | 2 – 10 MB |

**Decision:** Publish simplified boundaries at the current tolerance (0.00012) for the default S3 artifact. Add a coarser simplified index for map overview use. Full-res not published.

**Estimated corpus size:** ~68 MB gzipped (upper bound, simplified at current tolerance); likely ~25 MB average  
**Max single artifact:** ~200 KB gzipped for a large multi-polygon urban riding

**Update frequency:** Rare (Representation Orders change ~every 10 years; last was 2023)  
**Update trigger:** Manual re-publish when Elections Canada releases updated boundary files

**Proposed S3 key layout:**
```
ridings/v1/index.json                     # all 338 riding slugs, names, external_ids (~15 KB)
ridings/v1/boundary/{slug}.json           # simplified boundary per riding (~20-200 KB)
```

**Proposed JSON schema:** Matches `#/components/schemas/RidingBoundary` in OpenAPI. No structural changes. Pre-built `source_note`, `representation_order`, `extent`, and `centroid` are computed at publish time rather than at Lambda runtime.

**iOS consumer service:** `ios/epac/Util/RidingBoundaryService.swift`

---

## 10. `GET /api/v1/estimates` and `GET /api/v1/estimates/{org_id}` — Main Estimates ⚠️

**Lambda directory:** `backend/estimates`  
**Current implementation status:** Lambda code exists (handles both API GET and ingest trigger in a single handler). Not wired to API Gateway routes in either staging or production Terraform.

**Postgres tables:** `estimates`, `organizations`  
**Primary queries:**
```sql
-- All orgs for a fiscal year
SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number,
       e.vote_description, e.authorities, e.source
FROM estimates e
JOIN organizations o ON e.organization_id = o.id
WHERE e.fiscal_year = $1
ORDER BY o.name, e.vote_number

-- Single org (all years)
SELECT ... WHERE e.organization_id = $1 ORDER BY e.fiscal_year DESC, e.vote_number

-- Single org, single fiscal year
SELECT ... WHERE e.organization_id = $1 AND e.fiscal_year = $2
```

**Current response payload shape:**
```json
{
  "estimates": [
    {
      "fiscal_year": "2024-25",
      "organization_id": 1,
      "organization_name": "Agriculture and Agri-Food Canada",
      "vote_number": 1,
      "vote_description": "Operating expenditures",
      "authorities": 1234567.89,
      "source": "GC InfoBase"
    }
  ]
}
```

**Estimated corpus size:**
- Per fiscal year file: ~5,000 votes × 250 bytes = ~1.25 MB uncompressed; **~200 KB gzipped**
- Per-org all-years: ~300 orgs × ~20 votes × ~5 years × 250 bytes = ~7.5 MB uncompressed; **~800 KB gzipped** total across all org files
- Organizations index: ~300 orgs × 100 bytes = ~30 KB uncompressed; **~5 KB gzipped**

**Update frequency:** Annual (Main Estimates tabled once per fiscal year)  
**Update trigger:** Manual or cron on GC InfoBase CSV update; `main-estimates-ingest` pipeline

**Proposed S3 key layout:**
```
estimates/v1/all.json                 # all organizations and figures
estimates/v1/by-org/{org_id}.json     # all years for one org
```

**Proposed JSON schema:** Matches `#/components/schemas/EstimatesResponse`. The Lambda filters `all.json` by fiscal year and reads `by-org/{org_id}.json` for organization detail.

**iOS consumer service:** None today (Estimates UI not yet shipped). Will need a new `EstimatesService.swift`.

---

## 11. `GET /api/v1/calendar/house.ics` — Sitting calendar iCal feed ✅

**Lambda directory:** `backend/calendar`
**Postgres tables:** None for API reads. The publisher fetches the authoritative House sitting calendar HTML and emits ICS.

**Current response format:** RFC 5545 iCalendar (`text/calendar`), one VEVENT per sitting day

**Estimated artifact size:** ~365 sitting days/year × 200 bytes/VEVENT = ~73 KB per year; **~15 KB gzipped** for the current-year feed

**Update frequency:** Annual (sitting calendar published by Parliament at start of year); on-demand when sittings are added mid-session  
**Update trigger:** `publish-artifacts` workflow publishes the ICS artifact after fetching the authoritative sitting calendar

**Proposed S3 key layout:**
```
calendar/v1/house.ics            # current sitting calendar (RFC 5545)
calendar/v1/house-{year}.ics    # year-specific archive (e.g. calendar/v1/house-2026.ics)
```

**Proposed schema:** RFC 5545 iCalendar format; no structural change from current response. CloudFront serves with `Content-Type: text/calendar`.

**iOS consumer service:** `ios/epac/Util/CalendarExportService.swift`

---

## 12. Python statistics pipelines

All eight pipelines share a common pattern:
- Source: external government data (Statistics Canada, Finance Canada, Veterans Affairs, etc.)
- Output: currently JSON to `stdout` (or `--output <file>`)
- No Postgres reads or writes (except `pbo` which writes to `pbo_publications`)
- **S3 migration:** Replace `sys.stdout.write(body)` (or file write) with `s3.put_object(...)`. The pipelines already accept `--output` to write to a file; the S3 publisher can wrap that with an upload step.

### 12a. `cpi-statistics`

**Source:** Statistics Canada table 18-10-0004-01 (CPI, monthly, not seasonally adjusted)  
**Output shape:**
```json
{
  "generated_at": "2026-05-01T00:00:00Z",
  "source": { "title": "...", "url": "..." },
  "reference_month": "2026-03",
  "national": { "province": "Canada", "province_code": "CA", "all_items_index": 161.1, "months": [...] },
  "provinces": [{ "province": "Alberta", "province_code": "AB", ... }]
}
```
**Estimated size:** ~50 KB uncompressed; **~8 KB gzipped**  
**Update frequency:** Monthly (~3 weeks after reference month)  
**Update trigger:** Cron (monthly); manual re-run on data revision  
**Implemented S3 key layout:** `statistics/v1/cpi-statistics/all.json`, `national.json`, and `province-<code>.json` slice artifacts.
**iOS consumer service:** None today (statistics UI not yet shipped). Will need a `CPIStatisticsService.swift`.

### 12b. `fiscal-monitor`

**Source:** Department of Finance Canada Fiscal Monitor HTML + publication list  
**Output shape:** Array of `FiscalMonitorEntry` objects with monthly revenue/expense data  
**Estimated size:** ~20 KB uncompressed; **~4 KB gzipped**  
**Update frequency:** Monthly  
**Update trigger:** Cron (monthly after Finance Canada publishes)  
**Implemented S3 key layout:** `statistics/v1/fiscal-monitor/all.json`
**iOS consumer service:** `ios/epac/Util/FiscalMonitorService.swift`

### 12c. `cpp-oas-statistics`

**Source:** Statistics Canada (CPP + OAS beneficiary and payment data)  
**Estimated size:** ~30 KB uncompressed; **~5 KB gzipped**  
**Update frequency:** Quarterly  
**Update trigger:** Cron (quarterly)  
**Implemented S3 key layout:** `statistics/v1/cpp-oas-statistics/all.json`, `national.json`, and `province-<code>.json` slice artifacts.
**iOS consumer service:** None today.

### 12d. `ei-statistics`

**Source:** Employment Insurance statistics (Statistics Canada / ESDC)  
**Output shape:** Province-level EI benefit statistics with monthly history  
**Estimated size:** ~40 KB uncompressed; **~6 KB gzipped**  
**Update frequency:** Quarterly
**Update trigger:** Cron (quarterly)
**Implemented S3 key layout:** `statistics/v1/ei-statistics/all.json` and `province-<code>.json` slice artifacts.
**iOS consumer service:** None today.

### 12e. `vac-statistics`

**Source:** Veterans Affairs Canada statistics  
**Estimated size:** ~20 KB uncompressed; **~4 KB gzipped**  
**Update frequency:** Quarterly  
**Update trigger:** Cron (quarterly)  
**Implemented S3 key layout:** `statistics/v1/vac-statistics/all.json`, `national.json`, and `province-<code>.json` slice artifacts.
**iOS consumer service:** None today.

### 12f. `student-finance-statistics`

**Source:** Canadian student financing data  
**Estimated size:** ~20 KB uncompressed; **~4 KB gzipped**  
**Update frequency:** Quarterly
**Update trigger:** Cron (quarterly / manual)
**Implemented S3 key layout:** `statistics/v1/student-finance-statistics/all.json` and `province-<code>.json` slice artifacts.
**iOS consumer service:** None today.

### 12g. `corrections-statistics`

**Source:** Corrections Canada statistics  
**Estimated size:** ~20 KB uncompressed; **~4 KB gzipped**  
**Update frequency:** Quarterly
**Update trigger:** Cron (quarterly / manual)
**Implemented S3 key layout:** `statistics/v1/corrections-statistics/all.json`
**iOS consumer service:** None today.

### 12h. `transport-safety-statistics`

**Source:** Transport Canada safety data  
**Estimated size:** ~20 KB uncompressed; **~4 KB gzipped**  
**Update frequency:** Quarterly  
**Update trigger:** Cron (quarterly / manual)  
**Implemented S3 key layout:** `statistics/v1/transport-safety-statistics/all.json`, `road-national.json`, and `road-province-<code>.json` slice artifacts.
**iOS consumer service:** None today.

---

## Storage summary

| Artifact group | Files | Estimated gzipped size |
|---|---|---|
| Members (`all.json`) | 1 | 25 KB |
| Member speeches (`by-member/`) | 338 | 13 MB |
| Member votes (`by-member/`) | 338 | 600 KB |
| Sittings (`all.json`) | 1 | 30 KB |
| Sittings speeches (`by-date/`) | ~1,000 | 60 MB |
| On-this-day (`{MM-DD}.json`) | 366 | 800 KB |
| Bills (`by-parliament/`) | ~5 | 50 KB |
| Config | 1 | < 1 KB |
| Riding boundaries (`by-slug/`) | 338 | ~25 MB |
| Estimates (`by-fiscal-year/`) | ~5 | 1 MB |
| Estimates (`by-org/`) | ~300 | 800 KB |
| Calendar ICS | 1 | 15 KB |
| Statistics pipelines (8) | ~70 including province slices | 45 KB |
| **Total** | | **~100 MB** |

---

## `daily-fetch` transition note

`backend/daily-fetch` currently: fetches Hansard XML from ourcommons.ca → parses → upserts into `speeches` Postgres table.

Post-migration it will: fetch → parse → publish the following S3 artifacts:
1. `sittings/v1/by-date/{date}.json` — full speech list for the sitting
2. `sittings/v1/all.json` — regenerated sitting list
3. `speeches/v1/by-member/{member_id}.json` — updated for each member who spoke
4. `on-this-day/v1/{MM-DD}.json` — regenerated for the same calendar day (all past years)

The `daily-fetch` Lambda will continue to exist as the ingest orchestrator; Postgres is removed from its write path, replaced by S3 puts. Health tracking (`pipeline_health`) moves to a lightweight DynamoDB table or S3 metadata write.

---

## Design work items for migration issues

| Item | Concern | Migration issue action |
|---|---|---|
| `on-this-day` current-MP ranking | Ranking joins live `members` table; pre-build must snapshot current MP set | Rebuild all 366 artifacts on member change; embed `ranked_with_members_as_of` timestamp in artifact |
| `ridings/boundary` pre-build pipeline | No existing pipeline; needs a new cron script | Create `backend/riding-boundary-publisher` that fetches + simplifies all 338 boundaries |
| `sittings/{date}/speeches` corpus size | 60 MB total across ~1,000 files; CloudFront CDN required for cost-efficient delivery | Include CloudFront distribution in S3 migration infra issue |
| Statistics pipeline S3 writes | All 8 pipelines need an `--s3-key` argument wired to `boto3.put_object` | Single PR adds optional `--s3-key` to each pipeline; `--output` path still works for local runs |
| `health` endpoint | Currently reads `pipeline_health` Postgres table; post-migration there is no Postgres | Replace with S3-resident `pipeline-health.json` artifact updated by each pipeline after a run |
