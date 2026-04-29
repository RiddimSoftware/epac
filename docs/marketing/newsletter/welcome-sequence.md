# Parliament Monthly Welcome Sequence

EPAC-343 defines the three-email welcome journey for new Parliament Monthly
subscribers. The sequence introduces epac, explains why official public data is
useful, and moves subscribers toward the App Store without adding extra profile
fields or app accounts.

## Mailchimp Journey

Audience: `Parliament Monthly`

Trigger: contact subscribes to the audience, including subscribers tagged
`epac-website`.

Steps:

1. Send Email 1 immediately after subscription confirmation.
2. Wait 3 days.
3. Send Email 2.
4. Wait 4 days.
5. Send Email 3.

Exit rule: unsubscribe exits the journey immediately.

Privacy rule: do not add name, postal code, riding, demographic, or app-behavior
fields. The journey is driven only by newsletter subscription status.

## Campaign Links

Use the canonical App Store fallback URL until App Store Connect campaign links
are created. Each email uses the same `ct` campaign and a different
`utm_medium`, as required by EPAC-343.

| Email | Campaign URL |
| --- | --- |
| Welcome 1 | `https://apps.apple.com/ca/app/epac/id6739397803?ct=epac-newsletter-welcome&mt=8&utm_source=mailchimp&utm_medium=newsletter-welcome-1&utm_campaign=welcome-sequence` |
| Welcome 2 | `https://apps.apple.com/ca/app/epac/id6739397803?ct=epac-newsletter-welcome&mt=8&utm_source=mailchimp&utm_medium=newsletter-welcome-2&utm_campaign=welcome-sequence` |
| Welcome 3 | `https://apps.apple.com/ca/app/epac/id6739397803?ct=epac-newsletter-welcome&mt=8&utm_source=mailchimp&utm_medium=newsletter-welcome-3&utm_campaign=welcome-sequence` |

## Email 1: Day 0

Subject: Welcome to epac -- Parliament in your inbox

Preview text: A short monthly digest, plus the app for following what your MP
does between issues.

Body:

You are signed up for Parliament Monthly, a short digest of what Canada's
Parliament did in the last month. epac is the free iPhone app behind it: it
pulls together official House of Commons data, MP profiles, votes, debates,
bills, and lobbying records in one place.

One example from the record: on April 27, 2026, MPs resumed third-reading
debate on Bill C-225, An Act to amend the Criminal Code, and debated
Government Business No. 9 on changes to the Standing Orders.

If you want to follow debates before the next monthly email arrives, download
epac and look up your MP.

Download epac:
https://apps.apple.com/ca/app/epac/id6739397803?ct=epac-newsletter-welcome&mt=8&utm_source=mailchimp&utm_medium=newsletter-welcome-1&utm_campaign=welcome-sequence

Source: House of Commons Debates, April 27, 2026.

Word count: 134

## Email 2: Day 3

Subject: Did you know your MP's lobbying meetings are public?

Preview text: Canada's lobbying records are public. epac makes them easier to
check from your phone.

Body:

Lobbying meetings with federal officials are public records. The Registry of
Lobbyists records who communicated, when they communicated, and the subject
area reported by the registrant.

For example, Google Canada Corporation reported a March 31, 2026 communication
with one MP, Lisa Hepfner. The listed subjects were justice and law enforcement,
science and technology, and privacy and access to information.

That does not tell you whether a meeting was good or bad. It gives you a
verifiable starting point: who met whom, about what, and when.

In epac, open your MP profile to see official government records in context.

See who's lobbying your MP:
https://apps.apple.com/ca/app/epac/id6739397803?ct=epac-newsletter-welcome&mt=8&utm_source=mailchimp&utm_medium=newsletter-welcome-2&utm_campaign=welcome-sequence

Source: Office of the Commissioner of Lobbying communication report for Google
Canada Corporation, posted April 15, 2026.

Word count: 167

## Email 3: Day 7

Subject: What Parliament did this week

Preview text: Five official-record highlights from the House of Commons, plus
where to follow the details.

Body:

Here are five things from the most recent House of Commons sitting week:

1. The House sat on April 20, 21, 22, 23, 24, and 27.
2. MPs resumed third-reading debate on Bill C-225, An Act to amend the Criminal
   Code.
3. Government Business No. 9 dealt with the membership and composition of
   standing committees.
4. Bill C-29, the Financial Crimes Agency Act, was introduced on April 27.
5. The House continued routine proceedings, private members' business, and
   bill-stage debate across the week.

Parliamentary work is often procedural, but the record matters: bills move,
committees form, MPs speak, and votes create accountability.

Follow these debates in real time in epac:
https://apps.apple.com/ca/app/epac/id6739397803?ct=epac-newsletter-welcome&mt=8&utm_source=mailchimp&utm_medium=newsletter-welcome-3&utm_campaign=welcome-sequence

Sources: House of Commons sitting calendar and House of Commons Debates for
April 20 to April 27, 2026.

Word count: 151

## Source Log

Use primary sources only when refreshing this sequence:

- House of Commons Debates: https://www.ourcommons.ca/documentviewer/en/45-1/house/sitting-111/hansard
- House of Commons sitting calendar: https://www.ourcommons.ca/en/sitting-calendar
- LEGISinfo Bill C-29: https://www.parl.ca/legisinfo/en/bill/45-1/c-29
- Registry of Lobbyists communication reports:
  https://www.lobbycanada.gc.ca/app/secure/ocl/lrs/do/rgstrnCmmnctnRprts?lang=eng&regId=966376

## Monthly Refresh Checklist

Complete this during the monthly growth report process:

- Confirm all App Store links still resolve and preserve the three
  `utm_medium` values.
- Replace Email 1's parliamentary example if it is older than 45 days.
- Replace Email 2's lobbying example if it is older than 90 days.
- Replace Email 3 with the most recent complete sitting week.
- Recheck every factual sentence against the primary source linked in the
  source log.
- Send the journey to an internal test address before reactivating edited
  emails.
