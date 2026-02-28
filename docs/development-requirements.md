# Development Requirements

Wizig framework/tooling development requires:

- Zig `0.15.1`
- Xcode `26+` and Apple command line tools (`xcodebuild`, `xcrun`)
- Java `21`
- Gradle `9.3.1`
- XcodeGen
- Android SDK tools (`adb`, emulator, platform SDKs)

Homebrew baseline:

```sh
brew install gradle openjdk@21 xcodegen
brew install --cask android-platform-tools android-commandlinetools
```

Notes:

- Android app scaffolds are generated with Gradle wrapper `9.3.1` and Kotlin `2.2.x`.
- iOS app scaffolds use minimum deployment target `17.0`.
