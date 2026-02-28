# Bridge And Codegen

## Contract Sources

Ziggy supports two contract sources:

1. `ziggy.api.zig` (preferred)
2. `ziggy.api.json` (compatibility fallback)

Contract resolution order for `ziggy codegen` and `ziggy run`:

1. explicit `--api <path>`
2. `<project>/ziggy.api.zig`
3. `<project>/ziggy.api.json`

## Zig Contract Shape

Minimal Zig contract:

```zig
pub const namespace = "dev.ziggy.app";

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

Running `ziggy codegen <project_root>` emits:

- Zig: `.ziggy/generated/zig/ZiggyGeneratedApi.zig`
- Swift: `.ziggy/generated/swift/ZiggyGeneratedApi.swift`
- Kotlin: `.ziggy/generated/kotlin/dev/ziggy/generated/ZiggyGeneratedApi.kt`

Generated outputs contain:

- Method clients matching contract signatures.
- Event sink protocol/interface declarations.
- Event emit helpers bound to those sink surfaces.

## Host Integration

### iOS

- App target sources include `../.ziggy/generated/swift`.
- App code can instantiate `ZiggyGeneratedApi` directly.
- `ziggy run` regenerates code first, then builds.

### Android

- App module includes generated Kotlin source directory under `main` source set.
- App code imports `dev.ziggy.generated.ZiggyGeneratedApi`.
- `ziggy run` regenerates code first, then builds.

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
