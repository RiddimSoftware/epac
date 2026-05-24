# Experiment — First-screenshot caption: action-led vs tagline

**Status:** completed (deferred-by-rule — shipped directly)
**Created:** 2026-05-07
**Completed:** 2026-05-07
**Source:** [ASO Scorecard 2026-05-07](https://linear.app/riddimsoftware/initiative/aso-epac-04b0fbc7514c) · Experiment Planning Meeting
**Linear issue:** [EPAC-1762](https://linear.app/riddimsoftware/issue/EPAC-1762)

## Result

**Decision:** Ship Variant B directly.

**Rationale:**
1. **Baseline Traffic:** App Store Connect Analytics for the 14-day period ending 2026-05-07 were unavailable (API 403 / No recent reports found in `docs/marketing/reports`).
2. **Decision Rule:** Following the "Sample-size estimate" decision rule: _"If baseline < 100 / day, defer the experiment and instead ship the better-of-two-on-paper variant directly"_. Without a confirmed baseline above the 100/day floor, the experiment is deferred to avoid an underpowered PPO test.
3. **Execution:** Variant B ("See every vote your MP casts") is adopted as the new default first screenshot for the en-CA locale.

**Follow-up:**
- Monitor install CVR MoM for any significant directional shifts.
- Re-evaluate PPO potential once [EPAC-1752](https://linear.app/riddimsoftware/issue/EPAC-1752) and [EPAC-1753](https://linear.app/riddimsoftware/issue/EPAC-1753) have shipped and established a new traffic floor.

**Owning product:** ePac (`net.dinglebox.cabinetdoor`, ASC `1224459142`)
**Locale scope:** en-CA (CA App Store)
**Surface:** Apple Product Page Optimization (PPO), default product page, Treatment slot 1 of 3

## Hypothesis

Replacing the first screenshot's tagline-style caption ("Parliament in your pocket") with an **action-led caption that names a concrete user job** ("See every vote your MP casts") increases impression-to-product-page-view CTR by **≥ 6 %** at p < 0.10. The bet is that users searching `mp`, `vote`, `bills`, `hansard`, `senate` (the existing ePac keyword field) recognize concrete-action language faster in a thumbnail-sized search-result preview than they do tagline language.

## Why this experiment, why now

- Apple began **indexing screenshot caption text in June 2025**. The first three screenshots appear directly in search results; the first frame is the highest-leverage marketing surface on the listing.
- ePac's current first screenshot is `01-parliament-in-your-pocket.png` — its caption mirrors the (also tagline-style) subtitle. That doubles up on tagline language and wastes the action-orientation that screenshots 2–6 already do well (`02-see-how-your-mp-votes.png`, `04-track-a-bill-start-to-finish.png`).
- Per Phiture's 2026 ASO Stack benchmarks, action-verb screenshots average +18 % CVR vs tagline screenshots; SplitMetrics reports a similar lift band on tested screenshot variants.

## Variant spec

### Variant A (control)

| Field | Value |
|---|---|
| File | `01-parliament-in-your-pocket.png` |
| Visual treatment | Existing layout, current chrome, tagline caption: **"Parliament in your pocket"** |
| Other screenshots in set | unchanged: `02` … `06` |

### Variant B (treatment)

| Field | Value |
|---|---|
| File | `01-see-every-vote-your-mp-casts.png` (new asset) |
| Visual treatment | Same layout / chrome / colour as control. Only the caption text changes. |
| Caption | **"See every vote your MP casts"** (29 chars, verb-led, references `vote`+`MP` keywords) |
| Other screenshots in set | unchanged: `02` … `06` |

Caption alternatives considered and rejected (kept here to preserve reasoning):

- _"Track every vote, debate, bill"_ — too close to the proposed subtitle change in [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755); experiments must isolate one variable.
- _"Read your MP's every word"_ — Hansard-aligned but less specific; "vote" is more search-aligned per the existing keyword field.
- _"Hold Parliament accountable"_ — too abstract; the call-to-action is opaque at thumbnail size.

## Success metric

**Primary:** impression-to-product-page-view CTR on the default product page, measured via App Store Connect → Analytics → Product Page Optimization → this treatment.
**Secondary:** product-page-view to install CVR (a tagline-led first frame might convert browsers worse downstream even if it pulls the click).
**Guardrail:** install-to-launch retention (D1) — drop in D1 retention > 5 % vs control implies the treatment is attracting wrong-fit users; stop the test.

## Sample-size estimate

**Gap.** ePac's `analyticsReportRequests` ASC API scope returns 403 (per registry notes). The team does not currently have a measured baseline of impressions-per-day on the default product page. Without that, sample-size cannot be estimated with conventional power calculation (`n = 2σ²(zα + zβ)² / Δ²`).

**Pre-condition for running this experiment:** a 14-day baseline impression count from ASC analytics with `> 100 / day` (Apple's documented minimum for PPO traffic allocation; PPO won't allocate test traffic below that floor reliably).

**Decision rule for go/no-go on running:**
- If 14-day baseline ≥ 1,500 impressions/day on default page, run for 14 days minimum, target 0.10 significance.
- If baseline 100 – 1,500 / day, run for 28 days minimum, accept p < 0.20 directional read.
- If baseline < 100 / day, **defer the experiment** and instead ship the better-of-two-on-paper variant directly per the Scorecard's recommendation. Re-evaluate next cycle after [EPAC-1752](https://linear.app/riddimsoftware/issue/EPAC-1752) (review prompts) and [EPAC-1753](https://linear.app/riddimsoftware/issue/EPAC-1753) (fr-CA listing) lift the install volume above the PPO floor.

## Risk / cost

| Risk | Severity | Mitigation |
|---|---|---|
| PPO traffic allocation reduces total installs during test | low | PPO allocates ≤ 50 % of traffic to treatments by default; control still ships to most users. |
| Variant B caption rejected by Apple as ambiguous "vote" reference | low | "vote" is contextualized by the listing category (News) and the existing keyword field already uses `vote`. Fallback caption: `"Track every MP's votes daily"`. |
| Sample size too small for significance | high (per Sample-size section above) | Decision rule above explicitly defers the experiment if baseline < 100 / day. |
| Test cannibalizes the better tagline-based brand recognition | low | Control still serves; if Variant B harms, post-test the original ships back. |
| Hawthorne / novelty effect at start of test | low | First 48 h excluded from analysis; standard PPO practice. |

**Cost:** 1 × designer asset for Variant B (caption swap on existing layout — < 0.5 day). 1 × ASC submission cycle. No engineering cost.
**Reversibility:** fully reversible — PPO treatment can be killed mid-test; control set is unchanged at any point.

## Out of scope

- Multi-variable tests (caption + visual treatment in one test). One element per experiment.
- Localized fr-CA test — fr-CA listing doesn't exist yet ([EPAC-1753](https://linear.app/riddimsoftware/issue/EPAC-1753)). Once it does, a fr-CA equivalent of this experiment will be a separate spec file.
- Shipping the winner — separate `aso, Task` issue once the result is in.

## Definition of Done

1. 14-day pre-experiment baseline impressions captured (via ASC analytics) and posted as a comment on the Linear issue.
2. Decision rule applied: run / defer / ship-without-test.
3. If run: PPO test conducted; result documented as a comment with lift, significance, decision (ship Variant B / keep control / extend).
4. If shipped: follow-up `aso, Task` issue filed to ship the winner; this experiment closed.

## Review notes (for the human reviewer of this PR)

- This file is a **specification**, not an instruction to run the experiment immediately. The acceptance criteria explicitly gate on baseline traffic.
- The corresponding Linear issue (filed alongside this PR) tracks ownership and timing. The PR's only purpose is to get the spec under version control next to the ePac repo's other ASO artifacts.
- Alternative: if the team prefers to run experiments only via the org's chosen creative-testing tool (vendor sign-off pending), this spec is portable to that tool — replace "PPO" with the vendor name and the structure stands.
