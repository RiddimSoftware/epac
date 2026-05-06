# Manual baseline checks

- Confirmed app `1224459142` is `READY_FOR_SALE` in ASC at import time (version `1.9`).
- Confirmed primary locale `en-CA` metadata files were written from live ASC payloads, not copied blindly from older repo files.
- Confirmed `manifest.json` matches imported scope: locales=`["en-CA"]` and device classes only include sets with delivered screenshot assets.
- Confirmed screenshot counts match current ASC listing for `en-CA`:
  - `APP_IPAD_PRO_3GEN_129`: 5 PNG files
  - `APP_IPHONE_67`: 6 PNG files
- Screenshot set `APP_IPAD_PRO_129` exists in ASC but contains 0 assets; omitted from baseline tree.
- Preview set `IPHONE_67` exists in ASC but contains 0 preview assets; omitted from baseline tree.

## Downloaded screenshot assets
- `APP_IPAD_PRO_3GEN_129` → `01_calendar.png` (2064×2752) from ASC source `Calendar.png`
- `APP_IPAD_PRO_3GEN_129` → `02_debate.png` (2064×2752) from ASC source `Debate.png`
- `APP_IPAD_PRO_3GEN_129` → `03_expenditures-2.png` (2064×2752) from ASC source `Expenditures-2.png`
- `APP_IPAD_PRO_3GEN_129` → `04_expenditures.png` (2064×2752) from ASC source `Expenditures.png`
- `APP_IPAD_PRO_3GEN_129` → `05_questions.png` (2064×2752) from ASC source `Questions.png`
- `APP_IPHONE_67` → `01-parliament-in-your-pocket.png` (1290×2796) from ASC source `01-parliament-in-your-pocket.png`
- `APP_IPHONE_67` → `02-see-how-your-mp-votes.png` (1290×2796) from ASC source `02-see-how-your-mp-votes.png`
- `APP_IPHONE_67` → `03-your-mp-everything-they-do.png` (1290×2796) from ASC source `03-your-mp-everything-they-do.png`
- `APP_IPHONE_67` → `04-track-a-bill-start-to-finish.png` (1290×2796) from ASC source `04-track-a-bill-start-to-finish.png`
- `APP_IPHONE_67` → `05-know-whos-influencing-your-mp.png` (1290×2796) from ASC source `05-know-whos-influencing-your-mp.png`
- `APP_IPHONE_67` → `06-contact-them-in-one-tap.png` (1290×2796) from ASC source `06-contact-them-in-one-tap.png`
