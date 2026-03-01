# Toolchain Manifest Reference

This document is the field-level reference for:

- `toolchains.toml`
- `.wizig/toolchain.lock.json`

Use it when updating policy, extending doctor checks, or debugging lock-file output.

## `toolchains.toml` Reference

Path:

- `toolchains.toml`

## Top-Level Sections

Current sections:

- `[schema]`
- `[doctor]`
- `[doctor.tools.zig]`
- `[doctor.tools.xcodebuild]`
- `[doctor.tools.xcodegen]`
- `[doctor.tools.java]`
- `[doctor.tools.gradle]`
- `[doctor.tools.adb]`
- `[templates.ios]`
- `[templates.android]`
- `[templates.android.versions]`
- `[templates.android.gradle_wrapper]`
- `[docs]`

## `[schema]`

### `version`

- Type: integer (`u32` in parser)
- Required: yes
- Purpose: enables forward schema evolution and parser validation.

Current value:

- `1`

## `[doctor]`

### `strict_default`

- Type: boolean
- Required: yes
- Purpose: default strictness when user does not pass `--strict` or `--no-strict`.

## `[doctor.tools.<id>]`

Supported `<id>` values:

- `zig`
- `xcodebuild`
- `xcodegen`
- `java`
- `gradle`
- `adb`

Each tool block supports:

### `required`

- Type: boolean
- Required: yes
- Purpose: marks whether missing/outdated tool is mandatory for healthy baseline.

### `min_version`

- Type: string
- Required: yes
- Purpose: minimum accepted version checked by `wizig doctor`.

## `[templates.ios]`

### `deployment_target`

- Type: string
- Required: yes
- Purpose: iOS deployment target injected into generated Xcode project settings.

## `[templates.android]`

### `compile_sdk`

- Type: integer
- Required: yes
- Purpose: compile SDK used in generated Android `build.gradle.kts`.

### `min_sdk`

- Type: integer
- Required: yes
- Purpose: minimum supported Android SDK level.

### `target_sdk`

- Type: integer
- Required: yes
- Purpose: target SDK level for generated Android host.

### `java_version`

- Type: integer
- Required: yes
- Purpose: Java language level used in generated Android compile options.

### `kotlin_jvm_target`

- Type: string
- Required: yes
- Purpose: Kotlin JVM toolchain target used in generated host config.

## `[templates.android.versions]`

These fields pin generated dependency catalog and Android host dependency versions.

Current keys:

- `agp`
- `kotlin`
- `androidx_core_ktx`
- `androidx_lifecycle_runtime_ktx`
- `androidx_activity_compose`
- `androidx_compose_bom`
- `junit`
- `androidx_junit`
- `espresso_core`
- `jna`

All are string values and required by current generator flow.

## `[templates.android.gradle_wrapper]`

### `version`

- Type: string
- Required: yes
- Purpose: Gradle wrapper distribution version.

### `distribution_type`

- Type: string
- Required: yes
- Expected values: `bin`, `all`
- Purpose: wrapper artifact type.

### `distribution_sha256`

- Type: string
- Required: no (but strongly recommended)
- Purpose: wrapper distribution checksum in generated properties.

### `network_timeout`

- Type: integer
- Required: yes
- Purpose: wrapper download timeout in milliseconds.

### `validate_distribution_url`

- Type: boolean
- Required: yes
- Purpose: Gradle wrapper URL validation toggle.

## `[docs]`

### `python_min`

- Type: string
- Required: yes
- Purpose: rendered requirement for docs tooling baseline.

## Parser Behavior Notes

The current Zig parser (`cli/src/support/toolchains/manifest.zig`) intentionally reads only fields required by CLI features.

Important behaviors:

- Unknown sections/keys are ignored.
- Missing required parsed fields produce `error.InvalidManifest`.
- Manifest SHA-256 is computed from raw file bytes and stored in memory for lockfile output.

## `.wizig/toolchain.lock.json` Reference

Path pattern:

- `<app_root>/.wizig/toolchain.lock.json`

Written by:

- `wizig create`

## Top-Level Fields

### `schema_version`

- Type: integer
- Current value: `1`
- Purpose: lock file schema version.

### `manifest_schema_version`

- Type: integer
- Purpose: mirrors `[schema].version` from `toolchains.toml` used at creation time.

### `manifest_sha256`

- Type: string (hex)
- Purpose: hash of exact manifest bytes used when lock file was created.

### `created_at_unix`

- Type: integer
- Purpose: Unix timestamp (`seconds`) for lock-file creation time.

### `tools`

- Type: object map
- Keys: tool ids (`zig`, `xcodebuild`, `xcodegen`, `java`, `gradle`, `adb`)
- Purpose: per-tool policy and probe snapshot.

## Tool Entry Fields

Each `tools.<id>` entry contains:

### `required`

- Type: boolean
- Source: `toolchains.toml` doctor tool policy.

### `min_version`

- Type: string
- Source: `toolchains.toml` doctor tool policy.

### `detected`

- Type: boolean
- Source: runtime probe result.

### `detected_version`

- Type: string or `null`
- Source: parsed probe output.

## Example Lock File

```json
{
  "schema_version": 1,
  "manifest_schema_version": 1,
  "manifest_sha256": "<hex>",
  "created_at_unix": 1700000000,
  "tools": {
    "zig": {
      "required": true,
      "min_version": "0.15.1",
      "detected": true,
      "detected_version": "0.15.1"
    }
  }
}
```

## Operational Guidance

When reviewing a lock file in PRs:

1. Confirm `manifest_sha256` changes when policy changed.
2. Confirm detected versions match expected local toolchain.
3. Confirm required tool entries are present for all supported tools.

When adding a new governed tool:

1. Add new `[doctor.tools.<id>]` section in `toolchains.toml`.
2. Extend `ToolId` and ordered tool list in `types.zig`.
3. Add probe command/parser logic in `probe.zig`.
4. Add/adjust tests for parsing and lock output.
5. Update this reference document.

