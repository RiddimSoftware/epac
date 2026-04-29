# Parliament Monthly Mailchimp Setup

EPAC-115 adds the website signup surfaces and the reusable monthly digest template. Complete these steps in Mailchimp before the first production send.

## Audience

- Audience name: `Parliament Monthly`
- Fields: email address only
- Double opt-in: enabled
- Tags:
  - `epac-website`
  - `parliament-monthly`

## Signup Forms

The committed website forms currently use a mailto fallback so the page does not ship a broken `MAILCHIMP_FORM_ACTION_URL` placeholder.

After the Mailchimp audience exists:

1. Open Mailchimp: Audience -> Signup forms -> Embedded forms.
2. Copy the generated form `action` URL.
3. Replace both website form actions:
   - `website/index.html`
   - `website/subscribe.html`
4. Replace the generic hidden `SOURCE` field with Mailchimp's generated anti-bot field, preserving the existing source attribution as a hidden merge field or tag.
5. Submit one test email from `/subscribe.html`.
6. Confirm the double opt-in email arrives.
7. Confirm the subscription appears in the `Parliament Monthly` audience with the `epac-website` tag.

## First Digest

1. Copy `docs/marketing/newsletter/template.md` to `docs/marketing/newsletter/issues/YYYY-MM.md`.
2. Fill every source link with primary sources only.
3. Send the issue to a Mailchimp test segment first.
4. Verify the unsubscribe link is present in the footer.
5. Send the campaign to the audience.

## Welcome Journey

Use `docs/marketing/newsletter/welcome-sequence.md` as the source of truth for
the three-email onboarding sequence.

1. Open Mailchimp: Automations -> Customer Journeys.
2. Create a journey named `Parliament Monthly welcome sequence`.
3. Set the starting point to `Subscribed to Parliament Monthly`.
4. Add Email 1 with a 0-day delay.
5. Add a 3-day delay, then Email 2.
6. Add a 4-day delay, then Email 3.
7. Confirm the three App Store links use `utm_medium` values:
   - `newsletter-welcome-1`
   - `newsletter-welcome-2`
   - `newsletter-welcome-3`
8. Send a test subscription through the website form.
9. Confirm Email 1 arrives immediately, Email 2 after 3 days, and Email 3 after
   7 days.
10. Review and refresh stale facts during the monthly growth report process.

## Privacy Checks

- Do not add name, postal code, riding, demographic, or tracking fields.
- Keep the app account-free; the newsletter list is website-only.
- The footer copy must always include an unsubscribe link and the privacy policy link.
