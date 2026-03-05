# Architecture Overview

## Goals

Wizig is optimized for three constraints:

- **Keep platform UX native and first-class** — SwiftUI on iOS, Jetpack Compose on Android.
- **Share runtime/domain logic across hosts with Zig** — write once, bridge everywhere.
- **Keep host interop typed and deterministic** — generated bindings, not handwritten FFI.

## Four-Layer Runtime Stack

Wizig applications are structured in four layers:

1. **Host UI** — Native platform UI (SwiftUI / Jetpack Compose)
2. **Generated Bridge** — Typed Swift, Kotlin, and Zig clients generated from API discovery
3. **FFI/Runtime** — C ABI symbols exported by `ffi/src/root.zig` with runtime primitives
4. **App Domain** — Business logic written in Zig under `lib/`

See [Runtime Layers](runtime-layers.md) for a detailed breakdown of each layer.

## Scaffold Layout

`wizig create` produces a self-contained project:

| Directory | Purpose |
|-----------|---------|
| `lib/` | App logic (Zig) |
| `ios/` | iOS host project |
| `android/` | Android host project |
| `.wizig/sdk/` | Vendored host SDK wrappers |
| `.wizig/runtime/` | Vendored runtime sources |
| `.wizig/generated/` | Generated bridge + registrants |
| `plugins/` | Local plugin packages |
| `wizig.yaml` | App configuration |

Vendoring `.wizig/` assets is deliberate: projects remain portable and do not depend on Wizig repository-relative paths.

## Type-Safety Boundary

Type safety is generated from discovered Zig APIs into all target languages:

- Host call signatures are generated, not handwritten.
- Event sink interfaces are generated, not handwritten.
- API drift fails fast during generated binding validation/compile steps.

The transport boundary still uses C ABI for runtime interoperability, but application-facing APIs stay typed.

## Key Design Decisions

- **Arena allocators** throughout command execution for predictable memory management.
- **Toolchain governance** via `toolchains.toml` — enforced by `run` and `codegen` unless `--allow-toolchain-drift` is passed.
- **SDK resolution** follows a strict precedence chain: CLI flag > env var > install-relative > dev workspace fallback. See [SDK Resolution](sdk-resolution.md).

## Web Expansion Hooks

Current web scope is interface-only:

- Target abstraction exists in codegen design.
- Runtime host capability abstractions reserve future web integration.
- No production web runtime is shipped in this phase.
