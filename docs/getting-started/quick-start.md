# Quick Start

This guide walks you through creating, building, and running a Wizig app.

## Build Wizig

From the repository root:

```sh
zig build
```

This produces `./zig-out/bin/wizig` and installs runtime assets under `zig-out/`.

## Create an App

Use `--sdk-root` when scaffolding from a development checkout so the app vendors SDK/runtime/templates into `.wizig/`.

```sh
./zig-out/bin/wizig create MyApp /tmp/MyApp --sdk-root .
```

Expected output structure:

```
/tmp/MyApp/
├── lib/           # Zig app logic
├── ios/           # iOS host project
├── android/       # Android host project
├── .wizig/
│   ├── sdk/       # Vendored host SDK wrappers
│   ├── runtime/   # Vendored Zig runtime/FFI glue
│   └── generated/ # Generated bridge bindings
└── wizig.yaml     # App configuration
```

## Define Your API Surface

Declare host-callable functions as `pub fn` in `lib/**/*.zig`. Example (`lib/main.zig`):

```zig
const std = @import("std");

pub fn echo(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "echo:{s}", .{input});
}
```

Wizig discovers these functions automatically. For explicit control, add a `wizig.api.zig` or `wizig.api.json` contract override.

## Run Codegen

Regenerate bridge bindings after changing your API surface:

```sh
./zig-out/bin/wizig codegen /tmp/MyApp
```

This generates typed bindings for all target languages:

| File | Language |
|------|----------|
| `.wizig/generated/zig/WizigGeneratedApi.zig` | Zig FFI root |
| `.wizig/generated/swift/WizigGeneratedApi.swift` | Swift client |
| `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt` | Kotlin client |

SDK mirror copies are also placed under `.wizig/sdk/ios/` and `.wizig/sdk/android/`.

## Run the App

The unified runner discovers iOS/Android devices and delegates to the selected host:

```sh
./zig-out/bin/wizig run /tmp/MyApp
```

Non-interactive mode (useful for CI):

```sh
./zig-out/bin/wizig run /tmp/MyApp --non-interactive --device ios:3BE718C0-8315-4698-8C04-7F62D2EE71C7 --once
```

## Watch Mode

Keep codegen running in the background to auto-regenerate on file changes:

```sh
./zig-out/bin/wizig codegen /tmp/MyApp --watch
```

## Troubleshooting

If scaffold or build fails:

1. Run `./zig-out/bin/wizig doctor --sdk-root .` to validate your environment.
2. Confirm `.wizig/generated/swift/WizigGeneratedApi.swift` exists before iOS build.
3. Confirm `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt` exists before Android build.
4. Regenerate iOS project if needed: `cd /tmp/MyApp/ios && xcodegen generate`.

## Next Steps

- [Architecture Overview](../architecture/overview.md) — understand the runtime stack
- [Bridge & Codegen](../guide/bridge-and-codegen.md) — deep dive into the typed bridge
- [CLI Reference](../cli-reference.md) — full command documentation
