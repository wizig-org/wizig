# Wizig

Wizig is a mobile-first framework for building iOS and Android apps with:

- Native host UIs (`SwiftUI`, `Jetpack Compose`)
- Shared Zig runtime and domain logic
- Typed host-to-Zig bridge generation
- Static plugin registration

## Design Summary

Wizig uses a hybrid architecture:

- Keep UI and platform APIs native.
- Keep shared business/runtime logic in Zig.
- Generate typed bridge clients from discovered `lib/**/*.zig` APIs (optional contract overrides).

## Developer Requirements

- Zig `0.15.1`
- Xcode `26+` with command line tools (`xcodebuild`, `xcrun`)
- XcodeGen (optional, only for legacy `--regenerate-host` flows)
- Java `21`
- Gradle `9.3.1`
- Android SDK tools (`adb`, emulator, platform SDKs)
- Python `3.10+` + `markdown` package for docs build

Homebrew baseline:

```sh
brew install gradle openjdk@21 xcodegen python
brew install --cask android-platform-tools android-commandlinetools
python3 -m pip install --upgrade markdown
```

Detailed setup: `docs/content/development-requirements.md`.

## Build

```sh
zig build
zig build test
zig build e2e
```

## Scaffold App

```sh
zig build run -- create MyApp /tmp/MyApp --sdk-root /Users/arata/Developer/zig/wizig
```

This creates a portable project with app-local `.wizig/sdk`, `.wizig/runtime`, and `.wizig/generated` directories.

## Run App

```sh
zig build run -- run /tmp/MyApp --once
```

## Codegen

```sh
zig build run -- codegen /tmp/MyApp
```

Codegen discovery precedence:

1. `--api <path>`
2. `wizig.api.zig`
3. `wizig.api.json`
4. fallback: auto-discover `pub fn` API surface from `lib/**/*.zig`

Generated Swift/Kotlin APIs are mirrored into app-local SDK imports:

- `.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift`
- `.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt`

## Plugins

```sh
zig build run -- plugin validate examples/plugin-hello/wizig-plugin.json
zig build run -- plugin sync .
```

## Diagnostics

```sh
zig build run -- doctor
```

## Documentation

```sh
zig build docs
python3 scripts/docs_build.py --check
```

- Manual docs source: `docs/content/`
- Auto-generated API reference (Zig + Swift + Kotlin): `docs/content/reference/`
- Built site output: `docs/site/`

## FFI Runtime Notes

- FFI artifacts are produced by `zig build`.
- Shared library installs to `zig-out/lib` (for example `libwizigffi.dylib` on macOS).
- Host runtimes can use `WIZIG_FFI_LIB` to override runtime library path.
