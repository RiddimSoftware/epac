# In-App Event Template: "New Parliamentary Session"

**Reuse this template for each Parliament return (typically 3× per year: September, January, post-confidence vote).**

---

## App Store Connect fields

| Field | Value |
|-------|-------|
| Event type | Major update |
| Badge | NEW SESSION |
| Short description (30 chars max) | Parliament is back in session |
| Long description (120 chars max) | A new parliamentary session begins [DATE]. Follow the throne speech, upcoming bills, and your MP's activity in real time. |
| Start date | First sitting day of the session |
| End date | Start date + 14 days |
| Deep link | `https://epac.riddimsoftware.com/sitting/[YYYY-MM-DD]` |

## Event card image

- **Size:** 1024 × 1024 px (App Store Connect requires this for the event card)
- **Source:** Library of Parliament public domain archive — https://www.parl.ca/About/Parliament/PhotoLibrary
- **Preferred shots:** House of Commons chamber overhead, Centre Block exterior, or Parliament Hill aerial
- **File naming:** `in-app-event-new-session-[YYYY]-card.png`
- **Saved to:** `docs/marketing/in-app-events/assets/`

## Deep link

**Primary (Universal Link — preferred for App Store Connect):**
```
https://epac.riddimsoftware.com/sitting/YYYY-MM-DD
```

**Custom scheme fallback:**
```
cabinetdoor://sitting/YYYY-MM-DD
```

Both open the Parliament tab directly to the first sitting day's Hansard debates.
Replace `YYYY-MM-DD` with the ISO 8601 date of the first sitting day (e.g. `2025-09-15`).

## Recurring cadence

| Session return | Approximate date | Sitting date to confirm |
|---|---|---|
| Fall return | 2nd Monday of September | Check parl.ca calendar |
| Winter return | 3rd Monday of January | Check parl.ca calendar |
| Post-confidence / early return | Variable | Check parl.ca calendar |

## Checklist for each new instance

- [ ] Confirm first sitting date at https://www.parl.ca/en/sitting-calendar
- [ ] Update Long description with confirmed date
- [ ] Source event card image from Library of Parliament (public domain)
- [ ] Update deep link date in App Store Connect
- [ ] Submit via App Store Connect → My Apps → epac → In-App Events → + New Event
- [ ] Set start/end dates; submit for Apple review (~2 business days)
- [ ] After approval: confirm event appears on App Store product page

## Submitted instances

| Session | Start date | Submitted | Approved | Notes |
|---------|-----------|-----------|----------|-------|
| _(first instance pending — requires App Store Connect access)_ | | | | See EPAC-112 |
