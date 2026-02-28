# Plugin System

Wizig plugin v2 is static and build-time driven.

There is no runtime dynamic plugin loading in this phase.

## Plugin Goals

- Deterministic build integration on iOS and Android.
- Typed registrants generated into host and Zig code.
- Explicit native dependency metadata (SPM/Maven descriptors).

## Manifest

Each plugin declares `wizig-plugin.json` with identity, compatibility, and native dependency descriptors.

Typical fields:

- `id`
- `version`
- `api_version`
- `capabilities`
- iOS dependency descriptor (`url`, version requirement, product)
- Android dependency descriptor (Maven coordinate, optional classifier/scope)

Use:

```sh
wizig plugin validate plugins/my-plugin/wizig-plugin.json
```

to verify schema and constraints in isolation.

## Sync Flow

`wizig plugin sync <project_root>` executes:

1. Scan `plugins/` for manifests.
2. Parse and validate descriptors.
3. Write deterministic lockfile under `.wizig/plugins/`.
4. Generate static registrants in `.wizig/generated/{zig,swift,kotlin}`.
5. Apply managed host integration updates.

## Generated Registrants

- Zig registrant source used by runtime/plugin bootstrap.
- Swift registrant source consumed by iOS host.
- Kotlin registrant source consumed by Android host.

The generated registrants are authoritative. Do not hand-edit generated files.

## Adding Community Plugins

Use:

```sh
wizig plugin add <git_or_path>
```

Then run:

```sh
wizig plugin sync <project_root>
```

to lock and generate integration outputs.

## Interop Model

- Host-native packages remain host-native.
- Plugin bridge surface between host and Zig is generated and typed.
- Direct Zig imports should target true C ABI dependencies only.
