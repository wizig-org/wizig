# Toolchain Governance

Wizig toolchain governance ensures that CLI checks, host template generation, and docs requirements are all derived from a single policy source.

The policy source is:

- `toolchains.toml`

This page explains the intent, data flow, strict-mode behavior, and operating workflows.

## Goals

The governance system was introduced to solve four recurring problems:

1. Version drift between CLI checks and generated templates.
2. Unknown host state at scaffold time.
3. Manual docs updates that get stale.
4. Non-repeatable developer setup and CI outcomes.

The design objective is deterministic policy propagation with minimal duplicated configuration.

## Single Source Of Truth

`toolchains.toml` is the canonical policy file.

It currently defines:

- Schema versioning (`[schema]`).
- Doctor enforcement policy (`[doctor]`, `[doctor.tools.<id>]`).
- iOS host defaults (`[templates.ios]`).
- Android host defaults and dependency pins (`[templates.android]`, `[templates.android.versions]`, `[templates.android.gradle_wrapper]`).
- Docs tooling constraints (`[docs]`).

When a value needs to change (for example Gradle wrapper version), the change should be made only in `toolchains.toml`, then propagated through the documented generation workflow.

## System Data Flow

Policy values fan out through four independent consumers.

### 1. `wizig doctor`

`wizig doctor` reads `toolchains.toml` and evaluates host tools against policy.

Implementation path:

- `cli/src/commands/doctor/root.zig`
- `cli/src/support/toolchains/manifest.zig`
- `cli/src/support/toolchains/probe.zig`
- `cli/src/support/toolchains/version.zig`

Doctor evaluates each tool with:

- `required` (`true` or `false`)
- `min_version`

It reports:

- Missing tools.
- Unparseable version outputs.
- Versions below minimum.

### 2. Template Generation

Template generation consumes policy values to render host defaults and version pins.

Implementation path:

- `tools/templategen/generate_templates.py`
- `tools/templategen/common.py`
- `tools/templategen/ios_generator.py`
- `tools/templategen/android_generator.py`

Generated outputs include:

- iOS deployment target updates.
- Android SDK/JVM defaults.
- Android version catalog pinning.
- Gradle wrapper properties pinning.

### 3. Create-Time Lock File

`wizig create` writes `.wizig/toolchain.lock.json` inside every generated app.

Implementation path:

- `cli/src/commands/create/toolchain_lock.zig`
- `cli/src/support/toolchains/lockfile.zig`

The lock file captures:

- Policy schema version.
- SHA-256 hash of the exact manifest bytes used.
- Host tool probe results observed at scaffold time.

This gives traceability for support and CI diagnostics.

### 4. Development Requirements Docs

Development requirements docs are rendered from policy values.

Implementation path:

- `tools/toolchains/render_docs.py`

Rendered outputs:

- `docs/content/development-requirements.md`
- `docs/development-requirements.md`

This keeps published requirements aligned with doctor/template policy.

## Strict Mode Semantics

`wizig doctor` supports:

- `--strict`
- `--no-strict`
- `toolchains.toml` default via `[doctor].strict_default`

Priority order:

1. Command-line flag (`--strict` or `--no-strict`).
2. Manifest default (`strict_default`).

Behavior summary:

- Strict mode disabled: doctor returns warnings when issues are found.
- Strict mode enabled: doctor exits non-zero if any issue is found.

Current implementation treats both required and optional tool issues as failing in strict mode.

## Lock File Lifecycle

Lock generation happens during `wizig create` after initial scaffold and codegen steps.

File location:

- `<app_root>/.wizig/toolchain.lock.json`

Use cases:

- Confirm which policy file snapshot was used.
- Confirm detected host versions at app creation time.
- Compare local and CI environments during debugging.

When policy changes later, existing app lock files remain historical evidence unless explicitly regenerated.

## How To Update Policy Safely

When changing `toolchains.toml`:

1. Edit policy values.
2. Regenerate templates.
3. Regenerate docs.
4. Run unit tests and build.
5. Validate `wizig doctor` behavior.

Recommended command sequence:

```sh
python3 tools/templategen/generate_templates.py --out build/generated/templates
python3 tools/toolchains/render_docs.py
zig build test
zig build
```

For docs freshness checks:

```sh
python3 tools/toolchains/render_docs.py --check
python3 scripts/docs_build.py --check
```

## CI Recommendations

Use governance checks as explicit CI gates:

1. `zig build test`
2. `zig build`
3. `python3 tools/toolchains/render_docs.py --check`
4. `python3 scripts/docs_build.py --check`
5. (Optional) `wizig doctor --strict --sdk-root <repo_root>`

These checks prevent policy drift from entering main.

## Common Failure Modes

### Doctor reports missing `toolchains.toml`

Cause:

- Incorrect `--sdk-root`.
- Incomplete SDK install layout.

Action:

- Re-run with an explicit root that contains `toolchains.toml`.

### Template versions do not match manifest

Cause:

- Templates were not regenerated after manifest changes.

Action:

- Re-run templategen and commit the resulting changes.

### Docs show stale requirements

Cause:

- `render_docs.py` not run after policy updates.

Action:

- Re-run docs renderer and commit outputs.

### Lock file versions look unexpected

Cause:

- Tool version parser mismatch for local command output format.

Action:

- Re-run `wizig doctor` and inspect reported parsed version values.
- Update probe heuristics if output format changed.

## Ownership Model

To keep governance healthy:

- Treat `toolchains.toml` as a reviewed API contract.
- Update templates/docs only through generator scripts.
- Keep tool parser and version-compare tests up to date when adding tools.
- Keep policy changes and generated output updates in the same PR.

