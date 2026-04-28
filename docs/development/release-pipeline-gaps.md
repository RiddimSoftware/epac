# Release Pipeline Gaps — v1.9 Lessons

This file captures everything that **wasn't** automated in the v1.9 App Store
release and had to be done by hand. Each gap is a candidate for a backlog
ticket. The order roughly matches the order they hit during the v1.9 release.

---

## Gap 1 — App Store version is not auto-created in App Store Connect

**Symptom.** The `Create Release` workflow uploaded build 1.9.0 to TestFlight,
but no editable App Store version existed yet on App Store Connect. Fastlane
picked up an existing prepared version `1.9` (manually created by a human in the
ASC web UI) — but it was missing localizations, which kicked off Gap 2.

**What had to be done by hand.** A human had to click "+" in the ASC web UI to
create version `1.9` ahead of time. If they hadn't, fastlane would have
auto-created `1.9.0` as a fresh version with zero localizations and the same
Gap 2 failure.

**Fix idea.** A pre-flight step in the release pipeline that checks whether an
editable version exists and, if not, creates one **and** copies all
localizations from the previous shipped version. The ASC API supports both:
`POST /v1/appStoreVersions` and `POST /v1/appStoreVersionLocalizations` per
locale, copying field values from the previously-live version's localizations.

---

## Gap 2 — Locale folder name didn't match app's primary locale

**Symptom.** Repo had `ios/fastlane/metadata/en-US/`. App's primary locale on
the App Store is `en-CA`. Fastlane saw en-US in the repo, didn't see it on the
editable version, and called `create_app_store_version_localization(locale:
en-US)`. Apple's create-localization endpoint runs a **global app-name
uniqueness check** at create time, found "epac" registered to a different app
in en-US, and rejected with the misleading error `Cannot add localization due
to app name`.

**What had to be done by hand.** Renamed `en-US` → `en-CA` across `metadata/`,
`screenshots/`, `app-previews/`, plus six code references. Apple **never
runs the global name check on UPDATE** of an existing localization, only on
CREATE — and the app already had en-CA registered with name "epac" since 2024.

**Fix idea.** A repo precommit / CI lint that diffs the locale folder names
against the app's actual primary locale via the ASC API
(`apps/{id}.attributes.primaryLocale`) and fails fast if they disagree. Catches
this before a deploy attempt.

---

## Gap 3 — Localization file (fr-CA) created without the app actually
   supporting that locale

**Symptom.** Repo had `ios/fastlane/metadata/fr-CA/` from an earlier Quebec
push. The app has fr-CA registered at the App Info level (name="epac") but no
fr-CA localization on the editable version. Fastlane tried to create fr-CA on
the version → same global-name-conflict failure as Gap 2.

**What had to be done by hand.** Removed the `fr-CA` folder. (After Gap 2
was found, this was probably actually a duplicate of the same problem — fr-CA
on the version had to be created too, and the create-localization endpoint
checks the **localized** name "epac" globally.)

**Fix idea.** Same as Gap 2 — verify each locale folder against the app's
actual list of supported locales before deploy.

---

## Gap 4 — App Preview videos rejected without a silent audio track

**Symptom.** The recording script (`scripts/marketing/record-app-preview.sh`)
produced an MP4 with `-an` (no audio). Fastlane uploaded it; Apple's media
pipeline rejected with "Your app preview contains unsupported or corrupted
audio." Apple's spec says audio is "optional but recommended" — in practice,
the media transcoder requires *some* audio track even if silent.

**What was fixed.** Added a post-processing step in `record-app-preview.sh`
that muxes a silent AAC stereo track at 44.1 kHz onto the final MP4 before it
hits the fastlane folder.

**Remaining gap.** No automated test that the produced video passes Apple's
media checks before upload. Today, the only signal is "fastlane + Apple
processing succeed" which takes 12+ minutes.

---

## Gap 5 — App Preview upload takes ~12 minutes

**Symptom.** The upload itself is seconds; Apple's transcoding step takes
10–15 minutes to return processed-and-validated. Fastlane's default behavior
is `wait_for_processing: true`, so the workflow blocks the entire time. On
GitHub Actions this is wall-clock cost; locally it's just frustrating.

**Fix idea.** Pass `wait_for_processing: false` to the preview upload action
when running in time-sensitive contexts. Trade-off: you don't get a
confirmation that Apple's side is healthy until you see it in ASC. Combined
with an out-of-band poll (a simple `gh` workflow that checks the preview's
asset state every ~2 min) this would be a clean compromise.

---

## Gap 6 — Failed preview uploads stay attached to the version

**Symptom.** The first (audio-less) upload created an `AppPreview` record on
the version's preview set with `assetDeliveryState=FAILED`. Re-uploading
created a second `AppPreview` with `state=COMPLETE`. Both stayed attached.
Apple submission flow is fine with extra FAILED records, but they're junk in
ASC and would surface in any future audit.

**What had to be done by hand.** Direct `DELETE /v1/appPreviews/{id}` for the
FAILED record.

**Fix idea.** A cleanup pass before submission that deletes any preview /
screenshot in `FAILED`, `UPLOAD_INITIAL`, or `UPLOAD_COMPLETE_FAILED` state.
Could live as a fastlane plugin or a small Python script in `scripts/release/`.

---

## Gap 7 — Build is not auto-attached to the version

**Symptom.** TestFlight had build 33 (version 1.9). ASC's editable v1.9 had no
build relationship. Without an attached build, you can't submit for review.

**What had to be done by hand.** `PATCH
/v1/appStoreVersions/{id}/relationships/build` with the build id.

**Fix idea.** The release pipeline should auto-attach the latest VALID
TestFlight build for the version string after upload completes. Trivial API
call: find the build, patch the relationship.

---

## Gap 8 — Submission API requires three sequential calls

**Symptom.** Modern App Store submission isn't `POST /submit` — it's:
1. `POST /reviewSubmissions` (create container)
2. `POST /reviewSubmissionItems` (add the version)
3. `PATCH /reviewSubmissions/{id}` with `submitted: true` (commit)

Fastlane handles this internally, but if you hit any precheck error (which we
were hitting), you get a confusing trace and the sequence stalls partway.

**What had to be done by hand.** Wrote a Python script (`/tmp/asc_submit.py`)
that walks the three calls directly and skips fastlane's precheck.

**Fix idea.** Bundle the three calls into a `scripts/release/submit_for_review.py`
that takes `(app_id, version_id)` and is callable from CI or locally. Bypasses
fastlane's precheck (which is independently flaky) for cases where we've
already validated.

---

## Gap 9 — Version-string padding (1.9 vs 1.9.0)

**Symptom.** `scripts/release/compute_next_version.py` always pads to a 3-part
semver (`1.9.0`). App Store Connect stores 2-part where applicable (`1.9`).
TestFlight followed ASC's normalization. The downstream
`release-app-store.yml` workflow searches TestFlight by exact version string
`1.9.0` (from the `v1.9.0` git tag) — would have failed even if everything
else worked.

**What had to be done by hand.** Manually attaching the build to v1.9 via API
sidestepped this — but next release will hit it again.

**Fix idea.** Either drop trailing `.0` in `compute_next_version.py`, or have
the build search treat `1.9` and `1.9.0` as equivalent. Worth picking one
canonical form and propagating: tags, ASC, TestFlight, our scripts.

---

## Gap 10 — Screenshot dimensions don't match the size slot they get
    uploaded to

**Symptom.** Repo screenshots are 1206×2622 (iPhone 6.1" Display). Fastlane
uploaded them; ASC placed them in the `APP_IPHONE_61` set. The
`APP_IPHONE_67` set still has v1.8's old screenshots (`Calendar.png`,
`Debate.png`, etc.) which are different content with different framing.

**What had to be done by hand.** Nothing for v1.9 (the old 6.7" screenshots
are an acceptable fallback), but the listing now shows two different
screenshot styles depending on which device the user is browsing from.

**Fix idea.** The screenshot generation step
(`scripts/marketing/render_app_store_screenshots.sh`) should produce all three
required iPhone sizes (6.1", 6.5", 6.7" / 6.9") from the same source, named so
fastlane drops them in the right device set. Apple actually lets you reuse a
6.5" set for 6.7" if you don't have explicit 6.7" assets.

---

## Gap 11 — `deliver-metadata.yml` workflow had never actually worked

**Symptom.** Every push that touched fastlane metadata fired the workflow
which then tried to add the en-US localization and failed in 30 seconds. We
shipped the workflow as part of EPAC-535 but never verified it on a real
release. Two failed runs were the workflow's complete history before this
release exposed the bug.

**Fix idea.** Either (a) when you ship a release-pipeline workflow, run it
end-to-end against a non-prod app on ASC before the next release, or
(b) add a `dry-run` mode for `upload_to_app_store` that exercises the full
code path against ASC sandbox. Option (a) is the cheaper start.

The workflow is currently **disabled** (`gh workflow disable`) since the user
has moved away from a daily release model. Re-enable when the underlying gaps
above are addressed and the release cadence justifies it.

---

## Gap 12 — GitHub Actions cost on the macOS runner

**Symptom.** `Create Release` runs on `macos-15`, which is the most expensive
GH-hosted runner. Several failed attempts during v1.9 burned through the
budget faster than expected.

**Fix idea.** The build step legitimately needs macOS (xcodebuild + signing).
Everything else — version computation, release-notes generation, ASC API
calls, deliver — can run on Linux. Splitting the workflow so the macOS job
does only `archive + sign + pilot upload` and a separate Linux job handles
the rest (already partially the case for `release-app-store.yml`) keeps the
expensive minutes minimal. v1.10 onward.

---

## What the v1.9 release actually looked like end-to-end

For the next release, this is the path that worked from the developer's
machine, not via CI:

1. `gh workflow run build-deploy.yml` (or the user's preferred trigger) →
   archives, signs, uploads to TestFlight. **macOS runner.**
2. In ASC web UI, create the new version (or auto-create via ASC API if
   Gap 1 is fixed).
3. Locally, `bundle exec fastlane run upload_to_app_store
   api_key_path:/tmp/asc_key.json ... skip_screenshots:false skip_metadata:false
   submit_for_review:false`. Pulls metadata, screenshots, and the App Preview
   from the repo into the version. ~13 minutes wall-clock (12 of which are
   Apple processing the preview video).
4. ASC API: attach the latest TestFlight build to the version
   (`PATCH /v1/appStoreVersions/{id}/relationships/build`).
5. ASC API: clean up any FAILED preview / screenshot records.
6. ASC API: create reviewSubmission, add version as item, patch submitted=true.

Steps 4–6 currently live in ad-hoc Python scripts in `/tmp/`. Codifying them
into `scripts/release/` is the highest-leverage automation work for the next
sprint.
