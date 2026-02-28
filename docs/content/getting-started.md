# Getting Started

## Prerequisites

Required host tools:

- Zig `0.15.1`
- Xcode `26+` (`xcodebuild`, `xcrun`)
- XcodeGen
- Java `21`
- Gradle `9.3.1`
- Android SDK tools (`adb`, emulator)

Detailed setup: [Development Requirements](development-requirements.md)

## Build Ziggy

From repository root:

```sh
zig build
```

This produces `./zig-out/bin/ziggy` and installs runtime assets under `zig-out/`.

## Create An App

Use `--sdk-root` when scaffolding from a development checkout so the app vendors SDK/runtime/templates into `.ziggy/`.

```sh
./zig-out/bin/ziggy create MyApp /tmp/MyApp --sdk-root /Users/arata/Developer/zig/ziggy
```

Expected output structure:

- `/tmp/MyApp/lib`
- `/tmp/MyApp/ios`
- `/tmp/MyApp/android`
- `/tmp/MyApp/.ziggy/sdk`
- `/tmp/MyApp/.ziggy/runtime`
- `/tmp/MyApp/.ziggy/generated`
- `/tmp/MyApp/ziggy.api.zig`

## Define API Contract

The bridge contract defaults to `ziggy.api.zig`:

```zig
pub const namespace = "dev.ziggy.myapp";

pub const methods = .{
    .{ .name = "echo", .input = .string, .output = .string },
};

pub const events = .{
    .{ .name = "log", .payload = .string },
};
```

Supported scalar tags:

- `.string`
- `.int`
- `.bool`
- `.void`

## Run Codegen

Regenerate bridge bindings after contract changes:

```sh
./zig-out/bin/ziggy codegen /tmp/MyApp
```

Generated files:

- `/tmp/MyApp/.ziggy/generated/zig/ZiggyGeneratedApi.zig`
- `/tmp/MyApp/.ziggy/generated/swift/ZiggyGeneratedApi.swift`
- `/tmp/MyApp/.ziggy/generated/kotlin/dev/ziggy/generated/ZiggyGeneratedApi.kt`

## Run App

Unified runner discovers iOS/Android devices and delegates to the selected host.

```sh
./zig-out/bin/ziggy run /tmp/MyApp
```

Non-interactive example:

```sh
./zig-out/bin/ziggy run /tmp/MyApp --non-interactive --device ios:3BE718C0-8315-4698-8C04-7F62D2EE71C7 --once
```

## Troubleshooting

If scaffold/build fails:

1. Run `./zig-out/bin/ziggy doctor --sdk-root /Users/arata/Developer/zig/ziggy`.
2. Confirm `.ziggy/generated/swift/ZiggyGeneratedApi.swift` exists before iOS build.
3. Confirm `.ziggy/generated/kotlin/dev/ziggy/generated/ZiggyGeneratedApi.kt` exists before Android build.
4. Regenerate iOS project if needed: `cd /tmp/MyApp/ios && xcodegen generate`.

## Build Documentation

```sh
zig build docs
```

Rendered site output: `docs/site/`.
