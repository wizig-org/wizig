# Project Structure

## Module Layout

Wizig is organized into focused modules, each with a single responsibility:

| Module | Root Source | Purpose |
|--------|------------|---------|
| `wizig_core` | `src/core/root.zig` | Runtime primitives, plugin manifest, registry codegen |
| `wizig_ffi` | `src/ffi/root.zig` | C ABI bridge; exports `wizig_runtime_*`, `wizig_ffi_*` symbols |
| `wizig_cli` | `src/cli/main.zig` | CLI binary; dispatches to command handlers |
| `wizig` | `src/root.zig` | Compatibility re-export layer |
| `runtime/ffi/` | `runtime/ffi/root.zig` | Vendored FFI for app-local use |

## CLI Commands

Each CLI command lives in its own subdirectory under `src/cli/commands/`:

| Command | Directory | Purpose |
|---------|-----------|---------|
| `create` | `src/cli/commands/create/` | Scaffold new projects |
| `codegen` | `src/cli/commands/codegen/` | Generate typed bridge bindings |
| `run` | `src/cli/commands/run/` | Build and run on device/simulator |
| `build` | `src/cli/commands/build/` | Android multi-ABI and release builds |
| `plugin` | `src/cli/commands/plugin/` | Validate, sync, add plugins |
| `doctor` | `src/cli/commands/doctor/` | Validate host tools |

## Codegen Pipeline

The codegen system (`src/cli/commands/codegen/`) is the most complex subsystem:

| Sub-module | Purpose |
|------------|---------|
| `contract/` | API contract parsing (Zig source and JSON formats) |
| `model/` | `ApiSpec` data structure (methods, params, return types) |
| `project/` | Project analysis: path resolution, lib discovery, type discovery, spec merging |
| `render/` | Per-target code generators |
| `watch/` | File monitoring for incremental codegen |

### Render Targets

| Renderer | Output |
|----------|--------|
| `swift_api` | Swift API client |
| `kotlin_api` | Kotlin API client |
| `zig_ffi_root` | Zig FFI root |
| `ios_c_headers` | iOS C headers |
| `ios_c_shim` | iOS C shim |
| `android_jni_bridge` | Android JNI bridge |
| `zig_ffi_types` | Zig FFI type definitions |
| `zig_app_module` | Zig app module bridge |

## Toolchain Support

| File | Purpose |
|------|---------|
| `toolchains.toml` | Governance policy (single source of truth) |
| `src/cli/support/toolchains/manifest.zig` | TOML parser |
| `src/cli/support/toolchains/probe.zig` | Host tool version detection |
| `src/cli/support/toolchains/version.zig` | Version comparison logic |
| `src/cli/support/toolchains/lockfile.zig` | Lock file generation |

## Build and Tooling

| File/Directory | Purpose |
|----------------|---------|
| `build.zig` | Zig build system configuration |
| `build.zig.zon` | Package manifest |
| `tools/templategen/` | Python template generators for iOS/Android hosts |
| `tools/toolchains/` | Python toolchain docs renderer |
| `scripts/docs_build.py` | API reference markdown generator |
| `scripts/e2e/` | End-to-end test shell scripts |

## Key Entry Points

When working on a specific area, start here:

- **CLI dispatch**: `src/cli/main.zig` — command routing
- **FFI boundary**: `src/ffi/root.zig` — C ABI exports
- **Runtime core**: `src/core/root.zig` — runtime primitives
- **Codegen model**: `src/cli/commands/codegen/model/` — API specification types
- **Plugin registry**: `src/core/` — plugin manifest and registry
