# `cli/src/commands/codegen/ios_host_phase_entry.zig`

_Language: Zig_

Shared iOS host build phase template for framework-based FFI packaging.

## Goal
Emit a stable PBX shell phase entry that builds app-specific Zig FFI as an
Apple framework and mirrors it into an `.xcframework` artifact. This avoids
raw dylib staging and aligns with App Store-friendly bundle structure.

## Ownership
This module only owns static template constants. Project scanning and pbxproj
mutation logic live in `ios_host_patch.zig`.

## Public API

### `phase_name` (const)

Deterministic PBX shell phase display name.

```zig
pub const phase_name = "Wizig Build iOS FFI";
```

### `phase_id` (const)

Stable PBX object id used for idempotent phase replacement.

```zig
pub const phase_id = "D0A0A0A0A0A0A0A0A0A0AF01";
```

### `phase_ref_line` (const)

Build phase reference line inserted into app target `buildPhases`.

```zig
pub const phase_ref_line = "\t\t\t\t" ++ phase_id ++ " /* " ++ phase_name ++ " */,\n";
```

### `phase_entry` (const)

Full PBX shell script phase entry.

```zig
pub const phase_entry =
```
