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

## Build Wizig

From repository root:

```sh
zig build
```

This produces `./zig-out/bin/wizig` and installs runtime assets under `zig-out/`.

## Create An App

Use `--sdk-root` when scaffolding from a development checkout so the app vendors SDK/runtime/templates into `.wizig/`.

```sh
./zig-out/bin/wizig create MyApp /tmp/MyApp --sdk-root /Users/arata/Developer/zig/wizig
```

Expected output structure:

- `/tmp/MyApp/lib`
- `/tmp/MyApp/ios`
- `/tmp/MyApp/android`
- `/tmp/MyApp/.wizig/sdk`
- `/tmp/MyApp/.wizig/runtime`
- `/tmp/MyApp/.wizig/generated`

## Define Zig API Surface

Declare host-callable functions as `pub fn` in `lib/**/*.zig`. Example (`lib/main.zig`):

```zig
const std = @import("std");

pub fn echo(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "echo:{s}", .{input});
}
```

Optional: add `wizig.api.zig` or `wizig.api.json` when you need explicit contract overrides/events.

## Run Codegen

Regenerate bridge bindings after contract changes:

```sh
./zig-out/bin/wizig codegen /tmp/MyApp
```

Generated files:

- `/tmp/MyApp/.wizig/generated/zig/WizigGeneratedApi.zig`
- `/tmp/MyApp/.wizig/generated/swift/WizigGeneratedApi.swift`
- `/tmp/MyApp/.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt`
- `/tmp/MyApp/.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift`
- `/tmp/MyApp/.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt`

## Run App

Unified runner discovers iOS/Android devices and delegates to the selected host.

```sh
./zig-out/bin/wizig run /tmp/MyApp
```

Non-interactive example:

```sh
./zig-out/bin/wizig run /tmp/MyApp --non-interactive --device ios:3BE718C0-8315-4698-8C04-7F62D2EE71C7 --once
```

## Troubleshooting

If scaffold/build fails:

1. Run `./zig-out/bin/wizig doctor --sdk-root /Users/arata/Developer/zig/wizig`.
2. Confirm `.wizig/generated/swift/WizigGeneratedApi.swift` exists before iOS build.
3. Confirm `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt` exists before Android build.
4. Regenerate iOS project if needed: `cd /tmp/MyApp/ios && xcodegen generate`.

## Build Documentation

```sh
zig build docs
```

Rendered site output: `docs/site/`.
