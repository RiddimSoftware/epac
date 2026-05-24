# App Store Promotional Text History

Promotional text can be updated at any time in App Store Connect without submitting a new app version.
Maximum 170 characters.

## Current

**Date:** 2026-05-07
**Text:** Parliament is sitting. Follow every vote, read every debate, track every bill — verified from Hansard and official sources. Updated daily.

**Monthly refresh hook:** Automated via `.github/workflows/aso-staleness-check.yml`. The scheduled check runs daily; if the text is older than 30 days, contains stale factual wording, or claims "Parliament is sitting" during an adjournment (verified via the House of Commons calendar), it automatically files a Linear ASO refresh task.

## Archive

### 2026-04-27
**Text:** Canada's 45th Parliament is sitting. Follow every vote, read every debate, track every bill — verified from official sources. Free.

### Pre-2026-04-27
**Text:** Follow Parliament in real time. Track your MP's votes, read today's Hansard debates, and stay informed on every bill — straight from official sources.
