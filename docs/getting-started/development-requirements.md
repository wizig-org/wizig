# Development Requirements

## Core Toolchains

Wizig framework development requires:

- Zig `0.15.1`
- Xcode `26+` and Apple CLT (`xcodebuild`, `xcrun`)
- XcodeGen (optional for legacy regeneration flows)
- Java `21`
- Gradle `9.2.1`
- Android SDK tools (`adb`, emulator, platform SDKs)
- Python `3.10+` for docs tooling

## Homebrew Baseline

```sh
brew install gradle openjdk@21 xcodegen python
brew install --cask android-platform-tools android-commandlinetools
```

## Android Notes

- App scaffolds pin Gradle wrapper `9.2.1`.
- Android host defaults: `compileSdk 36`, `minSdk 26`, `targetSdk 36`.
- Kotlin/Compose versions are managed by generated version catalog.
- Generated host bindings are sourced from `.wizig/generated/kotlin`.

## iOS Notes

- iOS scaffolds are generated from bundled Xcode project templates (no runtime IDE tooling dependency).
- Minimum deployment target is currently `18.0`.
- Generated host bindings are sourced from `.wizig/generated/swift`.

## Docs Tooling

Install documentation dependencies:

```sh
pip install -r docs/requirements.txt
```

Build docs:

```sh
zig build docs
```

Serve docs locally for preview:

```sh
mkdocs serve
```
