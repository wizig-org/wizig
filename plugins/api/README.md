# Ziggy Plugin API

`ziggy-plugin.json` declares plugin identity, contract version, and native dependencies.

## Fields

- `id`: reverse-domain plugin identifier
- `version`: plugin implementation version
- `api_version`: Ziggy plugin API compatibility version
- `capabilities`: permissions requested by plugin
- `ios_spm`: Swift Package Manager dependencies (`url`, `requirement`, `product`)
- `android_maven`: Gradle/Maven dependencies (`coordinate`, optional `classifier`, optional `scope`)

## Notes

- Plugin loading is designed for build-time registration on mobile.
- Native dependencies are declared here, then resolved by platform adapters.
- Run `ziggy plugin sync [project_root]` to generate lockfile and registrants in `.ziggy/generated`.
