# EPAC-1940 review evidence

Captured on May 18, 2026 from local simulator builds for PR #494.

## iPhone evidence

Device: iPhone 17 Pro Max simulator, iOS 26.4.1.

- `before-iphone-parliament-toolbar.png`: baseline `origin/main` build with the pre-change crowded Parliament toolbar and legend-only Today affordance.
- `after-iphone-parliament-toolbar.png`: PR build with the grouped Parliament links menu and prominent in-view Today button.
- `after-iphone-parliament-after-retap.png`: PR build after the Parliament screen remained on May 2026; this matches the fixed post-retap state because the calendar scroll view no longer opts into UIKit scroll-to-top.
- `before-iphone-members-toolbar.png`: baseline `origin/main` build with the old Members toolbar controls.
- `after-iphone-members-toolbar.png`: PR build with the consolidated Members filters menu.

The tab-retap scroll behavior is also covered by `CalendarScrollsToTopDisablerTests`, which verifies the HorizonCalendar scroll view is the only scroll view opted out of `scrollsToTop`.

## iPad note

I attempted iPad verification on:

- `EPAC-1940 iPad 26.0` (`ED697A38-9F0B-445F-A561-97223F9DEAEF`)
- fresh `EPAC-1940 fresh iPad` (`0A486EA1-320F-4C83-98CC-998C8BC808E7`)
- fresh `EPAC-1940 fresh iPad 26.0` (`CF8374B4-3668-45D1-9ACF-498D76DA32E6`)

The PR app installed on iPad simulators, but `xcrun simctl launch ... net.dinglebox.cabinetdoor` repeatedly hung and never foregrounded the app for a valid in-app screenshot. The failed launch attempts are documented in the PR test plan; no iPad app screenshot is included because the only captured iPad frame was SpringBoard, not the app.
