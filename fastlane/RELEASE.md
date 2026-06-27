# App Store Metadata

This folder manages App Store Connect metadata through fastlane. It does not affect Xcode builds unless a fastlane lane is run manually.

Current workflow:

1. Archive and upload the App Store build from Xcode Organizer.
2. Update `fastlane/metadata/*/release_notes.txt` for the release.
3. Upload metadata:

```sh
fastlane mac upload_metadata
```

To target a specific App Store Connect version:

```sh
fastlane mac upload_metadata version:2.2.1
```

When `version:` is omitted, the lane reads the current Xcode marketing version from `ExcalidrawZ.xcodeproj`. It prints the target version and locales, then asks for confirmation before uploading.

Authentication uses an App Store Connect API key with App Manager access.

Create a local ignored file at `fastlane/.env.local`:

```env
APP_STORE_CONNECT_API_KEY_ID=...
APP_STORE_CONNECT_API_ISSUER_ID=...
APP_STORE_CONNECT_API_KEY_PATH=./fastlane/AuthKey_XXXXXXXXXX.p8
```

Keep the downloaded `.p8` file under `fastlane/` or another local path. The `.env.local` file and API key files are ignored by git.

Managed metadata files per locale:

- `name.txt`
- `subtitle.txt`
- `keywords.txt`
- `promotional_text.txt`
- `description.txt`
- `release_notes.txt`

Current metadata locales:

- `en-US`
- `ar-SA`
- `pl`
- `de-DE`
- `ru`
- `fr-FR`
- `zh-Hant`
- `ko`
- `nl-NL`
- `zh-Hans`
- `pt-BR`
- `ja`
- `th`
- `tr`
- `es-ES`
- `it`
- `vi`

The current lane skips binary and screenshot upload. Build/archive automation can be added later after the manual release flow is stable.

## Sparkle Release Notes

Sparkle release notes reuse the same `fastlane/metadata/*/release_notes.txt` source as App Store Connect.

Generate localized Sparkle HTML files and patch the local website appcast:

```sh
fastlane mac generate_sparkle_release_notes version:2.2.1
```

This writes files like:

```text
WebPage/public/downloads/ExcalidrawZ.2.2.1.en-US.html
WebPage/public/downloads/ExcalidrawZ.2.2.1.zh-Hans.html
```

If `WebPage/public/downloads/appcast.xml` already contains an item for that version, the lane replaces its release notes link with localized Sparkle links:

```xml
<sparkle:releaseNotesLink xml:lang="en-US">...</sparkle:releaseNotesLink>
<sparkle:releaseNotesLink xml:lang="zh-Hans">...</sparkle:releaseNotesLink>
<sparkle:releaseNotesLink xml:lang="zh-Hant">...</sparkle:releaseNotesLink>
```

The existing appcast generation script should run before this lane when publishing a new non-App Store build.

## Screenshots

Preview strips are rendered from a text-free template plus localized text configuration, then split into fastlane screenshot folders.

Text-free template:

```text
fastlane/previews/assets/iphone/AppStore_iPhone_Previews.png
fastlane/previews/assets/iphone/AppStore_iPhone_Previews-zh-Hans.png
```

The renderer first looks for a localized template named `AppStore_iPhone_Previews-{locale}.png`. If none exists, it falls back to `AppStore_iPhone_Previews.png`.

Localized text and font candidates:

```text
fastlane/previews/iphone.json
```

Text boxes can use `horizontalPlacement: "center"` to stay centered within each screenshot slice. In that mode, `x` is optional and acts as a center offset.

Generate localized App Store preview screenshots:

```sh
fastlane mac generate_previews
```

Render one locale:

```sh
fastlane mac generate_previews locales:zh-Hans
```

Preview without writing files:

```sh
fastlane mac generate_previews dry_run:true
```

Output:

```text
fastlane/previews/output/iphone/AppStore_iPhone_Previews.en-US.png
fastlane/previews/output/iphone/AppStore_iPhone_Previews.zh-Hans.png
fastlane/previews/output/iphone/AppStore_iPhone_Previews.zh-Hant.png
```

The lane renders localized preview strips as an intermediate output, then splits them into fastlane screenshot folders.

Source naming:

```text
fastlane/previews/output/iphone/AppStore_iPhone_Previews.en-US.png
fastlane/previews/output/iphone/AppStore_iPhone_Previews.zh-Hans.png
fastlane/previews/output/iphone/AppStore_iPhone_Previews.zh-Hant.png
```

If you need to split an older Resource strip, pass `source_dir:Resources`. The legacy source `AppStore_iPhone_Previews.png` is treated as `zh-Hans` unless a localized `AppStore_iPhone_Previews.zh-Hans.png` exists in the selected source directory.

Split existing strips again without rendering:

```sh
fastlane mac split_screenshots
```

Preview without writing files:

```sh
fastlane mac split_screenshots dry_run:true
```

Output:

```text
fastlane/screenshots/en-US/iphone_6_7_01.png
fastlane/screenshots/zh-Hans/iphone_6_7_01.png
```

The generated PNG files under `fastlane/screenshots/` are ignored by git.

Platform defaults are prepared for `iphone`, `ipad`, and `mac`:

```sh
fastlane mac generate_previews platform:iphone
```

Add `fastlane/previews/ipad.json` or `fastlane/previews/mac.json` later when those layouts are ready.

Apple controls the spacing between screenshots in App Store surfaces, and the web and app presentations should not be treated as pixel-identical. If a design source strip includes visual spacing between screenshots, set `gapWidth` in its preview config or pass `gap_width:` to `split_screenshots`. The splitter skips the gap, so final App Store screenshots do not contain baked-in spacing.

If the source strip is wider than the number of screenshots you want to upload, set `sliceCount` in its preview config. The iPhone config currently exports the first 5 screenshots.
