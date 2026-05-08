# EPAC-1744 repo launch handoff

This file captures the exact repo-level metadata and seeded `good first issue` drafts for the EPAC open-source launch surface.

## Repository settings

Apply these values on `RiddimSoftware/epac`:

- **Description:** `Canadian Hansard debates as a group-chat — civic-engagement iOS app`
- **Homepage:** `https://epac.riddimsoftware.com/`
- **Topics:** `ios`, `swift`, `civic-tech`, `canada`, `parliament`, `hansard`, `open-source`
- **Issues:** enabled
- **Discussions:** disabled
- **Social preview image:** `docs/brand/github-social-preview-1280x640.png`

## Social preview asset

Regenerate the 1280×640 asset with:

```bash
scripts/marketing/generate_github_social_preview.sh
```

Output path:

```text
docs/brand/github-social-preview-1280x640.png
```

## Seeded good first issues

The live GitHub issues seeded for this launch are:

- #384 — `Localize SittingCalendarView accessibility labels and hints`
- #385 — `Localize HomeFeedView accessibility labels for today card and followed bills`
- #386 — `Localize Toronto and Vancouver councillor card accessibility labels`

Each issue below is intentionally scoped to about 1–2 hours for a first-time contributor and should carry the `good first issue` label on GitHub.

---

### 1. Localize hardcoded accessibility copy in `SittingCalendarView`

**Title**

```text
Localize SittingCalendarView accessibility labels and hints
```

**Body**

```md
## Context

`ios/epac/Views/Calendar/SittingCalendarView.swift` still contains several hardcoded English accessibility strings alongside otherwise localized UI copy. A first-time contributor can make this screen more consistent for VoiceOver users by moving those strings into `Localizable.strings` and wiring the view to use them.

## Acceptance criteria

- Replace the hardcoded English accessibility strings in `SittingCalendarView.swift` with localization keys.
- Add matching entries to both `ios/epac/en.lproj/Localizable.strings` and `ios/epac/fr.lproj/Localizable.strings`.
- Cover the Today / Upcoming legend, year navigation, and refresh/loading controls that currently use string literals.
- Run `python3 scripts/localization/check_localizations.py --github-warnings` and confirm no missing keys.
- Run `swiftlint --strict ios/epac/Views/Calendar/SittingCalendarView.swift` and confirm zero violations.

## Out of scope

- Redesigning the calendar UI.
- Refactoring unrelated calendar logic.
```

---

### 2. Localize hardcoded accessibility copy in `HomeFeedView`

**Title**

```text
Localize HomeFeedView accessibility labels for today card and followed bills
```

**Body**

```md
## Context

`ios/epac/Views/Home/HomeFeedView.swift` mixes localized UI copy with a few hardcoded accessibility labels and hints. This is a good small starter task because the affected strings are clustered in one file and can be verified with the localization audit plus SwiftLint.

## Acceptance criteria

- Replace the hardcoded accessibility hint for the Today card's Parliament navigation.
- Replace the hardcoded accessibility label for followed-bill rows.
- Replace the hardcoded accessibility label for the "Unfollow all bills" button.
- Add matching keys to both English and French `Localizable.strings` files.
- Run `python3 scripts/localization/check_localizations.py --github-warnings` and confirm no missing keys.
- Run `swiftlint --strict ios/epac/Views/Home/HomeFeedView.swift` and confirm zero violations.

## Out of scope

- Rewriting the Today card content model.
- Broader Home feed IA or design changes.
```

---

### 3. Localize councillor-card accessibility copy for Toronto and Vancouver

**Title**

```text
Localize Toronto and Vancouver councillor card accessibility labels
```

**Body**

```md
## Context

The Toronto and Vancouver councillor cards (`ios/epac/Views/Toronto/TorontoCouncillorCard.swift` and `ios/epac/Views/Vancouver/VancouverCouncillorCard.swift`) still build their accessibility labels with hardcoded English suffixes like "City of Toronto" and "City of Vancouver". This is a contained two-file localization cleanup.

## Acceptance criteria

- Replace the hardcoded English accessibility label strings in both councillor card views with localized keys.
- Preserve the current meaning and dynamic data (role, name, ward/party).
- Add matching entries to both English and French `Localizable.strings` files.
- Run `python3 scripts/localization/check_localizations.py --github-warnings` and confirm no missing keys.
- Run `swiftlint --strict ios/epac/Views/Toronto/TorontoCouncillorCard.swift ios/epac/Views/Vancouver/VancouverCouncillorCard.swift` and confirm zero violations.

## Out of scope

- Visual redesign of the councillor cards.
- New data fields or party-color changes.
```

---

### 4. Localize hardcoded accessibility copy in `SpeechView` and `ExplainerCard`

**Title**

```text
Localize chat-toolbar and explainer accessibility copy
```

**Body**

```md
## Context

The debate chat surface still has a few hardcoded English accessibility strings in `ios/epac/Views/Chat/SpeechView.swift` and `ios/epac/Views/Common/ExplainerCard.swift`. This task keeps the scope small while improving consistency for VoiceOver users.

## Acceptance criteria

- Replace the hardcoded accessibility labels for the restart/share toolbar buttons in `SpeechView.swift` with localized keys.
- Replace the hardcoded `What is …?` accessibility label in `ExplainerCard.swift` with a localized format string.
- Add matching entries to both English and French `Localizable.strings` files.
- Run `python3 scripts/localization/check_localizations.py --github-warnings` and confirm no missing keys.
- Run `swiftlint --strict ios/epac/Views/Chat/SpeechView.swift ios/epac/Views/Common/ExplainerCard.swift` and confirm zero violations.

## Out of scope

- Changes to the debate playback model.
- Copy rewrites beyond localization plumbing.
```

---

### 5. Remove the force-unwrapped Vancouver votes source URL

**Title**

```text
Remove the force-unwrapped source URL in VancouverVotesView
```

**Body**

```md
## Context

`ios/epac/Views/Vancouver/VancouverVotesView.swift` still force-unwraps the Vancouver open-data source URL inside a SwiftUI `Link`. It already has a targeted SwiftLint suppression, which makes this a good first issue: small, real, and easy to verify.

## Acceptance criteria

- Remove the `!` URL force unwrap in `VancouverVotesView.swift`.
- Remove the matching SwiftLint suppression comment.
- Keep the source link visible when the URL is valid.
- If you introduce a fallback path for an invalid URL, make sure the view still builds cleanly and degrades gracefully.
- Run `swiftlint --strict ios/epac/Views/Vancouver/VancouverVotesView.swift` and confirm zero violations.

## Out of scope

- Refactoring the rest of the Vancouver votes screen.
- Changing the destination URL.
```
