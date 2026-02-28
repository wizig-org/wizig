# CLI Reference

## Top-Level

```sh
ziggy <command> [args]
```

Commands:

- `create`
- `run`
- `codegen`
- `plugin`
- `doctor`

## `ziggy create`

```sh
ziggy create <name> [destination_dir] [--platforms ios,android,macos] [--sdk-root <path>]
```

Creates a full app scaffold including `.ziggy/` app-local runtime assets.

## `ziggy run`

```sh
ziggy run [project_dir] [--device <id_or_name>] [--debugger <mode>] [--non-interactive] [--once]
```

Behavior:

- Runs codegen preflight automatically
- Discovers host projects under `ios/` and `android/`
- Shows/selects available devices across platforms

## `ziggy codegen`

```sh
ziggy codegen [project_root] [--api <path>]
```

Generates typed bindings into:

- `.ziggy/generated/zig`
- `.ziggy/generated/swift`
- `.ziggy/generated/kotlin`

## `ziggy plugin`

```sh
ziggy plugin validate <ziggy-plugin.json>
ziggy plugin sync <project_root>
ziggy plugin add <git_or_path>
```

## `ziggy doctor`

```sh
ziggy doctor [--sdk-root <path>]
```

Checks host toolchain and bundled SDK/runtime/templates integrity.
