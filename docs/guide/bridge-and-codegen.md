# Bridge & Codegen

Wizig generates typed host-callable APIs from Zig source code, creating a bridge between native hosts and the Zig runtime.

## Discovery Sources

Wizig discovers API surfaces from `pub fn` declarations across `lib/**/*.zig`.

Optional contract files provide explicit overrides and event declarations:

1. `wizig.api.zig` — Zig-native contract (preferred)
2. `wizig.api.json` — JSON contract (legacy, still supported)

### Resolution Order

When `wizig codegen` or `wizig run` needs a contract:

| Priority | Source |
|----------|--------|
| 1 | Explicit `--api <path>` flag |
| 2 | `<project>/wizig.api.zig` |
| 3 | `<project>/wizig.api.json` |
| 4 | Discovery-only mode from `lib/**/*.zig` |

## Optional Zig Contract

A minimal Zig contract defines namespace, methods, and events:

```zig
pub const namespace = "dev.wizig.app";

pub const methods = .{
    .{ .name = "echo", .input = .string, .output = .string },
    .{ .name = "increment", .input = .int, .output = .int },
};

pub const events = .{
    .{ .name = "log", .payload = .string },
};
```

### Supported Scalar Types

| Tag | Description |
|-----|-------------|
| `.string` | UTF-8 string |
| `.int` | Integer |
| `.bool` | Boolean |
| `.void` | No value |

## Generated Targets

Running `wizig codegen <project_root>` produces:

### Bridge Bindings

| File | Language |
|------|----------|
| `.wizig/generated/zig/WizigGeneratedApi.zig` | Zig FFI root |
| `.wizig/generated/swift/WizigGeneratedApi.swift` | Swift client |
| `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt` | Kotlin client |

### iOS C Interop

| File | Purpose |
|------|---------|
| `.wizig/generated/ios/wizig.h` | Core C header |
| `.wizig/generated/ios/WizigGeneratedApi.h` | Generated API C header |
| `.wizig/generated/ios/WizigFFI.h` | FFI C header |
| `.wizig/generated/ios/module.modulemap` | Clang module map for Swift import |

### SDK Mirrors

| File | Purpose |
|------|---------|
| `.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift` | iOS SDK copy |
| `.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt` | Android SDK copy |

## Generated Output Contents

Each generated file contains:

- **Method clients** matching contract signatures
- **Event sink protocol/interface declarations**
- **Event emit helpers** bound to sink surfaces

## Host Integration

### iOS

- App imports `Wizig` from `.wizig/sdk/ios`
- `WizigGeneratedApi` is part of the `Wizig` module
- `wizig run` regenerates code first, then builds

### Android

- App module includes both `.wizig/sdk/android/src/main/kotlin` and `.wizig/generated/kotlin`
- App code imports `dev.wizig.WizigGeneratedApi`
- `wizig run` regenerates code first, then builds

## Operational Rules

- **Treat generated files as build artifacts** — do not hand-edit.
- **Regenerate after contract changes** — run `wizig codegen` whenever `lib/**/*.zig` or contract files change.
- **Keep contract identifiers stable** — renaming methods requires host-side refactors.
- **Use watch mode** for iterative development: `wizig codegen --watch`.

## Error Handling

Common codegen errors and their causes:

| Error | Cause |
|-------|-------|
| Unsupported contract extension | Contract file is not `.zig` or `.json` |
| Invalid contract field/type token | Unknown type in explicit contract |
| Missing/mismatched FFI symbols | Generated API doesn't match compiled FFI; re-run codegen |

The codegen command prints explicit path and parser failure details to aid debugging.
