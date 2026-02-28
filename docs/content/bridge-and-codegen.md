# Bridge And Codegen

## Contract Sources

Wizig supports two contract sources:

1. `wizig.api.zig` (preferred)
2. `wizig.api.json` (compatibility fallback)

Contract resolution order for `wizig codegen` and `wizig run`:

1. explicit `--api <path>`
2. `<project>/wizig.api.zig`
3. `<project>/wizig.api.json`

## Zig Contract Shape

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
- Kotlin: `.wizig/generated/kotlin/dev/wizig/generated/WizigGeneratedApi.kt`

Generated outputs contain:

- Method clients matching contract signatures.
- Event sink protocol/interface declarations.
- Event emit helpers bound to those sink surfaces.

## Host Integration

### iOS

- App target sources include `../.wizig/generated/swift`.
- App code can instantiate `WizigGeneratedApi` directly.
- `wizig run` regenerates code first, then builds.

### Android

- App module includes generated Kotlin source directory under `main` source set.
- App code imports `dev.wizig.generated.WizigGeneratedApi`.
- `wizig run` regenerates code first, then builds.

## Operational Rules

- Treat generated files as build artifacts; do not hand-edit.
- Regenerate after contract changes.
- Keep contract identifiers stable where possible; rename migrations require host refactors.

## Error Handling

Common command errors:

- Missing contract file.
- Unsupported contract extension.
- Invalid contract field/type token.

The codegen command prints explicit path and parser failure category to aid debugging.
