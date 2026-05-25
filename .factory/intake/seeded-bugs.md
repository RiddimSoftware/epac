# Seeded bug candidates for SF intake

Use this file when an attendee says they don't know what to file.
Each entry includes:
- one-line summary
- exact reproduction steps
- demo visibility reason
- suggested classification
- suggested estimate (`1` or `2`)

## 1) Settings privacy actions are dead-ends
- **Summary:** `Settings → Data & Privacy` shows enabled buttons for "Export data" and "Delete account", but both are disabled placeholders with no action.
- **Repro steps:**
  1. Open **Settings**.
  2. Scroll to **Data & Privacy**.
  3. Tap **Export my data** and then **Delete account**.
  4. Observe no confirmation, no alert, and no visible result.
- **Why this is a good demo candidate:** It is immediately visible, easy to reproduce in 30 seconds, and produces a clear "nothing happens" result.
- **Suggested classification + estimate:** `simple`, `1`

## 2) Members nav title is not localized
- **Summary:** The Members tab title stays hardcoded as **Members** in all app locales.
- **Repro steps:**
  1. Set app language to French.
  2. Open the **Members** tab.
  3. Observe the navigation title still reads “Members”.
- **Why this is a good demo candidate:** It is a single-screen verification with a clearly visible text mismatch.
- **Suggested classification + estimate:** `simple`, `1`

## 3) Members filter strings are not localized
- **Summary:** Filter labels and controls in Members still use English copy (for example, **Filters**, **All Parties**, **All Provinces**, **Clear filters**).
- **Repro steps:**
  1. Set app language to French.
  2. Open the **Members** tab.
  3. Open the filters menu in the top-right.
  4. Confirm the menu header, picker options, and clear action remain in English.
- **Why this is a good demo candidate:** Small surface area, quick verify with a single menu open.
- **Suggested classification + estimate:** `simple`, `1`

## 4) Offline banner copy is hardcoded English
- **Summary:** The offline warning text is hardcoded and not localized.
- **Repro steps:**
  1. Disconnect network (Airplane mode).
  2. Open any authenticated screen.
  3. Confirm the bottom banner reads **You're offline. Showing cached content.** instead of a localized string.
- **Why this is a good demo candidate:** It is stable and obvious, with a visible single-line result.
- **Suggested classification + estimate:** `simple`, `1`

## 5) Expenditures search bar placeholder stays in English
- **Summary:** The placeholder in Expenditures search is hardcoded English, even when the app locale is French.
- **Repro steps:**
  1. Set app language to French.
  2. Open **Expenditures**.
  3. Confirm the search placeholder reads **Search for a member**.
- **Why this is a good demo candidate:** Highly visible on screen entry and easy to verify in one pass.
- **Suggested classification + estimate:** `simple`, `2`

## 6) Federal Finances still shows English navigation/labels
- **Summary:** The Federal Finances screen uses hardcoded English labels such as **Federal Finances**, **Fetching Finance Canada data...**, and related status/error copy.
- **Repro steps:**
  1. Set app language to French.
  2. Open **Expenditures** and tap the finance icon in the top toolbar.
  3. Open **Federal Finances** and confirm the screen title and status strings are still English.
- **Why this is a good demo candidate:** Repro is short and clearly visible even before any interactions.
- **Suggested classification + estimate:** `simple`, `2`

## 7) Transport safety topic copy is hardcoded English
- **Summary:** The Transport Safety topic has hardcoded English section headers and labels (for example, **Transport Safety**, **National Snapshot**, **Road Safety by Province**).
- **Repro steps:**
  1. Set app language to French.
  2. Open **Parliament** tab → **Topics** → **Transportation Safety**.
  3. Confirm those section headers and labels are still English.
- **Why this is a good demo candidate:** Clean one-screen verification with a clear before/after screenshot opportunity.
- **Suggested classification + estimate:** `simple`, `1`
