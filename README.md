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
zig build run -- plugin validate examples/plugin-hello/ziggy-plugin.json
zig build run -- plugin sync .
```

## App Scaffolding

```sh
zig build run -- create MyApp examples/app/MyApp
zig build run -- create MyApp examples/app/MyApp --platforms ios,android,macos --sdk-root .
```

## Run Apps

```sh
# Unified host/device selection from project root
zig build run -- run examples/app/ZiggyExample --once
```

## Codegen And Diagnostics

```sh
zig build run -- codegen examples/app/ZiggyExample
zig build run -- doctor
```

## Documentation

```sh
python3 scripts/docs_build.py
```

Generates API reference markdown from Zig doc comments and renders a static site to `docs/site/`.

## FFI Runtime Notes

- Build host FFI artifacts with `zig build`.
- Shared library output is installed under `zig-out/lib` (for example `zig-out/lib/libziggyffi.dylib` on macOS).
- Swift/Kotlin runtimes read `ZIGGY_FFI_LIB` to locate the library if needed.
