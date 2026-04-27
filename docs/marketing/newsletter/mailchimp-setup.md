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

## Privacy Checks

- Do not add name, postal code, riding, demographic, or tracking fields.
- Keep the app account-free; the newsletter list is website-only.
- The footer copy must always include an unsubscribe link and the privacy policy link.
