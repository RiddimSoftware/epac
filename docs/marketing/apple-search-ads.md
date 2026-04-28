# Apple Search Ads — Setup and Results

**Ticket:** EPAC-216
**Status:** Setup pending (requires searchads.apple.com browser access)

## Why Apple Search Ads

ASA is the highest-intent paid acquisition channel for iOS:
- Users are actively searching the App Store when they see the ad
- Attribution is first-party (Apple), not inferred via SKAdNetwork
- No creative work required for Basic — Apple uses existing metadata
- Payment only on install, not impression

For a civic app with authoritative positioning (no ads, no tracking, verified sources), paid acquisition via ASA is brand-safe: we are not buying data or tracking users, we are bidding on search intent.

## Account setup (one-time, 30 min)

1. Go to searchads.apple.com
2. Sign in with the same Apple ID that owns the app (sunny@riddimsoftware.com)
3. Accept developer terms
4. Create a campaign:
   - **Campaign name:** epac-canada-basic-2026
   - **Budget:** $150 CAD/month ($5/day)
   - **Max CPI:** $2.00 CAD (adjust after first 2 weeks)
   - **Countries:** Canada only
   - **Devices:** All (iPhone + iPad)
   - **Campaign type:** Basic (Apple manages keywords automatically)
5. Link payment method (credit card — billed monthly)
6. Set campaign to Active

## Budget rationale

$150 CAD/month = ~75 installs/month at $2 CPI target.
At $1.50 actual CPI (common for niche civic apps with low competition): ~100 installs/month.
This is a test budget — evaluate after 30 days.

## Keywords Apple will target automatically (Basic)

With Basic, Apple reads the app's title ("epac"), subtitle ("Parliament in your pocket"), description, and keywords field. It bids on semantically related searches. After EPAC-310's keyword optimization, the signals Apple reads are stronger.

Expected auto-targeting includes: "canada parliament", "mp tracking", "hansard", "canadian government", "vote tracker".

## 30-day evaluation criteria

| Metric | Target | Action if missed |
|---|---|---|
| Installs | ≥50 | Extend to 60 days before deciding |
| CPI | ≤$3.00 CAD | Pause; improve screenshots first (EPAC-301) |
| D7 retention | ≥20% | Investigate onboarding (is new user flow clear?) |
| Impressions | ≥2,000 | If low, check keyword field and metadata quality |

## Results tracking

After 30 days, fill in `docs/marketing/apple-search-ads-results.md` with:
- Total spend, installs, average CPI
- D7 retention (check via ASC Retention report)
- Top 5 keywords ASA chose (visible in ASA dashboard → Search Terms)
- Decision: continue / scale / pause

## Upgrading to Advanced

After 3 months of Basic, consider Advanced if:
- Basic is delivering at <$2 CPI and you want to target specific high-volume keywords
- You want to run brand keyword campaigns (bidding on competitors' names)
- You want separate campaigns for parliamentary sitting season vs. recess
