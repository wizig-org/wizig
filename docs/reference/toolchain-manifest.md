# Toolchain Manifest Reference

Field-level reference for `toolchains.toml` and `.wizig/toolchain.lock.json`.

## `toolchains.toml`

Located at the repository root.

### `[schema]`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `version` | `u32` | yes | Schema version for forward evolution and parser validation |

Current value: `1`

### `[doctor]`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `strict_default` | boolean | yes | Default strictness when `--strict`/`--no-strict` not passed |

### `[doctor.tools.<id>]`

Supported tool IDs: `zig`, `xcodebuild`, `xcodegen`, `java`, `gradle`, `adb`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `required` | boolean | yes | Whether missing/outdated tool is mandatory |
| `min_version` | string | yes | Minimum accepted version for `wizig doctor` |

### `[templates.ios]`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `deployment_target` | string | yes | iOS deployment target in generated Xcode settings |

### `[templates.android]`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `compile_sdk` | integer | yes | Compile SDK in generated `build.gradle.kts` |
| `min_sdk` | integer | yes | Minimum Android SDK level |
| `target_sdk` | integer | yes | Target SDK level |
| `java_version` | integer | yes | Java language level in compile options |
| `kotlin_jvm_target` | string | yes | Kotlin JVM toolchain target |

### `[templates.android.versions]`

Pins generated dependency catalog and Android host dependency versions:

`agp`, `kotlin`, `androidx_core_ktx`, `androidx_lifecycle_runtime_ktx`, `androidx_activity_compose`, `androidx_compose_bom`, `junit`, `androidx_junit`, `espresso_core`, `jna`

All string values, required by current generator flow.

### `[templates.android.gradle_wrapper]`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `version` | string | yes | Gradle wrapper distribution version |
| `distribution_type` | string | yes | `bin` or `all` |
| `distribution_sha256` | string | no (recommended) | Wrapper distribution checksum |
| `network_timeout` | integer | yes | Download timeout in milliseconds |
| `validate_distribution_url` | boolean | yes | URL validation toggle |

### `[docs]`

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `python_min` | string | yes | Minimum Python version for docs tooling |

### Parser Behavior

- Unknown sections/keys are ignored.
- Missing required fields produce `error.InvalidManifest`.
- Manifest SHA-256 is computed from raw bytes for lockfile output.

---

## `.wizig/toolchain.lock.json`

Located at `<app_root>/.wizig/toolchain.lock.json`. Written by `wizig create`.

### Top-Level Fields

| Field | Type | Purpose |
|-------|------|---------|
| `schema_version` | integer | Lock file schema version (current: `1`) |
| `manifest_schema_version` | integer | Mirrors `[schema].version` from `toolchains.toml` |
| `manifest_sha256` | string (hex) | Hash of exact manifest bytes used |
| `created_at_unix` | integer | Unix timestamp (seconds) of creation |
| `tools` | object | Per-tool policy and probe snapshot |

### Tool Entry Fields (`tools.<id>`)

| Field | Type | Source |
|-------|------|--------|
| `required` | boolean | `toolchains.toml` doctor policy |
| `min_version` | string | `toolchains.toml` doctor policy |
| `detected` | boolean | Runtime probe result |
| `detected_version` | string or null | Parsed probe output |

### Example

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

### Operational Guidance

When reviewing a lock file:

1. Confirm `manifest_sha256` changes when policy changed.
2. Confirm detected versions match expected local toolchain.
3. Confirm required tool entries are present for all supported tools.

When adding a new governed tool:

1. Add `[doctor.tools.<id>]` section in `toolchains.toml`.
2. Extend `ToolId` and ordered tool list in `types.zig`.
3. Add probe command/parser logic in `probe.zig`.
4. Add/adjust tests for parsing and lock output.
5. Update this reference document.
