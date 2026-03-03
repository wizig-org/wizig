# Bridge And Codegen

## Discovery Sources

Wizig generates host-callable APIs from `pub fn` declarations across `lib/**/*.zig`.

Optional contract files are still supported for explicit overrides and events:

1. `wizig.api.zig`
2. `wizig.api.json`

Resolution order for `wizig codegen` and `wizig run`:

1. explicit `--api <path>`
2. `<project>/wizig.api.zig`
3. `<project>/wizig.api.json`
4. fallback to discovery-only mode

## Optional Zig Contract Shape

Minimal Zig contract:

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

Supported scalar tags today:

- `.string`
- `.int`
- `.bool`
- `.void`

## Generated Targets

Running `wizig codegen <project_root>` emits:

- Zig: `.wizig/generated/zig/WizigGeneratedApi.zig`
- Swift: `.wizig/generated/swift/WizigGeneratedApi.swift`
- Kotlin: `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt`
- iOS C interop:
  - `.wizig/generated/ios/wizig.h`
  - `.wizig/generated/ios/WizigGeneratedApi.h`
  - `.wizig/generated/ios/WizigFFI.h`
  - `.wizig/generated/ios/module.modulemap`
- SDK mirrors:
  - `.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift`
  - `.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt`

Generated outputs contain:

- Method clients matching contract signatures.
- Event sink protocol/interface declarations.
- Event emit helpers bound to those sink surfaces.

## Host Integration

### iOS

- App imports `Wizig` from `.wizig/sdk/ios`.
- `WizigGeneratedApi` is part of the `Wizig` module.
- `wizig run` regenerates code first, then builds.

### Android

- App module includes both `.wizig/sdk/android/src/main/kotlin` and `.wizig/generated/kotlin`.
- App code imports `dev.wizig.WizigGeneratedApi`.
- `wizig run` regenerates code first, then builds.

## Operational Rules

- Treat generated files as build artifacts; do not hand-edit.
- Regenerate after contract changes.
- Keep contract identifiers stable where possible; rename migrations require host refactors.

## Error Handling

Common command errors:

- Unsupported contract extension.
- Invalid contract field/type token (when using explicit contracts).
- Missing/mismatched generated FFI symbols (validated at API init).

The codegen command prints explicit path and parser failure category to aid debugging.
