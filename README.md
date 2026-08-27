# Hiring Intel

Thin host app + WidgetKit extension. Openings come from `feed.json` in this folder (owned by Builder, gitignored). The app copies that file into the App Group and reloads widget timelines.

## Add the widget (iOS)

Long-press the Home Screen → tap **Edit** (or **+**) → **Add Widget** → search **Hiring Intel** → Small, Medium, or Large.

- Small: company + role
- Medium: + location
- Large: + looking for + company brief
- Tap opens the posting

## Generate

```sh
xcodegen generate
```
