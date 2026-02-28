# Getting Started

## Prerequisites

- Zig `0.15.1`
- Xcode `26+` (`xcodebuild`, `xcrun`)
- Java `21`
- Gradle `9.3.1`
- XcodeGen
- Android SDK tools (`adb`, emulator)

See: [Development Requirements](development-requirements.md)

## Build Ziggy

```sh
zig build
```

## Create A New App

```sh
./zig-out/bin/ziggy create MyApp /path/to/MyApp --sdk-root /Users/arata/Developer/zig/ziggy
```

## Run

```sh
./zig-out/bin/ziggy run /path/to/MyApp
```

The unified `run` command performs:

1. API codegen preflight from `ziggy.api.json`
2. Device discovery (iOS + Android)
3. Platform handoff to build/install/launch

## Build Documentation

```sh
python3 scripts/docs_build.py
```

Output is written to `docs/site/`.
