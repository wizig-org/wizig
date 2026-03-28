# Contribution Guide

This document explains how to contribute to Wizig, how to build and test the repository locally, and how releases are produced.

Wizig combines:
- a Zig CLI and code generator
- a shared Zig runtime and FFI boundary
- native iOS and Android host integrations
- generated templates, docs, and vendored SDK/runtime assets

## 1. Getting Started

Use the normal fork-and-branch workflow:

```sh
git clone https://github.com/<you>/wizig.git
cd wizig
git checkout -b <topic-branch>
```

Open pull requests against `main`.

## 2. Toolchain Requirements

The repository currently exposes two Zig version signals:

- [`build.zig.zon`](build.zig.zon) requires Zig `0.16.0-dev.2670+56253d9e3` or newer to build the repository.
- [`toolchains.toml`](toolchains.toml) currently sets the minimum app-facing `wizig doctor` Zig policy to `0.15.1`.

For repository development, follow the stricter requirement from `build.zig.zon`.

| Tool | Current expectation | Source of truth |
| --- | --- | --- |
| Zig | `0.16.0-dev.2670+56253d9e3` or newer | `build.zig.zon` |
| Xcode / `xcodebuild` | `26.0.0+` | `toolchains.toml` |
| XcodeGen | `2.39.0+` optional | `toolchains.toml` |
| Java | `21.0.0+` | `toolchains.toml` |
| Gradle | `9.2.1+` | `toolchains.toml` |
| `adb` | `1.0.41+` | `toolchains.toml` |
| Python | `3.10+` | `toolchains.toml`, docs tooling |

Example Homebrew baseline:

```sh
brew install gradle openjdk@21 python
brew install --cask android-platform-tools android-commandlinetools
brew install xcodegen
python3 -m pip install -r docs/requirements.txt
```

Validate your environment after setup:

```sh
zig build
./zig-out/bin/wizig doctor --sdk-root .
```

## 3. Repository Map

Key entry points:

| Path | Purpose |
| --- | --- |
| [`build.zig`](build.zig) | Build graph, install steps, tests, docs, and e2e entrypoints |
| [`src/cli/main.zig`](src/cli/main.zig) | CLI entrypoint |
| [`src/cli/commands/`](src/cli/commands) | Command implementations |
| [`src/core/root.zig`](src/core/root.zig) | Shared runtime/core primitives |
| [`src/ffi/root.zig`](src/ffi/root.zig) | Exported C ABI |
| [`runtime/ffi/root.zig`](runtime/ffi/root.zig) | Vendored runtime-side FFI |
| [`tools/templategen/`](tools/templategen) | Template generators |
| [`scripts/docs_build.py`](scripts/docs_build.py) | API reference generation and docs determinism checks |
| [`scripts/e2e/`](scripts/e2e) | End-to-end scaffold and run checks |
| [`toolchains.toml`](toolchains.toml) | Toolchain policy and template defaults |

## 4. Contribution Standards

Follow the conventions in [`docs/contributing/code-style.md`](docs/contributing/code-style.md).

For day-to-day work:

- run `zig fmt` on every Zig file you touch
- keep module docs (`//!`) and public declaration docs (`///`) accurate
- prefer small focused files over large multi-purpose files
- keep authored source files under 300 lines unless there is a reviewed exception
- keep outputs deterministic
- do not hand-edit generated outputs under `.wizig/generated/` or generated reference docs under `docs/reference/api/`
- prefer targeted inline `test` blocks near the code they validate
- keep allocator flow explicit and avoid hidden global state

If you change [`toolchains.toml`](toolchains.toml), treat it as the source of truth for doctor policy and template defaults.

## 5. Build Commands

The build graph is defined in [`build.zig`](build.zig).

```sh
zig build
zig build test
zig build e2e
zig build run -- <wizig args>
zig build docs
```

| Command | Purpose |
| --- | --- |
| `zig build` | Build `wizig`, install SDK/runtime/templates, install `toolchains.toml`, and produce FFI artifacts |
| `zig build test` | Run the aggregated test suites |
| `zig build e2e` | Run the self-contained scaffold/template e2e pipeline |
| `zig build run -- <args>` | Run the built CLI |
| `zig build docs` | Regenerate toolchain docs, rebuild API reference docs, and run `mkdocs build` |

The install step currently produces:

- `zig-out/bin/wizig`
- `zig-out/share/wizig/sdk`
- `zig-out/share/wizig/runtime`
- `zig-out/share/wizig/templates`
- `zig-out/share/wizig/toolchains.toml`
- `zig-out/lib/libwizigffi.*`
- `zig-out/include/wizig.h`

The shipped CLI version comes from:

```sh
zig build -Dversion=<version>
```

That embedded version is injected by CI and release workflows. It is not taken from the placeholder package version in [`build.zig.zon`](build.zig.zon).

## 6. Testing

Use the full suite as the default verification path:

```sh
zig build test --summary all
```

The aggregated suites are:

| Suite | Root |
| --- | --- |
| `core-tests` | `src/core/root.zig` |
| `ffi-tests` | `src/ffi/root.zig` |
| `compatibility-tests` | `src/root.zig` |
| `cli-tests` | `src/cli/main.zig` |

Targeted `zig test <module-root>` runs are useful for focused work, especially in facade modules. Do not assume every internal helper file is a valid standalone Zig module root; some internal code is only compiled through the aggregated CLI test graph. When in doubt, trust `zig build test --summary all`.

### End-to-end tests

The e2e entrypoint is:

```sh
zig build e2e
```

That step runs [`scripts/e2e/self_contained_template_pipeline.sh`](scripts/e2e/self_contained_template_pipeline.sh).

Useful overrides from [`scripts/e2e/README.md`](scripts/e2e/README.md):

- `WIZIG_TESTS_ROOT`
- `WIZIG_E2E_TEST_ROOT`
- `WIZIG_E2E_WORK_ROOT`
- `WIZIG_E2E_WIZIG_BIN`
- `WIZIG_E2E_REQUIRE_IOS_SLICE=1`
- `WIZIG_E2E_KEEP=1`

Run e2e locally when you change scaffolding, template generation, packaging assumptions, or run/build flows that affect generated app hosts.

### Docs verification

If you touch docs, public declarations, or docs generation:

```sh
python3 scripts/docs_build.py --check
zig build docs
```

## 7. CI

The current workflows live in:

- [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
- [`.github/workflows/docs-check.yml`](.github/workflows/docs-check.yml)
- [`.github/workflows/release.yml`](.github/workflows/release.yml)

The main CI workflow currently runs:

- `zig build test -j1 --summary all`
- `zig build -Doptimize=ReleaseSafe -Dversion="ci-<sha>" --summary all`
- Linux artifact packaging
- `python3 scripts/docs_build.py --check`

The dedicated docs workflow runs on relevant source/doc changes and validates docs determinism with the full docs dependency set.

At the time of writing, the main CI workflow does not run `zig build e2e` on every push. Treat e2e as a local or manually-triggered pre-merge check for scaffold/template-sensitive changes.

## 8. Special Cases

If you change [`toolchains.toml`](toolchains.toml):

```sh
python3 tools/toolchains/render_docs.py
python3 scripts/docs_build.py --check
zig build
zig build test --summary all
./zig-out/bin/wizig doctor --sdk-root .
```

If you change template seeds or template generators:

```sh
python3 tools/templategen/generate_templates.py --out build/generated/templates
zig build
zig build e2e
```

If you change documented public Zig, Swift, or Kotlin declarations:

```sh
python3 scripts/docs_build.py --check
zig build docs
```

## 9. Pull Requests

Before opening a pull request:

1. run `zig fmt` on changed Zig files
2. run `zig build test --summary all`
3. run `zig build e2e` if the change affects scaffolds, packaging, or runtime integration
4. run `python3 scripts/docs_build.py --check` if the change affects docs or public declarations
5. update [`CHANGELOG.md`](CHANGELOG.md) if the change is user-visible

PR descriptions should explain what changed, why it changed, what you ran to verify it, and any rollout or migration risk.

Release notes are categorized by labels from [`.github/release.yml`](.github/release.yml). Use the existing release-facing labels when appropriate:

- `breaking`, `breaking-change`
- `feature`, `enhancement`
- `bug`, `fix`, `bugfix`
- `documentation`, `docs`

## 10. Release Process

Releases are automated through [`.github/workflows/release.yml`](.github/workflows/release.yml).

The workflow can be triggered by:

- pushing a tag matching `v*`
- pushing a numeric tag matching `[0-9]*`
- manually dispatching the workflow with a `tag` input

Examples:

```sh
git tag v0.1.0
git push origin v0.1.0
```

```sh
git tag 0.1.0
git push origin 0.1.0
```

The workflow strips a leading `v` when embedding the version string.

Before tagging:

1. ensure the release commit is ready
2. run `zig build test --summary all`
3. run `zig build e2e` for scaffold/runtime-sensitive changes
4. run `python3 scripts/docs_build.py --check`
5. update [`CHANGELOG.md`](CHANGELOG.md)
6. make sure merged PRs have correct release labels

The release workflow currently:

1. runs repository tests on Ubuntu
2. builds tarballs for `aarch64-macos`, `x86_64-macos`, `x86_64-linux-gnu`, and `aarch64-linux-gnu`
3. packages each build as `wizig-<version>-<os>-<arch>.tar.gz`
4. generates `.sha256` files
5. creates a GitHub Release with generated notes
6. updates `wizig-org/homebrew-tap`

Current release tarballs contain:

- `bin/wizig`
- `share/wizig/sdk`
- `share/wizig/runtime`
- `share/wizig/templates`
- `share/wizig/toolchains.toml`
- `lib/libwizigffi.a`
- `include/wizig.h`

After release, verify the GitHub Release assets, checksum files, release notes, and Homebrew tap update.
