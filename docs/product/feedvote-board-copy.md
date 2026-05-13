# Feedvote Board Copy and Seed Requests

**Issue:** EPAC-1772

## Live Board / Publishing Evidence

**Public board URL:** https://epac.feedvote.app/

**Linear backlog-state check:** Before submitting the seed requests, I searched Linear for the exact proposed request titles and for close matches across Hansard summaries, bill milestone notifications, MP vote filters, MP speech notifications, promise tracking, home feed customization, accessibility text sizing, and bill keyword search. I found related epac backlog items, but no matching requests in **Done** or **In Progress**. The closest matches I checked were still backlog/Todo items, including EPAC-1035 (Todo), EPAC-1229 (Todo), EPAC-1130 (Todo), and EPAC-961 (Todo).

**Feedvote submission status (2026-05-13T05:34Z):** The public Feedvote board accepts anonymous submissions but currently has moderation enabled (`requireApproval: true`). I submitted the eight seed requests through `POST https://api.feedvote.app/public/epac/feedback`; Feedvote returned `201` for each request with `status: backlog`, `votesCount: 1`, and `moderationStatus: pending`. Because pending requests are not visible on the public board, a Feedvote admin must approve these requests before the Definition of Done is fully satisfied.

Submitted Feedvote IDs:

| Request | Feedvote ID | Moderation |
|---|---|---|
| Plain-language summaries of debates | `cmp3mk9k40yboo10w4coi3zhe` | pending |
| Notifications for bill milestones | `cmp3mkqi80ybso10wjroabmuf` | pending |
| Filter MP voting records by topic | `cmp3mkqmm0ybwo10wjkd9v40e` | pending |
| Push notifications for MP speeches | `cmp3mkqqx0yc0o10wq514183q` | pending |
| Track governing party election promises | `cmp3mkqv90yc4o10w8nyks7gu` | pending |
| Customize home feed regions and committees | `cmp3mkqzo0yc8o10w0jg26e74` | pending |
| Ajuster la taille du texte | `cmp3mkr3z0ycco10wt9ri970u` | pending |
| Recherche de projets de loi par mot-clé | `cmp3mkr8d0ycgo10wk13rnrgr` | pending |

**Remaining external gate:** Update the Feedvote board presentation copy in the Feedvote admin settings and approve the pending submissions so the header, welcome message, prompt, and 8+ requests are publicly visible.

## Board Copy

**Header / Tagline:**
Vote for features in Canada's Parliament app.

**Welcome Message:**
Welcome to the epac feature board. We are building the easiest way to track your MP, bills, and parliamentary debates from official sources. Your votes tell us what to build next—top-requested features are prioritized in our public roadmap and added to the app.

**Submission Form Prompt:**
What feature would help you better track Parliament? Please describe what you want to see and why it matters to you.

## Seeded Feature Requests

### 1. Hansard & Debates
**Title:** Plain-language summaries of debates
**Description:** "I want to see plain-language summaries of Hansard debates so I can understand what was discussed without reading the full transcript."

### 2. Bills
**Title:** Notifications for bill milestones
**Description:** "I want to be notified when a bill I follow reaches third reading, so I know when it is about to pass."

### 3. Members & Votes
**Title:** Filter MP voting records by topic
**Description:** "I want to filter my MP's voting record by topic (e.g., housing, climate) so I can see how they vote on issues I care about."

### 4. Notifications
**Title:** Push notifications for MP speeches
**Description:** "I want to receive a push notification when my MP speaks in the House of Commons."

### 5. Promise Tracker
**Title:** Track governing party election promises
**Description:** "I want to track the status of election promises made by the governing party to see if they are being fulfilled."

### 6. Home Feed
**Title:** Customize home feed regions and committees
**Description:** "I want to customize my home feed to only show updates from specific committees and regions."

### 7. Accessibility (fr-CA)
**Title:** Ajuster la taille du texte
**Description:** "Je veux pouvoir ajuster la taille du texte dans l'application pour rendre la lecture des longs débats parlementaires plus facile."

### 8. Search (fr-CA)
**Title:** Recherche de projets de loi par mot-clé
**Description:** "Je veux une fonction de recherche qui me permet de trouver des projets de loi par mot-clé plutôt que par numéro."
