# Experiment — Subtitle: accountability framing vs activity framing

**Status:** proposed (deferred — gated on [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) shipping AND on baseline traffic)
**Created:** 2026-05-07
**Source:** [ASO Scorecard 2026-05-07](https://linear.app/riddimsoftware/initiative/aso-epac-04b0fbc7514c) · Experiment Planning Meeting
**Linear issue:** _filed alongside this PR_
**Owning product:** ePac (`net.dinglebox.cabinetdoor`, ASC `1224459142`)
**Locale scope:** en-CA (CA App Store)
**Surface:** Apple Product Page Optimization (PPO), default product page, Treatment slot 2 of 3

## Hypothesis

Once [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) ships an activity-framed subtitle ("Track every vote, debate, bill"), an **accountability-framed alternative** ("Hold Parliament accountable") may convert better for the segment of users who download a Hansard-tracking app for *oversight* rather than *information*. We hypothesize accountability framing lifts product-page-view → install CVR by **≥ 5 %** at p < 0.10 vs the activity-framed control.

This experiment runs **after** [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) is in-market; the activity framing is the new baseline being tested against.

## Why this experiment, why now

- ePac's product positioning has two latent narratives: (a) "track every parliamentary action" (information) and (b) "hold your government accountable" (oversight). The current subtitle and the Scorecard-recommended replacement both lean (a). The experiment tests whether (b) outperforms.
- Apple's NLP-based ranking is intent-aware. Subtitle wording can shift not just CVR but also which queries surface ePac (accountability-related queries vs activity-related queries). The experiment will surface this shift via search-impressions side-effect.
- Subtitle is the second-highest-weighted indexed text field after title. Even small CVR shifts at this surface compound across the install funnel.

## Variant spec

### Variant A (control — assumes [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) has shipped)

| Field | Value |
|---|---|
| Field | `subtitle` |
| Locale | en-CA |
| Value | **"Track every vote, debate, bill"** (30 chars; activity-framed) |

### Variant B (treatment)

| Field | Value |
|---|---|
| Field | `subtitle` |
| Locale | en-CA |
| Value | **"Hold Parliament accountable"** (28 chars; accountability-framed) |

Variants considered and rejected:

- _"Watch every vote, debate, bill"_ — close to control, would test verb word ("Watch" vs "Track") in isolation. Lower-leverage variation; deferred to a future cycle.
- _"Hold MPs accountable, daily"_ — accountability-framed but the "daily" qualifier mixes a freshness claim into the framing test. Mixes variables.
- _"Hold Parliament accountable, daily"_ — same as above.
- _"Make Parliament transparent"_ — too abstract / passive; lower expected lift.

## Success metric

**Primary:** product-page-view → install CVR on the default product page (Apple "Search" + "Browse" + "Referrer" combined), via ASC PPO analytics for this treatment.
**Secondary:** impressions-per-day on accountability-aligned search queries (`accountability`, `petition`, `transparency`) vs control's activity queries (`vote`, `bills`, `debate`, `hansard`). Captured from ASC search-term report if available; else N/A.
**Guardrail:** D1 retention drop > 5 % vs control means the accountability framing is attracting users whose expectations the in-app experience doesn't meet — stop the test.

## Sample-size estimate

**Gap.** Same as [the first-screenshot caption experiment](./2026-05-07-first-screenshot-caption-action-led.md) — `analyticsReportRequests` returns 403 and we have no measured impression baseline.

**Pre-condition for running:** [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) shipped + 14 days of post-ship baseline data + same traffic-floor decision rule from the screenshot experiment.

The screenshot experiment (Treatment slot 1) and this subtitle experiment (Treatment slot 2) can run **concurrently** in PPO, since they're testing different surfaces and the PPO traffic split is per-treatment. If the team prefers to isolate signal, run them sequentially — screenshot first (faster baseline available), then subtitle.

## Risk / cost

| Risk | Severity | Mitigation |
|---|---|---|
| Subtitle change requires App Info layer submission | low | Subtitle change does not require a binary submission. ASC delivery rail handles. |
| Apple rejects "Hold Parliament accountable" for political tone | low–medium | Apple's metadata guidelines reject endorsements / partisan claims. "Hold accountable" is neutral civic language; CBC News, CTV News, etc. routinely use the word in editorial contexts. Fallback: `"Track every MP's record"`. |
| Accountability framing converts well but in-app experience is information-led, not action-led | medium | Mitigated by the D1 retention guardrail. If the in-app experience needs changes to deliver on the accountability promise, that's product scope and outside the experiment's authority — fall back to control. |
| Cannibalization with the already-shipped subtitle decision | low | PPO treatments don't permanently replace the App Info; control keeps shipping. |
| Sample size too small | high | Same defer-to-direct-ship decision rule as the screenshot experiment. |

**Cost:** subtitle copy (already specified). 1 × ASC submission cycle. 0 design effort.
**Reversibility:** fully reversible — PPO treatment kill-switch.

## Out of scope

- fr-CA subtitle (different locale, different audience). After [EPAC-1753](https://linear.app/riddimsoftware/issue/EPAC-1753) ships, file a separate fr-CA-subtitle test.
- Title rewrite — Apple flags branded title appends; deferred indefinitely.
- A 3-arm test (control + activity + accountability). PPO supports up to 3 treatments per app, but multi-arm reduces power per arm. Two-arm here keeps the read sharp.

## Definition of Done

1. [EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) shipped + 14-day post-ship baseline captured.
2. Decision rule applied (run / defer / ship-without-test).
3. If run: PPO test conducted; result documented as a comment on the Linear issue with lift, significance, decision.
4. Follow-up `aso, Task` issue filed if winner ships.

## Review notes (for the human reviewer of this PR)

- This file is a **specification** that explicitly defers execution until upstream conditions are met ([EPAC-1755](https://linear.app/riddimsoftware/issue/EPAC-1755) shipped + traffic baseline acquired).
- Storing the spec in version control next to the screenshot-caption experiment lets future cycles cross-reference both experiments and lets the linked Linear issue act as the always-up-to-date status pointer rather than the spec itself.
- If the team prefers to skip experiments entirely on ePac until install volume is materially higher (the Scorecard's view), this PR can be merged for documentary value and the Linear issues left in `Todo` indefinitely.
