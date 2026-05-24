# Product Page Optimization - EPAC-111

**Status:** Variant B creative package ready for App Store Connect upload  
**Treatment name:** Variant B - Problem/Solution  
**Baseline:** Variant A from EPAC-109 feature-led screenshot set  
**Primary device size:** iPhone 6.9 inch, 1290 x 2796 px  

## Test Hypothesis

Problem/solution framing will convert better than feature-led framing because the first screenshot answers a sharper user question: "Did my MP do something I should know about?"

Variant B leads with the vote-awareness hook, then reveals the product workflow:

1. Your MP voted last night. Did you know?
2. What did they say before the vote?
3. Your representative has a record.
4. A bill can spend billions.
5. Was it a party-line vote?
6. Have something to say?

## Asset Set

Generated PNGs live in `docs/marketing/app-store/ppo-epac111/variant-b/`.

| Order | File | App Store role |
|---|---|---|
| 1 | `01-your-mp-voted-last-night.png` | First screenshot and search result hook |
| 2 | `02-what-they-said-before.png` | Hansard debate readability |
| 3 | `03-your-representative.png` | My MP personalization |
| 4 | `04-bill-cost.png` | Bill tracking and PBO cost context |
| 5 | `05-party-line.png` | Voting record and party split |
| 6 | `06-contact-with-context.png` | Contact workflow close |

SVG source files are committed beside the PNGs. Regenerate with:

```sh
python3 scripts/marketing/generate_epac111_ppo_assets.py
```

## App Store Connect Setup

Apple Product Page Optimization supports testing alternate screenshots, app previews, and icons against the original product page, with up to three treatments. For EPAC-111:

- Product page: iOS app `epac`
- Treatment count: 1
- Treatment name: `Variant B - Problem/Solution`
- Traffic allocation: 50 percent baseline / 50 percent Variant B
- Duration: 90 days
- Localization: English Canada first
- Asset type: screenshots only
- Screenshot set: upload the six Variant B PNG files in order

## Monitoring Plan

Check App Store Connect Analytics weekly:

| Date | Baseline impressions | Variant B impressions | Baseline conversion | Variant B conversion | Notes |
|---|---:|---:|---:|---:|---|
| TBD | | | | | |

Do not call a winner before Variant B reaches at least 1,000 impressions. If App Store Connect reports a winning treatment before 1,000 impressions, keep the test running until the threshold is met unless Apple rejects or pauses the treatment.

## Winner Adoption

When the winner is clear:

1. Record final impressions, conversion rates, and delta in this document.
2. If Variant B wins, adopt the six PNGs as the default screenshot set.
3. If Variant A wins, leave the default screenshot set unchanged.
4. Add the result to `CLAUDE.md` under marketing decisions.

## External Blockers

This repo package does not configure the live PPO test. App Store Connect setup, traffic allocation, approval, 1,000-impression monitoring, and winner adoption require authenticated App Store Connect access and elapsed test time.
