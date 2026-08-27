# Hiring Intel

Thin host app + WidgetKit extension (iOS 17+ and macOS 14+). Openings come from `~/HiringIntel/feed.json` (owned by Builder, gitignored). The host copies that file into App Group `group.com.azealcompany.hiringintel` and reloads widget timelines.

## Builder refresh

Overwrite this file in place (do not rename):

    /Users/phlegonjoseph/HiringIntel/feed.json

Then open Hiring Intel (it copies on appear / becoming active) or wait for the next widget timeline reload (every 30 minutes). Empty `openings: []` is valid — widgets show "No openings yet".

SAMPLE openings exist only in Xcode widget previews, not in feed.json.

## Add the widget (iOS)

Long-press the Home Screen → Edit / + → Add Widget → Hiring Intel.

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
