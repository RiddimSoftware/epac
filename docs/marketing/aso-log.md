# ASO Change Log

Record every keyword field change here with rationale.

## 2026-04-27 (EPAC-310 + EPAC-210)

**en-US before:** `parliament,canada,mp,vote,bills,hansard,siri,spotlight,ontario,senate,committee,election`
**en-US after:** `hansard,mp,vote,bills,senate,election,mpp,riding,federal,debate,expenditure,petition,accountability`

**Changes:**
- Removed: `siri`, `spotlight` — iOS system features, not user search terms
- Removed: `parliament` — already in subtitle "Parliament in your pocket"
- Removed: `canada` — too broad; more specific terms have better signal
- Added: `mpp`, `riding`, `federal`, `debate`, `expenditure`, `petition`, `accountability`

**fr-CA before:** (none — first time)
**fr-CA after:** `parlement,depute,senat,chambre,vote,projet-de-loi,politique,canada,gouvernement,hansard,depenses`

## 2026-05-07 (EPAC-1762)

**Screenshot change:** First frame caption changed from tagline to action-led.
**Locale:** en-CA (en-US keywords unchanged)
**Before:** "Parliament in your pocket"
**After:** "See every vote your MP casts"

**Rationale:**
- Action-led captions with concrete user jobs ("See every vote") recognize search intent faster than taglines.
- Aligns first screenshot with search terms `mp` and `vote`.
- Experiment deferred due to low/unknown baseline traffic floor; Variant B shipped directly per Scorecard "ship + iterate" recommendation.

**Next review:** 2026-07-27


## YYYY-MM-DD (EPAC-XXX)

**en-US before:** `...`
**en-US after:** `...`

**Changes:**
- Removed: [term] — [reason]
- Added: [term] — [reason]

**Next review:** [date]
