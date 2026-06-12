# EPAC-329 SpeechView Performance Notes

Date: 2026-04-28
Device target: iOS Simulator `FCFAF817-6694-402D-B116-A86EDAF34237`
App target: `net.dinglebox.cabinetdoor`

## Profiling Result

The local simulator does not support the Instruments `Animation Hitches` template through `xctrace`; the run failed with:

```text
Hitches is not supported on this platform.
```

`Time Profiler` attach and all-process recordings started, but did not stop at the requested `--time-limit` and had to be terminated. The incomplete trace bundles were not committed.

## Hotspots Reviewed

1. `SpeechViewModel.nextMessage` resolved each revealed `SpeechMessage` by calling `MemberResolver.resolve`, which fetched every `ParliamentMember` from SwiftData each time. Resume playback of a 350-message sitting could therefore issue hundreds of full member-table fetches on the main actor.
2. `SpeakerImageView` started image work whenever a visible avatar row appeared. It went through `SpeakerImageViewModel` and decoded stored image data even when `MemberImageCache` already held a decoded `UIImage`.
3. The ExyteChat message builder still creates text, context-menu, and accessibility views for visible rows. This is accepted for now because the third-party chat view owns row virtualization, and the current row code has no per-row SwiftData query.

## Fixes

- Added `MemberResolutionCache`, loaded once per `SpeechViewModel`, so member and constituency lookup work is amortized across the full debate playback.
- Kept the existing `MemberResolver` API intact for other callers.
- Updated `SpeakerImageView` to check `MemberImageCache` before touching SwiftData image blobs or the network fallback chain.
- Stored decoded image data back into `MemberImageCache` so repeated avatar cells can reuse the decoded image directly.
- Added a focused cache test in `MemberResolverTests`.

## Remaining Verification

The MetricKit acceptance criterion requires at least two TestFlight builds after merge. That cannot be confirmed locally before this PR lands; it should be checked from production/TestFlight metrics after release.
