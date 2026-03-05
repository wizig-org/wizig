# Plugin System

Wizig plugin v2 is static and build-time driven. There is no runtime dynamic plugin loading in this phase.

## Goals

- Deterministic build integration on iOS and Android.
- Typed registrants generated into host and Zig code.
- Explicit native dependency metadata (SPM/Maven descriptors).

## Plugin Manifest

Each plugin declares `wizig-plugin.json` with identity, compatibility, and native dependency descriptors.

Typical fields:

- `id` — Unique plugin identifier
- `version` — Plugin version
- `api_version` — Wizig API compatibility version
- `capabilities` — Declared plugin capabilities
- iOS dependency descriptor (`url`, version requirement, product)
- Android dependency descriptor (Maven coordinate, optional classifier/scope)

Validate a plugin manifest:

```sh
wizig plugin validate plugins/my-plugin/wizig-plugin.json
```

## Sync Flow

`wizig plugin sync <project_root>` executes:

1. Scan `plugins/` for manifests
2. Parse and validate descriptors
3. Write deterministic lockfile under `.wizig/plugins/`
4. Generate static registrants in `.wizig/generated/{zig,swift,kotlin}`
5. Apply managed host integration updates

## Generated Registrants

Plugin sync generates registrants for each target language:

| Language | Purpose |
|----------|---------|
| Zig | Runtime/plugin bootstrap integration |
| Swift | iOS host consumption |
| Kotlin | Android host consumption |

The generated registrants are authoritative. Do not hand-edit generated files.

## Adding Plugins

Add a plugin from a Git repository or local path:

```sh
wizig plugin add <git_or_path>
```

Then sync to lock and generate integration outputs:

```sh
wizig plugin sync <project_root>
```

## Interop Model

- Host-native packages remain host-native.
- Plugin bridge surface between host and Zig is generated and typed.
- Direct Zig imports should target true C ABI dependencies only.
