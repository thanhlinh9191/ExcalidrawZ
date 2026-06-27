fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Upload App Store Connect metadata only. Build upload stays manual.

### mac generate_sparkle_release_notes

```sh
[bundle exec] fastlane mac generate_sparkle_release_notes
```

Generate localized Sparkle release notes and patch local website appcast.

### mac split_screenshots

```sh
[bundle exec] fastlane mac split_screenshots
```

Split localized App Store preview strips into fastlane screenshot folders.

### mac render_preview_strips

```sh
[bundle exec] fastlane mac render_preview_strips
```

Render localized App Store preview strips from a text-free template.

### mac generate_previews

```sh
[bundle exec] fastlane mac generate_previews
```

Render localized preview strips and split them into App Store screenshots.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
