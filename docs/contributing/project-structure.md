# Project Structure

## Module Layout

Wizig is organized into focused modules, each with a single responsibility:

| Module | Root Source | Purpose |
|--------|------------|---------|
| `wizig_core` | `core/src/root.zig` | Runtime primitives, plugin manifest, registry codegen |
| `wizig_ffi` | `ffi/src/root.zig` | C ABI bridge; exports `wizig_runtime_*`, `wizig_ffi_*` symbols |
| `wizig_cli` | `cli/src/main.zig` | CLI binary; dispatches to command handlers |
| `wizig` | `src/root.zig` | Compatibility re-export layer |
| `runtime/ffi/` | `runtime/ffi/src/root.zig` | Vendored FFI for app-local use |

## CLI Commands

Each CLI command lives in its own subdirectory under `cli/src/commands/`:

| Command | Directory | Purpose |
|---------|-----------|---------|
| `create` | `cli/src/commands/create/` | Scaffold new projects |
| `codegen` | `cli/src/commands/codegen/` | Generate typed bridge bindings |
| `run` | `cli/src/commands/run/` | Build and run on device/simulator |
| `build` | `cli/src/commands/build/` | Android multi-ABI and release builds |
| `plugin` | `cli/src/commands/plugin/` | Validate, sync, add plugins |
| `doctor` | `cli/src/commands/doctor/` | Validate host tools |

## Codegen Pipeline

The codegen system (`cli/src/commands/codegen/`) is the most complex subsystem:

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
| `cli/src/support/toolchains/manifest.zig` | TOML parser |
| `cli/src/support/toolchains/probe.zig` | Host tool version detection |
| `cli/src/support/toolchains/version.zig` | Version comparison logic |
| `cli/src/support/toolchains/lockfile.zig` | Lock file generation |

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

- **CLI dispatch**: `cli/src/main.zig` — command routing
- **FFI boundary**: `ffi/src/root.zig` — C ABI exports
- **Runtime core**: `core/src/root.zig` — runtime primitives
- **Codegen model**: `cli/src/commands/codegen/model/` — API specification types
- **Plugin registry**: `core/src/` — plugin manifest and registry
