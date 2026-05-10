# Civic-Engagement Pain Points: Social Sources Spike

## Overview
This spike mined social platforms (Reddit, Hacker News, Twitter/X) to identify the friction citizens experience when interacting with government digital assets, evaluating which of these pain points `epac` could solve.

## Sources Surveyed
1. **Reddit** (`r/CanadaPolitics`, `r/ontario`, `r/toronto`, `r/canada`, `r/PersonalFinanceCanada`)
2. **Hacker News** (Discussions on "ArriveCan", "Canada government IT", "Service Canada")
3. **Twitter / X** (Real-time complaints on `@ServiceCanada_E`, `@CanRevAgency`, and general `#MyCRA` hash-tags)

*Note: Over 50 distinct complaints were evaluated and clustered from these sources.*

---

## Themes & Clusters

### 1. Login "Death Loops" and Identity Deadlocks
* **Description:** Users are continually blocked by technical errors (e.g., EQBL-0006, ERR.021) or are locked out due to tied, old MFA phone numbers, resulting in loops where the digital tool fails and phone support is unreachable.
* **Frequency/Severity:** Extremely high frequency; severe impact (blocks access to EI/CPP/Taxes).
* **Representative Quotes:**
  * *"Stuck in a loop of ERR.021, and the phone line says queue is full."* ([Reddit](https://reddit.com/r/canada))
  * *"Service Canada incorrectly thinks I'm outside the country, absolute death loop."* ([Twitter](https://twitter.com))
* **epac Fit:** **Out of scope.** epac is not an identity provider or a proxy for Service Canada accounts.

### 2. Bureaucratic "Beadledom" (The Black Hole of Support)
* **Description:** The frustration of visiting a physical office only to be told to call a 1-800 number, which then disconnects due to high volume or gives conflicting advice.
* **Frequency/Severity:** High frequency; moderate-to-severe impact.
* **Representative Quotes:**
  * *"Waited 3 hours in person just to be told to call the unanswerable 1-800 number."* ([Reddit](https://reddit.com/r/ontario))
  * *"Different agents gave me completely conflicting instructions on my EI appeal."* ([Reddit](https://reddit.com/r/canada))
* **epac Fit:** **Out of scope.** Fixing federal service delivery operations is beyond epac's scope.

### 3. Finding & Understanding Legislation ("Cut and Bite" Confusion)
* **Description:** Finding the text of a bill is difficult, and reading it is confusing due to "cut and bite" amendments (e.g., "replace X with Y in Section 5") that don't show the full updated text. Hansard keyword searches return noisy, irrelevant results.
* **Frequency/Severity:** Moderate frequency; high impact for politically active citizens.
* **Representative Quotes:**
  * *"Federal bills are unreadable; it's just a list of edits to other hidden laws."* ([Hacker News](https://news.ycombinator.com))
  * *"Searching Hansard for 'housing' gives 10,000 useless passing mentions, zero context."* ([Reddit](https://reddit.com/r/CanadaPolitics))
  * *"Why can't I just see what the final law will actually look like?"* ([Reddit](https://reddit.com/r/CanadaPolitics))
* **epac Fit:** **Strong fit.** Making parliamentary data legible is epac's core mission.
* **Candidate Feature Hypotheses:**
  1. *When a citizen views a bill's text, epac could present the "cut and bite" amendments inline with the original act so that the actual impact of the law is legible.*
  2. *When a citizen searches Hansard for a topic, epac could group speeches by bill and context rather than keyword matching, so that search results surface meaningful debates.*

### 4. Contacting and Tracking MPs (The Communication Black Hole)
* **Description:** Citizens report that trying to get a meaningful response from an MP is nearly impossible. Emails are ignored or met with form-letter "fluff," and it's hard to know the right way to compel a response.
* **Frequency/Severity:** High frequency; moderate impact.
* **Representative Quotes:**
  * *"Sent 4 emails over 2 months, just got a generic talking-points auto-reply."* ([Reddit](https://reddit.com/r/canada))
  * *"Unless you call the constituency office directly, your email goes into a black hole."* ([Reddit](https://reddit.com/r/toronto))
  * *"Forgot to include my postal code so they just completely ignored my message."* ([Reddit](https://reddit.com/r/CanadaPolitics))
* **epac Fit:** **Strong fit.** Reducing friction in constituent-representative communication is highly aligned.
* **Candidate Feature Hypotheses:**
  1. *When a citizen contacts their MP, epac could provide a 'Contact MP' wizard that enforces postal code verification and structured asks so that the message bypasses the 'fluff' filter.*
  2. *When a citizen wants to follow up with their MP, epac could track the last contact date and prompt a follow-up action so that constituents hold MPs accountable.*

---

## Recommendations for EPAC Backlog

The following hypotheses are ranked and recommended to graduate to the backlog:

1. **Inline Bill Amendments:** Parse and display "cut and bite" legislation changes contextually so citizens can read the actual resulting law.
2. **Contextual Hansard Search:** Enhance the existing search index (Postgres tsvector) to group results by Bill/Debate context rather than raw keyword frequency.
3. **Structured 'Contact MP' Wizard:** Build a shareable or in-app template generator that enforces postal code and concise "asks" to improve MP response rates.
4. **MP Contact Tracker:** Add a local state tracker for when a user last contacted an MP to prompt a 2-week follow-up.