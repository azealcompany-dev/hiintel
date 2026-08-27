# HiIntel

iOS 17+ / macOS 14+ openings reader + WidgetKit. Display name is **HiIntel**.

One public repo holds the app and the live feed. The host and widget fetch:

    https://raw.githubusercontent.com/azealcompany-dev/hiintel/main/feed.json

They cache a successful fetch as `OpeningsFeed.json` in App Group `group.com.azealcompany.hiringintel`, then reload widget timelines. Bundled `feed.json` is the offline fallback. Fetch failures stay on cache/bundle. Mac disk `~/HiringIntel/feed.json` is a local-dev extra only.

The app does not scrape ATS or HTML career pages.

## Feed

`scripts/build_feed.py` pulls **SDR, BDR, and Account Executive** roles from public Greenhouse, Lever, and Ashby boards in `scripts/companies.json`. Run locally:

    python3 scripts/build_feed.py --out feed.json

A GitHub Action runs that script three times a day (`0 12,16,21 * * *` UTC) and commits `feed.json` here. Empty `openings: []` is valid and does not wipe a good on-device cache.

## Host

Search, family / where / when chips, newest vs by-company, Openings / Saved / Applied. Saved and applied are local to the App Group, keyed by opening id (no iCloud). Pull-to-refresh uses the same live JSON.

## Widget

Long-press the Home Screen → Edit / + → Add Widget → HiIntel.

- Small: company + role
- Medium: + location
- Large: + lookingFor + companyBrief (plain text)
- Tap opens the posting URL
- Rotates the first 24 openings (saved ids first when present)

## Bundle IDs

- Host (iOS + Mac): `com.azealcompany.hiringintel`
- Widget: `com.azealcompany.hiringintel.widget`
- Team: `B8VKLXY4L2`

## TestFlight

People test on their own iPhones with TestFlight — not a USB cable.

1. In Xcode: **Product → Archive** (Any iOS Device), then **Distribute App → App Store Connect → Upload**.
2. [App Store Connect](https://appstoreconnect.apple.com) → HiIntel → TestFlight.
3. **Internal testers** (people on the Azeal team): add them to a group. They install TestFlight from the App Store and get HiIntel immediately.
4. **External testers** (anyone): create a group, submit the build for Beta App Review, then share the public TestFlight link.

Privacy policy URL for external testing: this README. The app only fetches the public `feed.json`; saved/applied stay on-device in the App Group.

## Generate & build

    xcodegen generate
    xcodebuild -project HiringIntel.xcodeproj -scheme HiringIntel \
      -destination 'id=00008140-00194D9E3C0B001C' \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=B8VKLXY4L2

## Archive (TestFlight)

    xcodegen generate
    xcodebuild -project HiringIntel.xcodeproj -scheme HiringIntel \
      -destination 'generic/platform=iOS' -configuration Release \
      -archivePath build/HiIntel.xcarchive \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=B8VKLXY4L2 \
      archive
    xcodebuild -exportArchive -archivePath build/HiIntel.xcarchive \
      -exportOptionsPlist ExportOptions.plist \
      -exportPath build/export \
      -allowProvisioningUpdates

