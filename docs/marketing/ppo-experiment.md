# App Store PPO Experiment — Treatment B: News Readers

**Ticket:** EPAC-420
**Type:** App Store Product Page Optimization (A/B test)
**Traffic split:** 50/50
**Minimum duration:** 7 days
**Success metric:** Conversion rate (impressions → installs)

## Hypothesis

News readers ("I follow Canadian politics via CBC/Globe") convert better when they see relatable, current-events framing rather than parliamentary-insider framing.

## Treatment A (control — current default screenshots)

Headline style: "Parliament in your pocket" — insider positioning
Target: people who already know what Hansard is

## Treatment B (challenger — this PR)

Headline style: "Your MP just voted. Here's what happened." — news reader positioning  
Target: Canadians who follow the news and want facts behind the headlines

### Treatment B screenshot set (5 screenshots)

| # | Headline | Feature shown | Why for news readers |
|---|---|---|---|
| 1 | "Your MP just voted. Here's what happened." | Vote result with MP's riding highlighted | News trigger → epac as the explainer |
| 2 | "Question Period, straight from the record." | Oral Questions / SittingView | Familiar format (QP is on TV); epac has the full transcript |
| 3 | "Follow any bill. Know when it passes." | BillDetailView with follow button | News mentions bills; readers want to track them |
| 4 | "See exactly where your MP's expenses went." | Expenditure detail view | Accountability; taxpayer money angle resonates broadly |
| 5 | "Every debate. Every vote. Official sources only." | Home feed | Trust signal; differentiates from opinion/news sites |

## How to set up PPO in App Store Connect

1. App Store Connect → My Apps → epac → App Store tab → Product Page Optimization
2. Click "Create Test"
3. Upload Treatment B screenshots (from `ios/fastlane/screenshots/ppo-treatment-b/en-US/`)
4. Set traffic: 50% Treatment A, 50% Treatment B
5. Run for minimum 7 days
6. Read results in ASC → Analytics → Product Page Optimization

## Reading results

After 7 days: if Treatment B CVR > Treatment A by >5% with confidence >80%, promote Treatment B to the default.
If inconclusive after 14 days, keep Treatment A and iterate on Treatment B copy.

Document results in `docs/marketing/aso-log.md`.

## Compositing instructions

Raw captures are in `ios/fastlane/screenshots/ppo-treatment-b/en-US/`.
Apply same compositing process as the default set (see `docs/marketing/screenshot-brief.md`):
- Dark background #0a0a0c
- Outfit 900 headline, 42pt white
- Inter 600 sub-caption, 22pt #8a8a8e
- Official Apple device frame
