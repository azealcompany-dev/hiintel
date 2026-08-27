# Hiintel

iOS 17+ / macOS 14+ openings reader + WidgetKit. Display name is **Hiintel**.

One public repo holds the app and the live feed. The host and widget fetch:

    https://raw.githubusercontent.com/azealcompany-dev/hiintel/main/feed.json

They cache a successful fetch as `OpeningsFeed.json` in App Group `group.com.azealcompany.hiringintel`, then reload widget timelines. Bundled `feed.json` is the offline fallback. Fetch failures stay on cache/bundle. Mac disk `~/HiringIntel/feed.json` is a local-dev extra only.

The app does not scrape ATS or HTML career pages.

## Feed

`scripts/build_feed.py` pulls **SDR, BDR, and Account Executive** roles from public Greenhouse, Lever, and Ashby boards in `scripts/companies.json`. Run locally:

    python3 scripts/build_feed.py --out feed.json

A GitHub Action runs that script daily (`0 13 * * *` UTC) and commits `feed.json` here. Empty `openings: []` is valid and does not wipe a good on-device cache.

## Host

Search, family / where / when chips, newest vs by-company, Openings / Saved / Applied. Saved and applied are local to the App Group, keyed by opening id (no iCloud). Pull-to-refresh uses the same live JSON.

## Widget

Long-press the Home Screen → Edit / + → Add Widget → Hiintel.

- Small: company + role
- Medium: + location
- Large: + lookingFor + companyBrief (plain text)
- Tap opens the posting URL
- Rotates the first 24 openings (saved ids first when present)

## Bundle IDs

- Host (iOS + Mac): `com.azealcompany.hiringintel`
- Widget: `com.azealcompany.hiringintel.widget`
- Team: `B8VKLXY4L2`

## Generate & build

    xcodegen generate
    xcodebuild -project HiringIntel.xcodeproj -scheme HiringIntel \
      -destination 'id=00008140-00194D9E3C0B001C' \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=B8VKLXY4L2
