#!/usr/bin/env bash
# aso-baseline-audit.sh
#
# Fetches App Store Connect metadata and ratings for epac and writes a
# markdown baseline report to docs/marketing/growth-metrics-<YYYY-MM>.md.
#
# Prerequisites:
#   - PyJWT and requests installed:  pip install PyJWT requests
#   - Environment variables (same as fastlane / CI):
#       ASC_KEY_ID        — 10-character ASC API key ID
#       ASC_ISSUER_ID     — UUID from App Store Connect Users and Access
#       ASC_KEY_PATH      — path to the AuthKey_<KEY_ID>.p8 file
#
# Usage:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.appstoreconnect/AuthKey.p8 \
#     bash scripts/marketing/aso-baseline-audit.sh
#
# Output:
#   docs/marketing/growth-metrics-<YYYY-MM>.md
#
# Note on Analytics data:
#   The App Store Connect API does not expose the full Analytics suite
#   (impressions, page views, conversion rates, installs-by-source, search
#   terms) via the public REST API — those live only in ASC → Analytics in
#   the browser. This script fetches what IS available via the API (ratings
#   summary, recent reviews, app metadata) and writes placeholder rows for
#   the rest so a human can fill them in from the browser.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATE="$(date +%Y-%m-%d)"
MONTH="$(date +%Y-%m)"
OUT="$REPO_ROOT/docs/marketing/growth-metrics-$MONTH.md"

# Validate env
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH}"

echo "Running ASO baseline audit for $MONTH..."

# Delegate API calls to the Python script that already handles JWT auth
RATINGS_JSON="$REPO_ROOT/scripts/marketing/.aso-audit-ratings.json"

python3 - <<PYEOF
import json, time, jwt, requests, sys, os

APP_ID = "1224459142"
BASE   = "https://api.appstoreconnect.apple.com/v1"

key_id    = os.environ["ASC_KEY_ID"]
issuer_id = os.environ["ASC_ISSUER_ID"]
key_path  = os.environ["ASC_KEY_PATH"]

with open(key_path) as f:
    key = f.read()

now = int(time.time())
token = jwt.encode(
    {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
    key, algorithm="ES256", headers={"kid": key_id},
)
hdrs = {"Authorization": f"Bearer {token}"}

def asc_get(path, params=None):
    r = requests.get(f"{BASE}{path}", headers=hdrs, params=params, timeout=30)
    if not r.ok:
        print(f"  ASC {r.status_code} {path}: {r.text[:200]}", file=sys.stderr)
        return {}
    return r.json()

# Customer reviews (public API — gives rating + title + body)
print("Fetching customer reviews...", file=sys.stderr)
rev_data = asc_get(
    f"/apps/{APP_ID}/customerReviews",
    params={
        "limit": 20,
        "sort": "-rating",
        "fields[customerReviews]": "rating,title,body,createdDate",
    },
)
reviews = [
    {
        "rating": r["attributes"]["rating"],
        "title":  r["attributes"].get("title", ""),
        "body":   (r["attributes"].get("body") or "")[:200],
        "date":   r["attributes"]["createdDate"][:10],
    }
    for r in rev_data.get("data", [])
]

# Aggregate ratings from reviews
if reviews:
    total   = len(reviews)
    avg     = sum(r["rating"] for r in reviews) / total
    five_pc = sum(1 for r in reviews if r["rating"] == 5) / total * 100
else:
    total = avg = five_pc = None

result = {
    "fetched_at": "$DATE",
    "review_count_in_sample": total,
    "avg_rating_in_sample":   round(avg, 2) if avg else None,
    "five_star_pct_in_sample": round(five_pc, 1) if five_pc else None,
    "recent_reviews": reviews[:5],
}
with open("$RATINGS_JSON", "w") as f:
    json.dump(result, f, indent=2)
print(f"  Wrote ratings data ({total} reviews sampled)", file=sys.stderr)
PYEOF

# Read the ratings JSON back into shell variables
RATING_AVG=$(python3 -c "import json; d=json.load(open('$RATINGS_JSON')); print(d['avg_rating_in_sample'] or '_[fill from ASC]_')")
RATING_COUNT=$(python3 -c "import json; d=json.load(open('$RATINGS_JSON')); print(d['review_count_in_sample'] or '_[fill from ASC]_')")
FIVE_STAR_PCT=$(python3 -c "import json; d=json.load(open('$RATINGS_JSON')); v=d['five_star_pct_in_sample']; print(f'{v}%' if v else '_[fill from ASC]_')")

# Clean up temp file
rm -f "$RATINGS_JSON"

# Current listing state (read from fastlane metadata)
KEYWORDS=$(cat "$REPO_ROOT/ios/fastlane/metadata/en-US/keywords.txt" 2>/dev/null || echo "_[not found]_")

echo "Writing baseline document to $OUT..."
mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<MDEOF
# epac Growth Metrics — $MONTH Baseline

**Date recorded:** $DATE
**Purpose:** Baseline before structured ASO campaign (EPAC-206)
**Script:** \`scripts/marketing/aso-baseline-audit.sh\`

---

## App Store Connect Analytics (30-day snapshot)

> Fill from ASC → Analytics → Overview. The REST API does not expose Analytics data.

| Metric | Value | Notes |
|---|---|---|
| Impressions | _[fill from ASC]_ | Unique devices that saw the app icon |
| Product page views | _[fill from ASC]_ | |
| Installs | _[fill from ASC]_ | |
| Conversion rate (views→installs) | _[fill from ASC]_ | Primary KPI — target ≥ 3% |
| Re-downloads | _[fill from ASC]_ | |
| D7 retention | _[fill from ASC]_ | Target ≥ 30% |
| D28 retention | _[fill from ASC]_ | Target ≥ 15% |

---

## Installs by Source (30-day)

> Fill from ASC → Analytics → Installs → split by Source Type.

| Source | Installs | % of total |
|---|---|---|
| App Store Search | _[fill]_ | |
| App Store Browse | _[fill]_ | |
| Web Referral | _[fill]_ | |
| App Referral | _[fill]_ | |

---

## Top Search Terms (from ASC → Acquisition → App Store Search)

> Fill from ASC → Analytics → Acquisition → App Store Search Popularity.

| Rank | Term | Impressions | Installs | CVR |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

---

## Ratings

> Avg rating and five-star % are sampled from the 20 most-recent reviews via the
> ASC API (not the full lifetime breakdown — fill the lifetime numbers from ASC).

| Metric | API sample | Lifetime (fill from ASC) |
|---|---|---|
| Average rating | $RATING_AVG | _[fill]_ |
| Total ratings (lifetime) | — | _[fill]_ |
| Ratings in sample | $RATING_COUNT | — |
| 5-star % in sample | $FIVE_STAR_PCT | _[fill lifetime]_ |

---

## Current Keyword Field (as of $DATE)

\`\`\`
$KEYWORDS
\`\`\`

---

## Current Listing Copy Summary

- **App name:** epac
- **Subtitle:** Parliament in your pocket (added 2026-04-27, EPAC-326)
- **Promotional text:** Follow Parliament in real time. Track your MP's votes, read today's Hansard debates, and stay informed on every bill — straight from official sources.

---

## Google Search Console (fill from search.google.com/search-console)

> Date range: last 28 days ending $DATE.

| Metric | Value |
|---|---|
| Total clicks (28 days) | _[fill]_ |
| Total impressions (28 days) | _[fill]_ |
| Average CTR | _[fill]_ |
| Average position | _[fill]_ |
| Pages indexed | _[fill from Coverage report]_ — target 338+ riding pages |

### Top queries by clicks

> Fill from Search Console → Performance → Queries.

| Rank | Query | Clicks | Impressions | Position |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

---

## Next Review

Scheduled: $(python3 -c "
from datetime import date
d = date.today().replace(day=1)
m = d.month % 12 + 1
y = d.year + (1 if d.month == 12 else 0)
print(date(y, m, 30 if m in [4,6,9,11] else 31 if m != 2 else 28).strftime('%Y-%m-%d'))
") (monthly cadence)

---

## Notes

_Add any observations about what drove the numbers above. Note any known
attribution gaps (e.g. installs from direct App Store URL shares not captured
in any source bucket)._
MDEOF

echo "Done. Baseline document written to: $OUT"
echo ""
echo "Next steps:"
echo "  1. Open ASC → Analytics → Overview and fill in the Analytics section"
echo "  2. Open Search Console and fill in the GSC section"
echo "  3. Commit the filled-in document"
