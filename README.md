# HiIntel

Thin host app + WidgetKit extension (iOS 17+ and macOS 14+). Display name is HiIntel.

Live openings are fetched from GitHub raw (this repo must stay **public**):

    https://raw.githubusercontent.com/azealcompany-dev/hiintel-feed/main/feed.json

Widget and host cache a successful fetch as `OpeningsFeed.json` in App Group `group.com.azealcompany.hiringintel`, then reload widget timelines. Bundled `feed.json` is the offline fallback. Fetch failures fall back silently (App Group cache, then bundle). Mac disk `~/HiringIntel/feed.json` is a local-dev extra only.

A private feed repo makes GitHub raw return 404 and the app stays on cache/bundle.

The host list fetches whenever you open the app, on pull-to-refresh, and about once a day via Background App Refresh. Widget timelines still rotate openings and refetch on each timeline.

## Builder refresh

The live source of truth is `main/feed.json` in **`azealcompany-dev/hiintel-feed`**. Empty `openings: []` is valid — the list and widgets show "No openings yet".

Local overwrite for Mac-only debugging (do not rename):

    /Users/phlegonjoseph/HiringIntel/feed.json

Host fetches on launch / appear. Widget `getTimeline` waits briefly for fetch-or-timeout, then rotates openings and asks WidgetKit to refresh in 15–30 minutes.

SAMPLE openings exist only in Xcode widget previews, not in feed.json.

## Add the widget (iOS)

Long-press the Home Screen → Edit / + → Add Widget → HiIntel.

- Small: company + roleFamily / role
- Medium: + location + role
- Large: + lookingFor + companyBrief (truncated)
- Tap opens the posting URL

## Bundle IDs

- Host (iOS + Mac): com.azealcompany.hiringintel
- Widget: com.azealcompany.hiringintel.widget
- Team: B8VKLXY4L2

## Generate & build

    xcodegen generate
    xcodebuild -project HiringIntel.xcodeproj -scheme HiringIntel \
      -destination 'id=00008140-00194D9E3C0B001C' \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=B8VKLXY4L2
