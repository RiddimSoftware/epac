# Social account setup checklist

One-time operator checklist for standing up the epac Bluesky and X accounts
referenced in `calendar.md`. Once both accounts exist and the URLs in this
file resolve, this checklist can be archived.

## Prerequisites

- Access to a working email address dedicated to social (suggest
  `social@epac.app` or whatever the canonical brand inbox is).
- A copy of the brand assets: `website/epac-icon-light.png` for the dark-mode
  avatar, `website/epac-icon-dark.png` for light-mode preview, and
  `website/og-image.png` for the X header image.
- 5 minutes per account.

## Bluesky — `@epac.bsky.social`

1. Sign up at bsky.app with the social inbox email.
2. Reserve handle: `epac.bsky.social` (the default `*.bsky.social` is fine
   for v1; a custom domain handle like `epac.app` can come later via
   well-known/atproto-did).
3. Profile image: `website/epac-icon-light.png` (1500×1500 export).
4. Banner: `website/og-image.png` (1500×500 crop).
5. Display name: `epac`.
6. Bio (240 char Bluesky limit):

   ```
   Canada's Parliament, in your pocket. Hansard, voting records, MP
   expenses — verbatim from official sources, no commentary. Free on
   iPhone: https://apps.apple.com/ca/app/epac/id...
   ```

7. Pinned link in bio: App Store URL.
8. Settings → Privacy: turn off discoverability via email; leave reply
   defaults at "Everyone".
9. Verify the account loads at https://bsky.app/profile/epac.bsky.social.

## X / Twitter — `@epac_ca`

1. Sign up at x.com with the social inbox email.
2. Reserve handle: `@epac_ca` (the bare `@epac` is taken; `_ca` is
   acceptable per the EPAC-138 ticket).
3. Profile image: `website/epac-icon-light.png` (400×400 export).
4. Banner: `website/og-image.png` (1500×500 crop).
5. Display name: `epac`.
6. Bio (160 char X limit):

   ```
   Canada's Parliament — Hansard, votes, MP expenses. From official
   sources. Free on iPhone. epac.app
   ```

7. Website link: https://epac.app
8. Settings → Privacy and safety: protect tweets OFF, "show photo tags"
   OFF, "discoverability via email/phone" OFF.
9. Verify the account loads at https://x.com/epac_ca.

## After both accounts exist

1. Update `website/index.html` footer if the placeholder URLs differ from
   the actual handles. Search for `bsky.app/profile/epac.bsky.social` and
   `x.com/epac_ca`.
2. Run a single follow-up PR to add the social links to the other website
   pages with footers (`features.html`, `faq.html`, `press.html`,
   `educators.html`, `privacy.html`, `subscribe.html`, `bill/index.html`,
   `vote/index.html`, `app/index.html`, the `blog/*.html` pages). The
   index.html footer is the only one updated in EPAC-138's PR.
3. Schedule the 10 launch posts from `calendar.md` over the first week —
   one per day, no more than two per day.

## Recovery / 2FA

- 2FA: enable on both accounts using the team's password manager TOTP
  vault.
- Recovery codes: store in the team password manager under
  `social/bluesky-recovery` and `social/x-recovery`.
- Email forwarding: the social inbox should forward to the operator and one
  backup so a forgotten-password loop doesn't lock out the account.

## What this checklist does not cover

- Cross-posting tooling. Manual is fine for the first 10 posts; automation
  is tracked as a follow-up to EPAC-138.
- Paid promotion. Out of scope.
- Verification badges. Apply only after the cadence is proven for at least
  4 weeks.
