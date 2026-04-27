# App Store Creative Brief — EPAC-300

**For:** Screenshots (EPAC-301), App Preview video (EPAC-305)  
**Version:** 1.0 — 2026-04-27  
**Device format required:** iPhone 6.9" (1290×2796px) — mandatory. Also produce iPhone 6.1" and iPad 13" if time allows.

---

## The brief in one sentence

Tell the story: _Parliament is doing things that affect you right now — here's how to know_.

---

## Research foundation

- **StoreMaven**: screenshots account for 50%+ of the App Store conversion decision. 70% of visitors decide after seeing only the first 2 screenshots.
- **Thomas Petit (AppTweak)**: "Screenshot 1 is a second title. It must answer 'why download this?' before the user reads anything else."
- **Gabe Kwakyi (Incipia)**: "The narrative arc — know → understand → act — outperforms a list of features."
- **Apple guidelines**: show actual app UI. Lifestyle imagery without UI underperforms for utility apps.

**Implication**: the first screenshot is the most important asset we have. It must communicate the core hook in under 2 seconds of scanning.

---

## Narrative arc across 6 screenshots

**Emotional hook**: _Your government is doing things right now that affect you, and you don't know about them._

**Story**: "They're doing things without you knowing → here's what you've been missing → now you can know → and act"

| # | Scene | Headline | Purpose |
|---|-------|----------|---------|
| 1 | Hook | "Parliament voted last night." | Answer: what is this app for? |
| 2 | Debates | "Read every word they said." | Feature depth — Hansard in chat format |
| 3 | My MP | "Everything your MP has done." | Personalization hook — postal code value |
| 4 | Bills | "Track a bill start to finish." | Accountability feature — bill timeline |
| 5 | Votes | "See who voted which way." | Accountability feature — voting records |
| 6 | Action | "Contact them in one tap." | Civic action — close the loop |

---

## Screenshot specifications

### Screenshot 1 — The hook

**Headline (large, top):** `Parliament voted last night.`  
**Sub-caption (smaller, below headline):** `Find out how your MP voted — and what they said before the vote.`  
**Screen shown:** Voting record tab with a real vote (e.g., a budget vote), MP name visible, Yea/Nay clearly shown  
**Design note:** Headline should occupy ≥30% of image height. Use Outfit Bold. Brand blue (#0071E3) accent.

### Screenshot 2 — Hansard debates

**Headline:** `Read every word they said.`  
**Sub-caption:** `The official Hansard transcript — in a format you can actually read.`  
**Screen shown:** SpeechView with a recognizable debate, party colours visible in chat bubbles, MP names shown  
**Design note:** Show the chat metaphor clearly — two or three speakers alternating

### Screenshot 3 — My MP

**Headline:** `Everything your MP has done.`  
**Sub-caption:** `Enter your postal code. Get your representative. See their votes, speeches, and expenses.`  
**Screen shown:** MyMPView or HomeFeedView with MP name, recent activity list (vote + speech + expense)  
**Design note:** Show the personalization — a real MP name, real riding name

### Screenshot 4 — Bills

**Headline:** `Track a bill start to finish.`  
**Sub-caption:** `From introduction to Royal Assent — with the PBO cost estimate and every vote.`  
**Screen shown:** BillDetailView with stage timeline, PBO cost badge visible, Follow button  
**Design note:** The timeline/progress indicator is the key visual — make it prominent

### Screenshot 5 — Voting records

**Headline:** `See who voted which way.`  
**Sub-caption:** `Every recorded division in the House of Commons, searchable by MP, party, or bill.`  
**Screen shown:** VoteDetailView or MemberVotingRecordView with Yea/Nay distribution clearly visible  
**Design note:** The party colour coding makes this visually compelling — show it

### Screenshot 6 — Contact

**Headline:** `Contact them in one tap.`  
**Sub-caption:** `Send your MP an email about any vote or debate — pre-filled from the parliamentary record.`  
**Screen shown:** Contact compose sheet with pre-filled subject and body referencing a real vote  
**Design note:** Show the one-tap → compose flow; the context-aware pre-fill is the differentiator

---

## Typography

- **Headline font**: Outfit Bold or Outfit ExtraBold, white or dark depending on background
- **Sub-caption font**: Inter Regular or Medium, slightly smaller, with opacity reduction
- **Avoid**: system fonts, all-caps except short labels, more than 2 font weights per screenshot

## Colour palette

| Use | Hex |
|-----|-----|
| Primary blue | #0071E3 |
| Liberal red | #D01D1D |
| Conservative blue | #003F7D |
| NDP orange | #E67E00 |
| Green | #007D3C |
| BQ teal | #00A4B0 |

---

## App Preview video brief

**Duration:** 25–30 seconds (App Store maximum 30s)  
**Format:** H.264, recorded at 1290×2796 via `xcrun simctl io booted recordVideo`  
**No device frame** (Apple requirement)

**Scene sequence:**

| Time | Scene | What to show |
|------|-------|-------------|
| 0:00–0:05 | Home feed | App launches, Home feed with today's parliamentary activity visible |
| 0:05–0:12 | Debates | Tap a debate → SpeechView scrolling, party colours in chat bubbles |
| 0:12–0:18 | My MP | MP profile → voting record tab, Yea/Nay history |
| 0:18–0:23 | Bill detail | Bill stage timeline, PBO cost badge, Follow button tap with haptic |
| 0:23–0:28 | Contact | Contact sheet opens → filled → send animation |

**No narration required.** Background music optional (recommended: subtle, modern, Canadian content if possible).

---

## Production checklist

- [ ] All screenshots show **real parliamentary data** — no placeholder names, no lorem ipsum
- [ ] iPhone 6.9" at 1290×2796px exported
- [ ] Each screenshot saved to `docs/marketing/screenshots/` with descriptive filename
- [ ] App Preview video recorded and saved to `docs/marketing/preview/`
- [ ] Uploaded to App Store Connect alongside new version submission
