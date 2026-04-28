# epac — Apple editorial pitch

This is the source-of-truth document the operator submits to Apple's editorial team for App of the Day / curated-collection consideration. Submit verbatim or excerpt by section.

## How to use this document

1. Pick a target window from the **Timing** section (Budget Day, opening of a parliamentary session, election, or evergreen).
2. Submit at least **8 weeks before** that window via both channels:
   - App Store Connect → My Apps → epac → App Information → **App Store Promotions** → "Pitch your app" form.
   - Email applemktg@apple.com with the **Pitch (general)** body verbatim, swapping in the chosen seasonal angle and the actual target window.
3. After submission, log the outcome (accepted / declined / no response) in the project's GitHub Discussion thread for EPAC-179.

Apple does not discover apps organically for editorial features. The submission is the gate.

---

## Pitch (general)

> **Subject:** epac — Canada's Parliament, in your pocket. App of the Day pitch.
>
> Hello App Store editorial team,
>
> I'd like to pitch **epac** for App of the Day or for an upcoming "Apps for Democracy" / "Follow the News" curated collection in the Canadian storefront.
>
> **What it is.** epac is a free iPhone app that turns Canada's House of Commons proceedings — Hansard debates, recorded votes, MP expenses, bill progress, and the parliamentary calendar — into a clean, readable, group-chat view. Every figure traces to an authoritative government source: ourcommons.ca, Parliament of Canada, the Office of the Auditor General, Statistics Canada, CMHC, IRCC, and Infrastructure Canada. There are no opinion takes, no LLM-generated summaries, and no engagement-bait framings.
>
> **Why it's worth featuring right now.** [Insert one of the seasonal angles below.]
>
> **What makes it different.**
> - **Verbatim, not summarized.** Hansard is the official transcript. We render it as a chat that's actually pleasant to read on a phone — same words, better surface.
> - **Sourced, end to end.** Every screen attributes its data to a named government publication and links to the original record. No inferred numbers, no estimated party positions, no chatbot summaries.
> - **Personal without being political.** A user enters a postal code; the app surfaces *their* MP's votes, speeches, expenses, and committee work. The frame is "what did this person do," not "which side is winning."
>
> **Built for Canada.** Canadian-developed, Canadian data, available in the Canadian App Store.
>
> Materials below: App Store URL, screenshots (6 × 1290×2796), App Preview video (30s, 886×1920, H.264), and a one-line value prop.
>
> Thank you for considering it.
>
> — Sunny Purewal · Riddim Software · sunny@riddimsoftware.com

---

## Seasonal angles

Substitute one of these into the **Why it's worth featuring right now** placeholder above, depending on the target window. Each is calibrated against epac's brand brief: clear, neutral, civic, plain-spoken, sourced.

### Election (federal general election or by-election)

> Voters who care about more than the horse race need a tool that shows what their MP actually said and how they actually voted, from the official record. epac is that tool. The app does not endorse parties, predict outcomes, or rank candidates. It surfaces verifiable facts during the period in which voters most need them.

### New parliamentary session (typically September or January)

> Parliament resumes [Month Year] with a new sitting calendar, an Order Paper full of government business, and committee work resuming across the House and Senate. epac follows the session in real time — Hansard, votes, bills, MP profiles — pulled from official sources within hours of publication. Featuring the app at the start of a session puts a verified-facts tool in front of the audience that is most actively re-engaging with civic news.

### Budget Day (federal budget, typically March or April)

> The federal budget is the most-watched single document in Canadian politics each year. epac is the only iPhone app that shows the budget commitments alongside the Auditor General's audits of past commitments — so users can see what was promised, what was funded, and what was delivered. Featuring on Budget Day puts the app in front of a search-and-discover audience that is actively looking for the budget.

### Evergreen civic engagement

> epac is the iPhone-native way to engage with Canada's federal government between elections. Postal code → your MP → their voting record, speeches, expenses, lobbying activity, and the bills they're working on. All from official sources, free, and built for Canadian users. Apple's "Apps for Democracy" and "Follow the News" curated collections are a natural fit; an App of the Day feature would put a civic-utility app in front of an audience that browses the App Store specifically for tools they hadn't yet discovered.

---

## App story angle (one paragraph)

For the App Store Connect Promotions form's **Story Angle** field:

> Canada's federal government produces a vast amount of public information every day — Hansard debates, recorded votes, MP expenses, committee evidence, audited financial reports — but it is scattered across a dozen government websites, formatted for desktop, and rarely reaches Canadians in a form they can act on. **epac brings all of it into a single iPhone app, presented as a clean group-chat reading view, with every figure traceable to an official source.** No commentary, no opinion, no AI-generated text — only verified records from Parliament of Canada, ourcommons.ca, the Office of the Auditor General, Statistics Canada, CMHC, IRCC, and Infrastructure Canada. It is a civic utility for Canadians who want to follow what their government actually does, not what people are saying about it.

---

## Three differentiation bullets

For the App Store Connect Promotions form's **Differentiation** field. Each bullet is one sentence and ends with the source-attribution beat:

- **Verbatim civic record.** Hansard, votes, MP expenses, and committee evidence rendered as a phone-readable chat — every word from the official record at ourcommons.ca and parl.ca.
- **Personal without partisan framing.** Postal code in, your MP out — speeches, votes, expenses, lobbying contacts. No score, no ranking, no party-line scoring system; the user reads the record and forms their own view.
- **Sourced end to end.** No LLM summaries. No inferred positions. Every stat carries the publishing department, dataset name, and vintage year. If the source can't prove it, the app doesn't show it.

---

## Materials

| Item | URL / Path |
|---|---|
| App Store listing (Canada) | https://apps.apple.com/ca/app/epac/id[FILL-IN-APP-ID] |
| App Store URL (general) | https://apps.apple.com/app/id[FILL-IN-APP-ID] |
| App Preview video (30s · 886×1920 · H.264 · iPhone 6.9") | `docs/marketing/preview/app-preview-final.mp4` (regenerated via `./scripts/marketing/record-app-preview.sh`, see EPAC-538) |
| Screenshots (6 × 1290×2796) | `docs/marketing/screenshots/` (produced under EPAC-109; uploaded to App Store Connect under en-CA) |
| Marketing site | https://epac.app |
| Press kit / contact | https://epac.app/press.html |

The App Preview video and screenshots are the same artifacts that ship with the App Store metadata pipeline (see `ios/fastlane/app-previews/en-CA/IPHONE_67_app-preview.mp4`). They do not need to be regenerated for the pitch; the operator can attach them directly.

---

## One-line value proposition

For any field that asks for a one-line summary of the app:

> Track your MP, bills, votes, and debates — verbatim from Canada's official parliamentary record.

Long form variant for fields that allow more text (matches the brand brief):

> epac helps Canadians track MPs, bills, votes, debates, expenses, and lobbying activity from official government sources.

---

## Timing

8 weeks of lead time is Apple's stated minimum for editorial submissions. The target windows below are the windows worth submitting against; "submit by" is 8 weeks before the window opens.

| Target window | Window opens | Submit by |
|---|---|---|
| New parliamentary session — fall 2026 | mid-September 2026 | mid-July 2026 |
| Federal Budget Day 2027 | typical late March – late April 2027 | late January – late February 2027 |
| New parliamentary session — winter 2027 | late January 2027 | late November 2026 |
| Federal general election (next fixed date) | October 20, 2025 (passed; next fixed date is October 19, 2026 if not called earlier) | August 24, 2026 |
| Evergreen | any | any |

If the operator can submit only one pitch in 2026, **submit by mid-July 2026 against the fall parliamentary session**: it lines up with naturally elevated civic-news interest, gives Apple the longest evaluation window before the target, and avoids competing with the simultaneous Budget-Day pitch wave.

---

## After submission

Per EPAC-179's AC, document the outcome in the project's GitHub Discussion thread:

- **Date submitted** (and via which channels)
- **Target window pitched against**
- **Apple's response** (accepted / declined / no response after 4 weeks)
- **If accepted**, the date Apple ran the feature and the install/visit lift observed in App Store Connect Analytics for the surrounding 7-day window
- **If declined or no response**, the next target window the operator plans to re-submit against

This thread is the institutional memory for future pitches. Apple's stated etiquette is to wait at least 8 weeks between re-pitches against different target windows.
