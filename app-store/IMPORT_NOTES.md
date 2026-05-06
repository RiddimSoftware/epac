# App Store baseline import notes

Fetched from App Store Connect at **2026-05-06T20:03:33Z** for app **epac** (`1224459142`), bundle `net.dinglebox.cabinetdoor`.

## Why epac was selected as the GROW-8 pilot

- Active App Store listing in ASC (`READY_FOR_SALE`) with current live version **1.9**.
- Accessible local app repo: `RiddimSoftware/epac`.
- Existing App Store asset surface already lives in-repo (`ios/fastlane/metadata`, `ios/fastlane/screenshots`, `ios/fastlane/app-previews`, and `docs/marketing/`).
- The live listing has enough surface to exercise the contract: metadata, multiple screenshot device classes, and a visible secondary locale in app info.
- The repo already contains ongoing ASO and release workflow material, making it the lowest-risk golden path for baseline import.

## Import scope

- Imported the current live **primary locale** `en-CA` into the contract `app-store/` tree.
- Downloaded current live screenshots directly from ASC asset URLs for the device classes that currently have delivered assets.
- Initialized `ids.json` but left it empty; no CPP/PPO/in-app-event IDs were created by this baseline import.

## Known gaps documented intentionally

- `fr-CA` exists as an App Info localization in ASC, but the current live version does not expose a matching App Store Version localization payload with metadata + screenshots through the fetched relationships. It is **not** represented in `manifest.json` yet.
- `APP_IPAD_PRO_129` screenshot set exists for the live version in ASC but currently contains **0** screenshots, so it was omitted from the artifact tree.
- An `IPHONE_67` preview set exists for the live version in ASC but currently contains **0** preview assets, so no `app-previews/` assets were imported.
- Repository-local legacy assets that do **not** match the current live listing exactly were intentionally not copied into this baseline.

## Source references

- App Info localizations: `/v1/apps/1224459142/appInfos?include=appInfoLocalizations`
- Live version localization: `/v1/appStoreVersionLocalizations/682dbc3a-21db-4628-85e3-5e58f86bc378`
- Screenshot sets: `/v1/appStoreVersionLocalizations/682dbc3a-21db-4628-85e3-5e58f86bc378/appScreenshotSets`
- Preview sets: `/v1/appStoreVersionLocalizations/682dbc3a-21db-4628-85e3-5e58f86bc378/appPreviewSets`
