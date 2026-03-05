# CLI Reference

## Top-Level Usage

```sh
wizig <command> [args]
```

Commands: `create`, `run`, `codegen`, `build`, `plugin`, `doctor`, `version`, `self-update`, `uninstall`

---

## `wizig create`

Scaffold a new Wizig project.

```sh
wizig create <name> [destination_dir] [--platforms ios,android,macos] [--sdk-root <path>]
```

**Behavior:**

1. Resolves SDK/runtime/templates roots
2. Creates app structure (`lib/`, hosts, `.wizig/`, config files)
3. Runs initial `wizig codegen` from discovered `lib/**/*.zig`
4. Generates iOS/Android host projects

**Examples:**

```sh
wizig create Runa
wizig create Runa /tmp/Runa --sdk-root /path/to/wizig
wizig create Runa /tmp/Runa --platforms ios,android
```

---

## `wizig run`

Build and run on device or simulator.

```sh
wizig run [project_dir] [--device <id_or_name>] [--debugger <mode>] [--non-interactive] [--once] [--monitor-timeout <seconds>] [--allow-toolchain-drift]
```

**Behavior:**

1. Performs codegen preflight from discovered `lib/**/*.zig` APIs
2. Discovers iOS and Android run targets
3. Prompts for target selection unless `--non-interactive`
4. Delegates to platform-specific build/install/launch
5. Applies monitor watchdog rules (timeout + app-liveness stop)
6. Writes run log under `.wizig/logs/run.log`
7. Enforces `.wizig/toolchain.lock.json` minimum versions unless `--allow-toolchain-drift`

**Examples:**

```sh
wizig run .
wizig run /tmp/Runa --non-interactive --device emulator-5554 --once
wizig run /tmp/Runa --non-interactive --device 3BE718C0-... --debugger none --once
```

---

## `wizig codegen`

Generate typed bridge bindings.

```sh
wizig codegen [project_root] [--api <path>] [--watch] [--watch-interval-ms <ms>] [--allow-toolchain-drift]
```

**Contract resolution:**

| Priority | Source |
|----------|--------|
| 1 | `--api <path>` |
| 2 | `<project>/wizig.api.zig` |
| 3 | `<project>/wizig.api.json` |
| 4 | Discovery-only from `lib/**/*.zig` |

**Outputs:**

- `.wizig/generated/zig/WizigGeneratedApi.zig`
- `.wizig/generated/swift/WizigGeneratedApi.swift`
- `.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt`
- `.wizig/sdk/ios/Sources/Wizig/WizigGeneratedApi.swift`
- `.wizig/sdk/android/src/main/kotlin/dev/wizig/WizigGeneratedApi.kt`

**Watch mode:**

- `--watch` polls for changes and reruns codegen automatically
- `--watch-interval-ms` controls polling interval (default: `500`)
- Lock enforcement defaults on; use `--allow-toolchain-drift` to bypass

**Examples:**

```sh
wizig codegen .
wizig codegen /tmp/Runa --api /tmp/Runa/wizig.api.zig
wizig codegen /tmp/Runa --watch
```

---

## `wizig build`

Build for release or multi-ABI Android targets.

```sh
wizig build [project_dir] [options]
```

---

## `wizig plugin`

Manage project plugins.

```sh
wizig plugin validate <wizig-plugin.json>
wizig plugin sync <project_root>
wizig plugin add <git_or_path>
```

**`sync`** performs: manifest validation, lockfile update, registrant generation, and host managed-section updates.

---

## `wizig doctor`

Validate development environment.

```sh
wizig doctor [--sdk-root <path>] [--strict|--no-strict]
```

**Checks:**

- Tool policy from `toolchains.toml` (required/optional + minimum versions)
- SDK/runtime/templates bundle integrity
- Path marker validity for selected SDK root
- Strict enforcement mode via `--strict`

See also: [Toolchain Governance](guide/toolchain-governance.md), [Toolchain Manifest Reference](reference/toolchain-manifest.md)

---

## `wizig version`

Print the installed wizig version.

```sh
wizig version
wizig --version
```

---

## `wizig self-update`

Check for and install the latest wizig release from GitHub.

```sh
wizig self-update
```

Compares the current version against the latest GitHub Release. If a newer version is available, downloads and installs it in place.

Not available for development builds (`dev` version).

---

## `wizig uninstall`

Remove the wizig installation.

```sh
wizig uninstall [--yes]
```

**Flags:**

- `--yes` / `-y` — Skip confirmation prompt

Refuses to uninstall from system or package-managed directories (e.g., Homebrew prefix). For those installs, use the package manager to uninstall.

---

## Exit Semantics

- Commands exit non-zero on validation/build/codegen failures.
- Diagnostics are emitted to stderr with actionable path/context hints.
