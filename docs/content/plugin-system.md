# Plugin System

## Manifest

Plugins are declared by `ziggy-plugin.json` manifests.

Core fields:

- `id`
- `version`
- `api_version`
- `capabilities`
- native dependency descriptors (SPM/Maven)

## Sync Flow

`ziggy plugin sync <project_root>` performs:

1. Scan `plugins/`
2. Parse and validate manifests
3. Produce deterministic lockfile under `.ziggy/plugins/`
4. Generate registrants for Zig/Swift/Kotlin
5. Update managed host integration sections

## Generated Registrants

- Zig registrant source
- Swift registrant source
- Kotlin registrant source

These are static build-time registries (no runtime plugin loading in v1).

## Validation

Use:

```sh
ziggy plugin validate path/to/ziggy-plugin.json
```

to validate schema and descriptor constraints in isolation.
