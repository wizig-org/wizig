# Ziggy

Ziggy is a mobile-first framework for building iOS and Android apps with:

- Native host UIs (`SwiftUI`, `Jetpack Compose`)
- Shared Zig runtime and domain logic
- Typed host-to-Zig bridge generation
- Static plugin registration

## Design Summary

Ziggy uses a hybrid architecture:

- Keep UI and platform APIs native.
- Keep shared business/runtime logic in Zig.
- Generate typed bridge clients from a single contract (`ziggy.api.zig`).

## Developer Requirements

- Zig `0.15.1`
- Xcode `26+` with command line tools (`xcodebuild`, `xcrun`)
- XcodeGen
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
```

## Scaffold App

```sh
zig build run -- create MyApp /tmp/MyApp --sdk-root /Users/arata/Developer/zig/ziggy
```

This creates a portable project with app-local `.ziggy/sdk`, `.ziggy/runtime`, and `.ziggy/generated` directories.

## Run App

```sh
zig build run -- run /tmp/MyApp --once
```

## Codegen

```sh
zig build run -- codegen /tmp/MyApp
```

Contract lookup precedence:

1. `--api <path>`
2. `ziggy.api.zig`
3. `ziggy.api.json`

## Plugins

```sh
zig build run -- plugin validate examples/plugin-hello/ziggy-plugin.json
zig build run -- plugin sync .
```

## Diagnostics

```sh
zig build run -- doctor
```

## Documentation

```sh
zig build docs
```

- Manual docs source: `docs/content/`
- Auto-generated API reference: `docs/content/reference/`
- Built site output: `docs/site/`

## FFI Runtime Notes

- FFI artifacts are produced by `zig build`.
- Shared library installs to `zig-out/lib` (for example `libziggyffi.dylib` on macOS).
- Host runtimes can use `ZIGGY_FFI_LIB` to override runtime library path.
