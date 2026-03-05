# Wizig Documentation

Wizig is a mobile application framework that keeps product UI native (SwiftUI / Jetpack Compose) while sharing core runtime and domain logic in Zig.

## Core Principles

- **Native hosts are first-class** — SwiftUI and Jetpack Compose are the production UI layers.
- **Cross-platform behavior lives in Zig** — shared business logic, no UI abstractions.
- **Host-to-Zig calls are generated** — typed bridges discovered from Zig APIs with optional contract overrides.
- **App scaffolds are portable** — `.wizig/` vendored assets make projects self-contained.

## What You Get

When you scaffold an app with `wizig create`, Wizig generates:

| Directory | Purpose |
|-----------|---------|
| `lib/` | Zig application logic |
| `ios/` | iOS SwiftUI host app |
| `android/` | Android Compose host app |
| `.wizig/sdk/` | Vendored host SDK wrappers |
| `.wizig/runtime/` | Vendored Zig runtime/FFI glue |
| `.wizig/generated/` | Generated bridge bindings and plugin registrants |

## Reading Paths

### New to Wizig?

1. [Installation](getting-started/installation.md) — set up your development environment
2. [Quick Start](getting-started/quick-start.md) — create, codegen, and run your first app
3. [Architecture Overview](architecture/overview.md) — understand the four-layer runtime stack

### Building an App?

- [Bridge & Codegen](guide/bridge-and-codegen.md) — how the typed bridge works
- [Plugin System](guide/plugin-system.md) — extend your app with plugins
- [CLI Reference](cli-reference.md) — command-by-command usage

### Understanding the Internals?

- [Runtime Layers](architecture/runtime-layers.md) — detailed layer architecture
- [FFI Design](architecture/ffi-design.md) — C ABI boundary, error handling, memory policy
- [SDK Resolution](architecture/sdk-resolution.md) — how Wizig finds SDK roots

### Contributing?

- [How to Contribute](contributing/index.md) — fork, branch, PR workflow
- [Project Structure](contributing/project-structure.md) — module layout and key entry points
- [Code Style](contributing/code-style.md) — conventions and patterns

## Design Decisions

High-level design rationale is tracked in Architecture Decision Records:

- [ADR-0001: Native Host + Zig Core](adr/0001-native-host-plus-zig-core.md)
