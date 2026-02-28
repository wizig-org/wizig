# Wizig Documentation

Wizig is a mobile application framework that keeps product UI native (`SwiftUI`/`Jetpack Compose`) while sharing core runtime and domain logic in Zig.

The framework is built around four hard rules:

- Native hosts are first-class and production-default.
- Cross-platform behavior lives in Zig.
- Host-to-Zig calls are generated from discovered Zig APIs (with optional contract overrides).
- Application scaffolds are app-local and portable (`.wizig/` vendored assets).

## What You Get

When you scaffold an app with `wizig create`, Wizig generates:

- `ios/` and `android/` host apps.
- `lib/` Zig application logic.
- `.wizig/sdk/` host runtime wrappers.
- `.wizig/runtime/` Zig runtime/FFI glue.
- `.wizig/generated/` generated bridge and plugin registrants.
- optional `wizig.api.zig` / `wizig.api.json` contract overrides.

This structure is intentionally self-contained so projects work outside the Wizig repository.

## Reading Path

If you are new to Wizig, read in this order:

1. [Getting Started](getting-started.md)
2. [Architecture](architecture.md)
3. [Bridge And Codegen](bridge-and-codegen.md)
4. [Zig-First Bridge Design](zig-first-bridge.md)
5. [Plugin System](plugin-system.md)

For command details, use [CLI Reference](cli-reference.md).

For implementation-level API details generated from Zig comments, use [API Reference](reference/index.md).

## Design Decisions

High-level design rationale is tracked in ADRs:

- [ADR-0001: Native Host + Zig Core](adr/0001-native-host-plus-zig-core.md)

## Documentation Build

Wizig ships a built-in docs pipeline:

```sh
zig build docs
```

This runs `scripts/docs_build.py`, generates API markdown under `docs/content/reference/`, and renders the static site under `docs/site/`.
