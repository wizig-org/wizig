# Wizig Plugin API

`wizig-plugin.json` declares plugin identity, contract version, and native dependencies.

## Fields

- `id`: reverse-domain plugin identifier
- `version`: plugin implementation version
- `api_version`: Wizig plugin API compatibility version
- `capabilities`: permissions requested by plugin
- `ios_spm`: Swift Package Manager dependencies (`url`, `requirement`, `product`)
- `android_maven`: Gradle/Maven dependencies (`coordinate`, optional `classifier`, optional `scope`)

## Notes

- Plugin loading is designed for build-time registration on mobile.
- Native dependencies are declared here, then resolved by platform adapters.
- Run `wizig plugin sync [project_root]` to generate lockfile and registrants in `.wizig/generated`.
