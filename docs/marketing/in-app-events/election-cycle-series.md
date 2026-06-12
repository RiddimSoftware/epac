# In-App Event Series: Federal Election Cycle

**Status:** Shelf-ready spec — activate on writ drop  
**Series scope:** 7 events across the 36-day campaign window and post-election period  
**Ticket:** EPAC-1759  

---

## Overview

Apple in-app events are indexed in App Store search and category browse from iOS 15.6+. A pre-designed series of 7 events covering the full federal election cycle gives ePac a sustained indexed presence throughout the campaign window, when search volume on `election`, `riding`, `MP`, `candidate`, and `polling station` peaks by an order of magnitude.

All copy is neutral and informational — zero editorial, zero partisan framing, zero candidate names. This is required to pass Apple review and is consistent with ePac's brand.

**Apple limits per event:**
- Event name: ≤ 30 characters
- Short description: ≤ 50 characters
- Long description: ≤ 120 characters
- Event card image: 1024 × 1024 px

---

## Event Series Spec

### Event 1 — Writ Drop

| Field | Value |
|-------|-------|
| Reference name | `election-writ-drop` |
| Event type | Special Event |
| Badge | ELECTION |
| **Event name (en-CA)** | Election Called |
| **Short description (en-CA)** | Canada's federal election writ has been issued. |
| **Long description (en-CA)** | The writ of election has dropped. ePac tracks every riding, MP voting record, and bill from official sources. |
| **Event name (fr-CA)** | Élection déclenchée |
| **Short description (fr-CA)** | Le bref électoral est lancé au Canada. |
| **Long description (fr-CA)** | Le bref est lancé. ePac suit chaque circonscription et chaque vote de député depuis les sources officielles. |
| Event purpose | Announce the election; draw users who search "federal election called" |
| Start date | Writ drop day (Day 0) |
| End date | Day 0 + 3 days |
| Deep link (universal) | `https://epac.riddimsoftware.com/` |
| Deep link (custom scheme) | `cabinetdoor://` |
| Imagery direction | Parliament Hill Centre Block exterior — dawn light, no signage, no people. Neutral, civic. |
| Submit by | Day 0 (writ drop day — submit immediately) |

---

### Event 2 — English Leaders' Debate

| Field | Value |
|-------|-------|
| Reference name | `leaders-debate-english` |
| Event type | Live Event |
| Badge | LIVE |
| **Event name (en-CA)** | English Leaders' Debate |
| **Short description (en-CA)** | Tonight: the English-language federal leaders' debate. |
| **Long description (en-CA)** | The English-language leaders' debate is tonight. Check each party's voting record and bill positions in ePac. |
| **Event name (fr-CA)** | Débat des chefs en anglais |
| **Short description (fr-CA)** | Ce soir : le débat des chefs en anglais. |
| **Long description (fr-CA)** | Le débat anglophone des chefs a lieu ce soir. Vérifiez le bilan de vote de chaque parti dans ePac. |
| Event purpose | Surface ePac to users watching the debate and searching for party/MP voting history |
| Start date | Debate start time (typically ~Week 2 of campaign, confirm from Elections Canada / broadcaster) |
| End date | Debate day + 1 day |
| Deep link (universal) | `https://epac.riddimsoftware.com/` |
| Deep link (custom scheme) | `cabinetdoor://` |
| Imagery direction | Empty podiums in a clean debate-hall setting. No candidate faces, no party colours. Neutral blue/grey. |
| Submit by | At least 14 days before debate night (submit on writ drop day alongside Event 1) |

---

### Event 3 — French Leaders' Debate

| Field | Value |
|-------|-------|
| Reference name | `leaders-debate-french` |
| Event type | Live Event |
| Badge | LIVE |
| **Event name (en-CA)** | French Leaders' Debate |
| **Short description (en-CA)** | Tonight: the French-language federal leaders' debate. |
| **Long description (en-CA)** | French-language leaders' debate tonight. Track each party's parliamentary record and voting history in ePac. |
| **Event name (fr-CA)** | Débat des chefs en français |
| **Short description (fr-CA)** | Ce soir : le débat des chefs en français. |
| **Long description (fr-CA)** | Le grand débat francophone des chefs est ce soir. Retrouvez le bilan parlementaire de chaque chef dans ePac. |
| Event purpose | Reach Quebec and francophone audiences at peak engagement; fr-CA copy signals official record, not partisan coverage |
| Start date | French debate night (typically 1–2 days after English debate, confirm from consortium) |
| End date | Debate day + 1 day |
| Deep link (universal) | `https://epac.riddimsoftware.com/` |
| Deep link (custom scheme) | `cabinetdoor://` |
| Imagery direction | Same visual treatment as English debate event — podiums, neutral, no candidate imagery |
| Submit by | At least 14 days before debate night (submit on writ drop day) |

> **fr-CA note:** Quebec's election-night audience follows TVA/Radio-Canada. Frame copy as "official record" (bilan parlementaire) rather than "live results in your pocket." Do not use campaign-framing language.

---

### Event 4 — Advance Polls Open

| Field | Value |
|-------|-------|
| Reference name | `advance-polls-open` |
| Event type | Special Event |
| Badge | VOTE EARLY |
| **Event name (en-CA)** | Advance Polls Are Open |
| **Short description (en-CA)** | Vote early — 4 days of advance polling begins today. |
| **Long description (en-CA)** | Advance polling runs for 4 days. Look up your MP's voting record and riding history in ePac before you vote. |
| **Event name (fr-CA)** | Vote par anticipation |
| **Short description (fr-CA)** | Le vote par anticipation est ouvert — 4 jours. |
| **Long description (fr-CA)** | Quatre jours de vote par anticipation. Consultez le bilan de votre député dans ePac avant d'aller voter. |
| Event purpose | Reach "polling station" and "advance voting" searchers; route them to the riding/MP lookup |
| Start date | First day of advance polling (Day 23 of campaign per Canada Elections Act) |
| End date | Last day of advance polling + 1 day (Day 27) |
| Deep link (universal) | `https://epac.riddimsoftware.com/setup/postal-code` |
| Deep link (custom scheme) | `cabinetdoor://setup/postal-code` |
| Imagery direction | Ballot box or exterior shot of a civic building (community centre, school). Plain, welcoming, no partisan signage. |
| Submit by | Day 9 of the campaign (14 days before Day 23) |

---

### Event 5 — Election Day

| Field | Value |
|-------|-------|
| Reference name | `election-day` |
| Event type | Live Event |
| Badge | ELECTION DAY |
| **Event name (en-CA)** | Election Day |
| **Short description (en-CA)** | Today Canadians elect their next Parliament. |
| **Long description (en-CA)** | Today Canadians elect the next Parliament. Look up your candidates and riding in ePac before you vote. |
| **Event name (fr-CA)** | Jour de l'élection |
| **Short description (fr-CA)** | Les Canadiens votent pour leur prochain Parlement. |
| **Long description (fr-CA)** | C'est le jour du scrutin. Vérifiez vos candidats et votre circonscription dans ePac avant de voter. |
| Event purpose | Highest-traffic ASO day of the cycle; capture every "how to vote" and "find my riding" searcher |
| Start date | Election Day (Day 36 of campaign) |
| End date | Election Day + 1 day (polls close ~9:30 PM PT when BC closes) |
| Deep link (universal) | `https://epac.riddimsoftware.com/setup/postal-code` |
| Deep link (custom scheme) | `cabinetdoor://setup/postal-code` |
| Imagery direction | Parliament Hill aerial — golden hour, no people, no signage. Or: a single unoccupied polling booth with natural light. Canadian flag may be included but must not dominate. |
| Submit by | Day 22 of the campaign (14 days before Election Day) |

---

### Event 6 — Results Night

| Field | Value |
|-------|-------|
| Reference name | `election-results` |
| Event type | Live Event |
| Badge | RESULTS |
| **Event name (en-CA)** | Election Results |
| **Short description (en-CA)** | Votes are being counted. Follow results by riding. |
| **Long description (en-CA)** | Polls have closed. ePac's MP and riding data updates as official results are certified. See who won your riding. |
| **Event name (fr-CA)** | Résultats de l'élection |
| **Short description (fr-CA)** | Résultats en cours. Suivez votre circonscription. |
| **Long description (fr-CA)** | Bureaux de scrutin fermés. ePac se met à jour au fil des résultats officiels. Qui a gagné votre circonscription? |
| Event purpose | Retain users through results night; high engagement window for "who won my riding" searches |
| Start date | 6:30 PM ET on Election Day (Atlantic polls close; results begin) |
| End date | Election Day + 2 days (official preliminary results certified) |
| Deep link (universal) | `https://epac.riddimsoftware.com/` |
| Deep link (custom scheme) | `cabinetdoor://` |
| Imagery direction | Map of Canada with ridings (outline only, no colour fills), or Parliament Hill exterior at night. No election-results scoreboard aesthetic — keep it factual and calm. |
| Submit by | Day 22 of the campaign (same submission batch as Event 5) |

> **fr-CA note:** Quebec audiences follow TVA/Radio-Canada results coverage closely. Ensure fr-CA copy frames ePac as the official record source, not a results tracker. Do not use "en direct" or "en temps réel" language — this overpromises live data.

---

### Event 7 — New Parliament Convenes

| Field | Value |
|-------|-------|
| Reference name | `new-parliament-opens` |
| Event type | Major Update |
| Badge | NEW PARLIAMENT |
| **Event name (en-CA)** | New Parliament Opens |
| **Short description (en-CA)** | Canada's new Parliament is now sitting. |
| **Long description (en-CA)** | The new Parliament has been sworn in. Follow your new MP's first debates, votes, and committee appearances in ePac. |
| **Event name (fr-CA)** | Nouveau Parlement |
| **Short description (fr-CA)** | Le nouveau Parlement canadien siège maintenant. |
| **Long description (fr-CA)** | Le nouveau Parlement est assermenté. Suivez les premiers débats et votes de votre député dans ePac. |
| Event purpose | Re-engage lapsed users as the new Parliament begins; capture "new MP" and "Speech from the Throne" search intent |
| Start date | First sitting day of the new Parliament (varies; typically 4–8 weeks after Election Day) |
| End date | Start date + 14 days |
| Deep link (universal) | `https://epac.riddimsoftware.com/sitting/YYYY-MM-DD` (first sitting date) |
| Deep link (custom scheme) | `cabinetdoor://sitting/YYYY-MM-DD` |
| Imagery direction | House of Commons chamber — overhead view, seats filling, clean framing. Or: the Governor General's arrival at Parliament Hill (Throne Speech day). Public domain, Library of Parliament archive. |
| Submit by | At least 14 days before the first sitting day (confirm sitting date from parl.ca calendar) |

---

## Trigger Plan

### Primary signal: Elections Canada official bulletin

Elections Canada publishes a **Writ of Election** on elections.ca as soon as the Governor General issues the proclamation. The ASO lead should monitor:

1. **elections.ca news releases** — official writ notice is published within minutes of issuance; has an RSS feed.
2. **gg.ca** — the Governor General's office posts the proclamation on the same day.
3. **CBC News RSS / push alert** (backup) — CBC breaks this story within minutes; use as a cross-check only.

### Writ-drop response procedure (time-sensitive)

| Time | Action |
|------|--------|
| T+0 (writ drops) | Confirm at elections.ca; note the official Election Day (Day 36) |
| T+1h | Calculate all 7 event dates using the timeline below |
| T+2h | Log into App Store Connect; update placeholder dates on all 7 events |
| T+3h | Submit all 7 events for Apple review in a single batch |
| T+1–3 days | Apple approves (typical; spec 14 days) — activate approved events |
| Day 9 | Confirm Event 4 (Advance Polls) is live; advance polling starts Day 23 |
| Day 22 | Confirm Events 5 & 6 (Election Day + Results) are live |
| Post-election | Confirm first Parliament sitting date; update Event 7 deep link date; submit if not yet approved |

### Federal election campaign timeline reference

| Event | Campaign day |
|-------|-------------|
| Writ drop | Day 0 |
| Leaders' debate (English) | ~Day 14 (varies by consortium) |
| Leaders' debate (French) | ~Day 16 (varies by consortium) |
| Advance polls open | Day 23 (fixed by Canada Elections Act, s. 168) |
| Advance polls close | Day 26 |
| Election Day | Day 36 (fixed by Canada Elections Act, s. 57) |
| Preliminary results certified | Day 36–37 |
| New Parliament sits | Day 36 + 28–56 days (GG proclamation) |

> Note: debate dates are set by the Leaders' Debates Commission (Canada). The LDC publishes the schedule within the first week of the campaign at debates-debats.ca. Monitor this source for Events 2 and 3.

---

## Localization Plan

### Languages required

| Locale | Required | Rationale |
|--------|----------|-----------|
| en-CA | Yes (primary) | Default App Store locale |
| fr-CA | Yes | Quebec voter turnout; federal election is a bilingual institution; English-only copy would be brand-incorrect |
| en-US | No | App is Canada-only; App Store Connect en-US would be confusing to non-Canadian users |

### fr-CA copy conventions

- Use "circonscription" (not "district", "comté", or "arrondissement") — this is the official Elections Canada term.
- Use "député" for MP (not "élu", "représentant", or "politicien").
- Use "Chambre des communes" (not "Parlement" when referring to the lower house specifically).
- Use "bref" or "bref électoral" (not "décret d'élection") — this is Elections Canada's French term for the writ.
- Frame results-night copy as "résultats officiels" — do not promise real-time data. ePac updates as Elections Canada certifies results, not in true real-time.
- Do not use campaign-era language ("votez pour X", "choisissez votre prochain", etc.) — informational only.

### Translation workflow

1. All en-CA copy is final in this spec.
2. fr-CA first draft is included in this spec (see each event card above).
3. Before submission, review fr-CA copy with a native fr-CA speaker, ideally from Quebec (not European French).
4. Do not use machine-translation directly for App Store copy — Apple's editorial team reviews fr-CA locales; machine translation is detectable and looks unprofessional.

---

## Risk Register and Kill-Switch

### Risk 1: Apple rejects event for political content

**Likelihood:** Medium. Apple's review guidelines (§5.6) prohibit content that is "defamatory, offensive, mean-spirited, or likely to place Apple in a negative light." Political apps are allowed; partisan endorsements are not.

**Mitigation:** 
- All copy is strictly informational ("The English-language leaders' debate is tonight") — zero editorial.
- No candidate names, party names, or colours in event copy or imagery.
- Use "Special Event" or "Major Update" type for events that don't time-lock to a live broadcast; reserve "Live Event" type for debate nights and results night only.

**Kill-switch:** If rejected, immediately resubmit with:
1. Event type downgraded from "Live Event" to "Special Event".
2. Any action verbs removed ("Vote early" → "Advance polling is now open").
3. Remove the badge text if flagged (leave badge as type-determined only).
If still rejected, fall back to normal organic ASO — the existing keyword set already includes `election`, `riding`, `MP`, `polling station` — and post a custom product page instead (no Apple review gate for CPPs).

### Risk 2: Apple review takes longer than 14 days

**Likelihood:** Low (typical review is 1–3 business days). 14 days is the documented maximum.

**Mitigation:** Submit all 7 events in a single batch on writ drop day. The earliest events (writ drop, debates) have the tightest windows; if only those are rejected or delayed, the later events (advance polls, election day) still have headroom.

**Kill-switch:** If an event misses its window (approved after the event ended), simply do not activate it. Deactivate it in App Store Connect without publishing. There is no penalty for an approved-but-not-published event.

### Risk 3: Writ recalled or election postponed

**Likelihood:** Very low (historically unprecedented in Canada, but legally possible under the Canada Elections Act in extraordinary circumstances).

**Mitigation:** App Store Connect allows events to be ended early. If the election is suspended, log into App Store Connect and set the end date to the current date on any active events.

### Risk 4: Debate dates change after submission

**Likelihood:** Medium — debate schedules are sometimes adjusted.

**Mitigation:** App Store Connect allows event date changes after submission (subject to a re-review if the change is significant). Submit Events 2 and 3 with the best-known dates and update if the LDC schedule shifts. Set event end dates to +2 days as a buffer against same-day schedule changes.

### Risk 5: Event card artwork rejected

**Likelihood:** Low. Parliament Hill exterior shots are consistently approved.

**Mitigation:** The single safe fallback for all 7 events is a Parliament Hill exterior photograph from the Library of Parliament's public-domain archive (parl.ca/About/Parliament/PhotoLibrary). This has been used previously without rejection. Have this fallback image pre-prepared at 1024 × 1024 px.

---

## Asset Checklist (Prepare Before Writ Drops)

- [ ] Event card images for all 7 events — 1024 × 1024 px, saved to `docs/marketing/in-app-events/assets/`
- [ ] Parliament Hill fallback image — 1024 × 1024 px
- [ ] fr-CA copy reviewed by native fr-CA speaker
- [ ] App Store Connect events pre-configured (name, copy, type, imagery) with placeholder dates
- [ ] Elections Canada RSS feed monitored (or use a news alert on "élections fédérales bref")
- [ ] Leaders' Debates Commission (debates-debats.ca) bookmarked for debate schedule

---

## Submitted Instances

| Election | Writ drop date | Events submitted | Events activated | Notes |
|----------|---------------|-----------------|-----------------|-------|
| _(next federal election — writ not yet dropped)_ | TBD | TBD | TBD | See EPAC-1759 |
