# Sprint-001 Release Notes — 2026-04-27

## Build status
- **iOS build:** `** BUILD SUCCEEDED **` confirmed on simulator FCFAF817-6694-402D-B116-A86EDAF34237 (iPhone 17)
- **TestFlight upload:** ⚠️ Pending — run `cd ios && bundle exec fastlane deploy` before App Store submission

## Release candidate
- **Branch:** `main` at commit `d453677`
- **Version bump:** To be set in Xcode before TestFlight upload

## Changelog (user-facing)

### New features
- **Settings screen**: Manage your location, notification preferences, followed bills/members/topics, and app appearance from a single screen. Access via the profile icon on the Home tab.
- **Fiscal Monitor**: Federal revenue and spending data from Finance Canada, updated monthly. Find it in the Accountability tab.
- **Vancouver City Council**: Council votes and My City Councillors section (join Toronto and Ontario legislature coverage).
- **Federal contracts database**: Government vendor spending by department via proactive disclosure.
- **New bills badge**: Bills introduced since your last app open get a blue dot so you don't miss them.
- **MP speech feed**: Full paginated speech history on every MP profile page, with topic filters.

### Improvements
- **Network resilience**: Every data fetch now uses exponential backoff (1s/2s/4s, 3 retries). Offline banner appears at the bottom when disconnected. Cached data always shown — no blank screens.
- **Retry buttons**: Debounced 2 seconds to prevent hammering a struggling server.
- **Snapshot tests**: Visual regression tests for 5 view types × 3 configurations (light/dark/accessibility large text) run on every PR.

### Developer / App Store assets
- 6 App Store screenshots (1290×2796) in `docs/marketing/screenshots/epac-109/`
- App Preview video mode: launch with `-AppPreviewVideo` to record the 6-scene showcase
- Newsletter signup form on website; digest template at `docs/marketing/newsletter/template.md`
- Brand brief at `docs/marketing/` (tagline, voice & tone, anti-positioning)
- Open Graph image on website homepage for social sharing

## Evidence links
- Build screenshots: `docs/build-evidence/EPAC-133-running.png`, `EPAC-110-preview-mode.png`
- PR list: #130, #135, #139, #171–#175, #178–#180, #182–#183

## Pending human actions before App Store submission
1. `cd ios && bundle exec fastlane deploy` to upload TestFlight build
2. Upload `docs/marketing/screenshots/epac-109/` to App Store Connect (re-capture on iPhone 16 Pro Max / 17 Plus for 6.9" slot)
3. Record and upload App Preview video (EPAC-110 — 30s, `xcrun simctl io booted recordVideo`)
4. Replace Mailchimp placeholder form actions (EPAC-115 — see `docs/marketing/newsletter/mailchimp-setup.md`)
5. Complete Sprint-001 in Jira board UI → Start Sprint-002
