# ASO Keyword Refresh Playbook

**Cadence:** Quarterly (Jan, Apr, Jul, Oct)
**Time required:** ~3 hours
**Owner:** Any developer on the team

## Why quarterly?

Apple's search algorithm re-indexes apps within days of a metadata update. Keyword rankings shift as:
- Competitors update their listings
- News cycles create seasonal search spikes (budget, election, throne speech)
- Apple adjusts weighting of individual terms

## Step-by-step process

### 1. Pull current performance data (30 min)

In App Store Connect → Analytics → Acquisition → App Store Search:
- Export the last 90 days of search terms (CSV)
- Identify terms in the current keyword field that have zero impressions → candidates for replacement
- Identify terms NOT in the keyword field that appear in the search terms report → users found us despite not targeting these

Save the export to `docs/marketing/keyword-data/YYYY-QN-search-terms.csv` (not committed — too sensitive; keep locally).

### 2. Research new candidates (1 hour)

Using the framework from `docs/marketing/aso-keyword-research.md`:
- Check parliamentary calendar for upcoming civic events (session opening, budget, election)
- Search App Store for 5–10 competitor/adjacent apps; note terms in their descriptions
- Generate 20 new candidates with volume/difficulty estimates
- For French: check what Quebec civic news sites are calling current parliament topics

### 3. Score and select (30 min)

Score each candidate 1–10 on:
- Expected volume (how many Canadians search this monthly)
- Fit with epac's actual features
- Competition (how many strong apps rank for this term)

Select replacements: swap out zero-impression current keywords for highest-scoring new candidates.

### 4. Compose new keyword strings (30 min)

- en-US: ≤100 chars, comma-separated, no spaces
- fr-CA: ≤100 chars, comma-separated, no spaces
- Never include words from app name or subtitle
- Test char count: `echo -n "your,string,here" | wc -c`

### 5. Update and submit (30 min)

- Update `ios/fastlane/metadata/en-US/keywords.txt`
- Update `ios/fastlane/metadata/fr-CA/keywords.txt`
- Open a PR with the keyword changes
- After merge, run `cd ios && bundle exec fastlane deliver` (requires ASC credentials)
- Document the change in `docs/marketing/aso-log.md`

### 6. Track results (ongoing)

After 4 weeks, compare ASC search terms report to pre-change baseline.
Document findings in `docs/marketing/aso-log.md` under the refresh date.

## Keyword refresh log

See `docs/marketing/aso-log.md` for historical changes.

## Tooling

- `scripts/marketing/aso-baseline-audit.sh` — generates a ratings snapshot from ASC API
- ASC Analytics CSV export — manual download required (no public API for search term data)
- `echo -n "..." | wc -c` — count keyword string length before submitting
