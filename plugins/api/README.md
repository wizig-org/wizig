# Ziggy Plugin API

`ziggy-plugin.toml` declares plugin identity, contract version, and native dependencies.

## Fields

- `id`: reverse-domain plugin identifier
- `version`: plugin implementation version
- `api_version`: Ziggy plugin API compatibility version
- `capabilities`: permissions requested by plugin
- `ios_spm`: optional Swift Package Manager dependencies
- `android_maven`: optional Gradle/Maven dependencies

## Notes

- Plugin loading is designed for build-time registration on mobile.
- Native dependencies are declared here, then resolved by platform adapters.
- Run `ziggy plugin sync <plugin_root>` to generate lockfile and registrants in default platform paths.
