# Development Requirements

## Core Toolchains

Wizig framework development requires:

- Zig `0.15.1`
- Xcode `26+` and Apple CLT (`xcodebuild`, `xcrun`)
- XcodeGen
- Java `21`
- Gradle `9.3.1`
- Android SDK tools (`adb`, emulator, platform SDKs)
- Python `3.10+` for docs tooling

## Homebrew Baseline

```sh
brew install gradle openjdk@21 xcodegen python
brew install --cask android-platform-tools android-commandlinetools
```

## Android Notes

- App scaffolds pin Gradle wrapper `9.3.1`.
- Kotlin/Compose versions are managed by generated version catalog.
- Generated host bindings are sourced from `.wizig/generated/kotlin`.

## iOS Notes

- iOS scaffolds are generated through XcodeGen from `ios/project.yml`.
- Minimum deployment target is currently `17.0`.
- Generated host bindings are sourced from `.wizig/generated/swift`.

## Docs Tooling

Install Python markdown renderer:

```sh
python3 -m pip install --upgrade markdown
```

Then build docs:

```sh
zig build docs
```
