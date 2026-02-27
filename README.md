# Ziggy

Ziggy is a mobile-first framework architecture with Zig core logic and native host UIs.

## Developer Requirements

- Zig `0.15.1`
- Xcode `26+` with command line tools (`xcodebuild`, `xcrun`)
- Java `21`
- Gradle `9.3.1`
- XcodeGen
- Android SDK tools (`adb`, emulator, platform SDKs)

Homebrew install baseline:

```sh
brew install gradle openjdk@21 xcodegen
brew install --cask android-platform-tools android-commandlinetools
```

Detailed setup notes: `docs/development-requirements.md`.

## Core Commands

```sh
zig build
zig build test
```

## Plugin Registry

```sh
zig build run -- plugin validate examples/plugin-hello/ziggy-plugin.toml
zig build run -- plugin sync examples
```

## App Scaffolding

```sh
zig build run -- create MyApp examples/app/MyApp
zig build run -- create MyApp examples/app/MyApp --platforms ios,android,macos

# Legacy per-platform mode
zig build run -- create ios MyLegacyIos examples/ios/MyLegacyIos
zig build run -- create android MyLegacyAndroid examples/android/MyLegacyAndroid
```

## Run Apps

```sh
# iOS (interactive simulator selection + lldb attach)
zig build run -- run ios examples/app/ZiggyExample/ios

# Android (interactive device selection + jdb attach or logcat fallback)
zig build run -- run android examples/app/ZiggyExample/android
```

## FFI Runtime Notes

- Build host FFI artifacts with `zig build`.
- Shared library output is installed under `zig-out/lib` (for example `zig-out/lib/libziggyffi.dylib` on macOS).
- Swift/Kotlin runtimes read `ZIGGY_FFI_LIB` to locate the library if needed.
