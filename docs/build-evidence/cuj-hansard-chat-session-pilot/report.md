# PR Change Evidence Report

## Summary
- Repository: `RiddimSoftware/epac`
- Pull request: [#542 [EPAC-1985]: reduce ContentView deep-link complexity](https://github.com/RiddimSoftware/epac/pull/542)
- PR title: [EPAC-1985]: reduce ContentView deep-link complexity
- PR URL: https://github.com/RiddimSoftware/epac/pull/542
- Before SHA: `9ba487ca2fdb2ecfa4fe722d0c353944284bc9ff`
- After SHA: `79e3b0bc2904dcc69e53975142deb4283f5f8c6d`
- Runner mode: `simctl`
- Simulator: `iPhone 17 Pro Max` (`1B4F22DF-E851-4A3B-AFFE-0EA338BD5D48`)
- Command: `evidence capture-pr --repo RiddimSoftware/epac --pr 542 --plan .evidence/cuj-hansard-chat-session.json --output /Users/sunny/code/epac/.symphony/workspaces/EPAC-2057/docs/build-evidence/cuj-hansard-chat-session-pilot --before-ref 9ba487ca2fdb2ecfa4fe722d0c353944284bc9ff --after-ref 79e3b0bc2904dcc69e53975142deb4283f5f8c6d`
- Started: `2026-05-25T17:41:26Z`
- Completed: `2026-05-25T17:44:00Z`
- Overall status: **succeeded**

## Visual Comparisons

### home baseline
![home baseline comparison](comparisons/home-baseline.png)
Artifacts: before `before/00-home-baseline.png`, after `after/00-home-baseline.png`

### sitting day overview
![sitting day overview comparison](comparisons/sitting-day-overview.png)
Artifacts: before `before/01-sitting-day-overview.png`, after `after/01-sitting-day-overview.png`

### chat thread top
![chat thread top comparison](comparisons/chat-thread-top.png)
Artifacts: before `before/02-chat-thread-top.png`, after `after/02-chat-thread-top.png`

### chat thread scrolled
![chat thread scrolled comparison](comparisons/chat-thread-scrolled.png)
Artifacts: before `before/03-chat-thread-scrolled.png`, after `after/03-chat-thread-scrolled.png`

## Planned Steps

### 1. launch app
- Kind: `launch`
- Before status: `succeeded`
- After status: `succeeded`

### 2. settle after launch
- Kind: `wait`
- Before status: `succeeded`
- After status: `succeeded`

### 3. home baseline
- Kind: `screenshot`
- Before status: `succeeded`
- After status: `succeeded`
- Before screenshot: [before/00-home-baseline.png](before/00-home-baseline.png)
- After screenshot: [after/00-home-baseline.png](after/00-home-baseline.png)

### 4. open cs-sitting
- Kind: `openURL`
- Before status: `succeeded`
- After status: `succeeded`

### 5. settle cs-sitting
- Kind: `wait`
- Before status: `succeeded`
- After status: `succeeded`

### 6. sitting day overview
- Kind: `screenshot`
- Before status: `succeeded`
- After status: `succeeded`
- Before screenshot: [before/01-sitting-day-overview.png](before/01-sitting-day-overview.png)
- After screenshot: [after/01-sitting-day-overview.png](after/01-sitting-day-overview.png)

### 7. open early speech
- Kind: `openURL`
- Before status: `succeeded`
- After status: `succeeded`

### 8. settle chat thread top
- Kind: `wait`
- Before status: `succeeded`
- After status: `succeeded`

### 9. chat thread top
- Kind: `screenshot`
- Before status: `succeeded`
- After status: `succeeded`
- Before screenshot: [before/02-chat-thread-top.png](before/02-chat-thread-top.png)
- After screenshot: [after/02-chat-thread-top.png](after/02-chat-thread-top.png)

### 10. open later speech in same thread
- Kind: `openURL`
- Before status: `succeeded`
- After status: `succeeded`

### 11. settle chat thread scrolled
- Kind: `wait`
- Before status: `succeeded`
- After status: `succeeded`

### 12. chat thread scrolled
- Kind: `screenshot`
- Before status: `succeeded`
- After status: `succeeded`
- Before screenshot: [before/03-chat-thread-scrolled.png](before/03-chat-thread-scrolled.png)
- After screenshot: [after/03-chat-thread-scrolled.png](after/03-chat-thread-scrolled.png)

## Run Metadata
- Plan: `.evidence/cuj-hansard-chat-session.json`
- Xcode destination: `platform=iOS Simulator,name=iPhone 17 Pro Max`
- Build duration: 1m 48.4s
- Logs: [logs/build-after.log](logs/build-after.log), [logs/build-before.log](logs/build-before.log)
