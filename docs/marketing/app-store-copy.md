# App Store Promotional Text History

Promotional text can be updated at any time in App Store Connect without submitting a new app version.
Maximum 170 characters.

## Current

**Date:** 2026-05-07
**Text:** Parliament is sitting. Follow every vote, read every debate, track every bill — verified from Hansard and official sources. Updated daily.

**Monthly refresh hook:** Run `python3 scripts/marketing/check_promotional_text_staleness.py --create-linear-issue` during the ASO scorecard / monthly report cycle. If the text is older than 30 days or contains stale factual wording, this will automatically file a Linear ASO refresh task. Ensure `LINEAR_API_KEY` is set in your environment.

## Archive

### 2026-04-27
**Text:** Canada's 45th Parliament is sitting. Follow every vote, read every debate, track every bill — verified from official sources. Free.

### Pre-2026-04-27
**Text:** Follow Parliament in real time. Track your MP's votes, read today's Hansard debates, and stay informed on every bill — straight from official sources.
