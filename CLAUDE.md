# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Wizig?

Wizig is a framework for building native iOS (SwiftUI) and Android (Jetpack Compose) apps with shared Zig runtime logic and automatically generated typed bridges (Swift/Kotlin) from discovered Zig APIs.

Runtime stack: Host UI -> Generated Bridge (Swift/Kotlin/Zig) -> Wizig FFI Runtime (C ABI) -> App Domain Logic (lib/*.zig)

## Build Commands

```sh
zig build                        # Build CLI, FFI libs, install SDK/runtime/templates
zig build test --summary all     # Run all test suites (preferred verification path)
zig build e2e                    # End-to-end scaffold/template pipeline
zig build run -- <args>          # Run the built CLI with arguments
zig build docs                   # Regenerate docs (toolchains + API ref + mkdocs)
zig build -Dversion="x.y.z"     # Build with embedded version string (used by CI/releases)
```

## Testing

Tests are inline `test` blocks in their respective modules. Run `zig build test --summary all` as the default check.

Four test suites: `core-tests` (`src/core/root.zig`), `ffi-tests` (`src/ffi/root.zig`), `compatibility-tests` (`src/root.zig`), `cli-tests` (`src/cli/main.zig`).

Not all internal files are valid standalone Zig module roots -- some only compile through the aggregated test graph. When in doubt, use `zig build test --summary all`.

Run `zig build e2e` locally when changing scaffolding, templates, packaging, or run/build host integration. Use `WIZIG_E2E_KEEP=1` to preserve test artifacts for debugging.

## Module Architecture

| Module | Root | Purpose |
|--------|------|---------|
| `wizig_core` | `src/core/root.zig` | Runtime primitives, plugin manifest, registry codegen |
| `wizig_ffi` | `src/ffi/root.zig` | C ABI bridge (exports `wizig_runtime_*` / `wizig_ffi_*` symbols) |
| `wizig_cli` | `src/cli/main.zig` | CLI binary; depends on `wizig_core` + `build_options` |
| `wizig` | `src/root.zig` | Compatibility re-export layer over `wizig_core` |
| runtime FFI | `runtime/ffi/root.zig` | Vendored FFI for app-local use |

The CLI dispatcher (`src/cli/main.zig`) routes to command handlers in `src/cli/commands/`: `create`, `codegen`, `run`, `build`, `plugin`, `doctor`, `self_update`, `uninstall`.

**Codegen** (`src/cli/commands/codegen/`) is the most complex subsystem with ~66 files: `contract/` (API parsing), `model/` (ApiSpec data structure), `project/` (path resolution, lib/type discovery, spec merging), `render/` (per-target code generators), `watch/` (file monitoring).

Support utilities live in `src/cli/support/` (path, fs, process, errors, sdk_locator, toolchains/).

## Key Conventions

- **Allocators**: Use arena allocators for command execution, pass explicitly, never use global state.
- **Error handling**: Zig error unions (`!T`), domain-specific error sets, propagate with `try`, catch only at boundaries.
- **FFI boundary**: Return integer status codes (never Zig errors), thread-local error envelopes, prefix exports with `wizig_runtime_` or `wizig_ffi_`.
- **File size**: Keep authored source files under 300 lines unless reviewed exception.
- **Determinism**: Codegen, lockfiles, and docs must produce identical output for identical inputs.
- **Generated code**: Never hand-edit files under `.wizig/generated/` or `docs/reference/api/`.
- **Formatting**: Run `zig fmt` on changed Zig files before committing.

## Special Workflows

When changing `toolchains.toml` (single source of truth for doctor policy and template defaults):
```sh
python3 tools/toolchains/render_docs.py
python3 scripts/docs_build.py --check
zig build && zig build test --summary all
./zig-out/bin/wizig doctor --sdk-root .
```

When changing template seeds or generators:
```sh
python3 tools/templategen/generate_templates.py --out build/generated/templates
zig build && zig build e2e
```

When changing public declarations or docs:
```sh
python3 scripts/docs_build.py --check
zig build docs
```

## Toolchain Requirements

Zig `0.16.0-dev.2670+56253d9e3` or newer (from build.zig.zon). Other requirements defined in `toolchains.toml`: Xcode 26+, Java 21+, Gradle 9.2.1+, Python 3.10+. Validate with `./zig-out/bin/wizig doctor --sdk-root .`.

## CI

Main CI (`.github/workflows/ci.yml`) runs: `zig build test -j1 --summary all`, ReleaseSafe build, Linux packaging, docs determinism check. E2E tests are **not** part of regular CI -- run locally for scaffold/template changes.
