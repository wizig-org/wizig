# CLI Reference

## Top-Level

```sh
wizig <command> [args]
```

Primary commands:

- `create`
- `run`
- `codegen`
- `wizigd`
- `plugin`
- `doctor`

## `wizig create`

```sh
wizig create <name> [destination_dir] [--platforms ios,android,macos] [--sdk-root <path>]
```

Behavior:

1. Resolves SDK/runtime/templates roots.
2. Creates app structure (`lib/`, hosts, `.wizig/`, config files).
3. Runs initial `wizig codegen` from discovered `lib/**/*.zig`.
5. Generates iOS/Android host projects.

Examples:

```sh
wizig create Runa
wizig create Runa /Users/arata/Developer/zig/tests/Runa --sdk-root /Users/arata/Developer/zig/wizig
wizig create Runa /tmp/Runa --platforms ios,android
```

## `wizig run`

```sh
wizig run [project_dir] [--device <id_or_name>] [--debugger <mode>] [--non-interactive] [--once]
```

Behavior:

1. Performs codegen preflight from discovered `lib/**/*.zig` APIs (contract optional).
2. Discovers iOS and Android run targets.
3. Prompts for target selection unless non-interactive.
4. Delegates to platform-specific build/install/launch.
5. Writes run log under `.wizig/logs/run.log`.

Examples:

```sh
wizig run .
wizig run /tmp/Runa --non-interactive --device emulator-5554 --once
wizig run /tmp/Runa --non-interactive --device 3BE718C0-8315-4698-8C04-7F62D2EE71C7 --debugger none --once
```

## `wizig codegen`

```sh
wizig codegen [project_root] [--api <path>] [--force]
```

Contract resolution:

1. `--api <path>`
2. `<project>/wizig.api.zig`
3. `<project>/wizig.api.json`
4. fallback: discovery-only mode from `lib/**/*.zig`

Incremental behavior:

- Uses `.wizig/cache/codegen.manifest.json` fingerprint cache.
- Skips regeneration when inputs are unchanged.
- `--force` bypasses cache and regenerates.

Outputs:

- `.wizig/generated/zig/WizigGeneratedApi.zig`
- `.wizig/generated/swift/WizigGeneratedApi.swift`
- `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt`
- `.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift`
- `.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt`

Examples:

```sh
wizig codegen .
wizig codegen /tmp/Runa --api /tmp/Runa/wizig.api.zig
wizig codegen /tmp/Runa --force
```

## `wizig wizigd`

```sh
wizig wizigd [status] [project_root]
wizig wizigd start [project_root] [--interval-ms <ms>]
wizig wizigd stop [project_root]
```

Behavior:

1. Runs a persistent background codegen loop per project.
2. Reuses the same manifest fingerprinting as `wizig codegen`.
3. Regenerates only when contract/lib input fingerprints change.
4. Stores daemon pid in `.wizig/cache/wizigd.pid`.

Examples:

```sh
wizig wizigd start . --interval-ms 300
wizig wizigd status .
wizig wizigd stop .
```

## `wizig plugin`

```sh
wizig plugin validate <wizig-plugin.json>
wizig plugin sync <project_root>
wizig plugin add <git_or_path>
```

`sync` performs manifest validation, lockfile update, registrant generation, and host managed-section updates.

## `wizig doctor`

```sh
wizig doctor [--sdk-root <path>]
```

Checks:

- Required host tools (Zig/Xcode/Java/Gradle/adb/xcodegen)
- SDK/runtime/templates bundle integrity
- Path marker validity for selected SDK root

## Exit Semantics

- Command exits non-zero on validation/build/codegen failures.
- Diagnostics are emitted to stderr with actionable path/context hints.
