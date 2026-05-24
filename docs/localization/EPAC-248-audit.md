# EPAC-248 French Localization Audit

Date: 2026-04-28

## Scope

Audited the iOS app's explicit localization keys:

- `NSLocalizedString("...")`
- `String(localized: "...")`
- `ios/epac/en.lproj/Localizable.strings`
- `ios/epac/fr.lproj/Localizable.strings`

SwiftUI literal `Text("...")` values are not fully enforced by this first-pass audit because many are static demo, preview, data, or brand strings. The CI warning step focuses on explicit localization APIs first.

## Baseline Finding

Before the fix:

- English table: 555 keys
- French table: 528 keys
- French coverage of the English table: 95.1%
- Missing French keys: 27

The missing keys were concentrated in notification settings and per-member notification controls.

## After Fix

After adding the missing notification translations:

- Explicit source keys: 437
- English table: 567 keys
- French table: 567 keys
- French coverage of the English table: 100.0%
- Missing explicit source keys in English: 0
- Missing explicit source keys in French: 0

The final count includes existing party labels that were already localized through `NSLocalizedString` in the model layer but were not present in either language table.

## CI Guardrail

`.github/workflows/swiftlint.yml` now includes a Linux localization audit job that runs:

```bash
python3 scripts/localization/check_localizations.py --github-warnings
```

The job emits GitHub Actions warnings for missing explicit localization keys or duplicate keys, but does not fail the build yet. This matches EPAC-248's initial "warning, not error" acceptance criterion.
