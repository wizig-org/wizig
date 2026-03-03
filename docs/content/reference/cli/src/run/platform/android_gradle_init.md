# `cli/src/run/platform/android_gradle_init.zig`

_Language: Zig_

Gradle init-script generation for Android run compatibility.

## Why This Exists
Existing app projects may contain legacy host build wiring where
`merge*JniLibFolders` consumes outputs from `buildWizigFfi*` tasks without an
explicit dependency edge. Modern Gradle versions flag this as an error.

## Strategy
`wizig run android` passes a generated init script (`-I`) that injects
dependencies from JNI merge tasks to Wizig FFI build tasks for all
subprojects. This preserves backward compatibility without mutating user
build files.

## Public API

### `ensureInitScript` (fn)

Writes/updates the Gradle init script used by Android run orchestration.

The script path lives under `gradle_home` to keep lifecycle coupled with
Gradle cache cleanup strategy used by `wizig run`.

```zig
pub fn ensureInitScript(
    arena: std.mem.Allocator,
    io: std.Io,
    gradle_home: []const u8,
) ![]const u8 {
```

### `init_script_contents` (const)

Static Gradle init script used to wire legacy task dependencies.

```zig
pub const init_script_contents =
```
