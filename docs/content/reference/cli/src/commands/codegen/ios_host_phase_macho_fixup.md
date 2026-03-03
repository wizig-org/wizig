# `cli/src/commands/codegen/ios_host_phase_macho_fixup.zig`

_Language: Zig_

Mach-O __TEXT segment page-alignment fixup for zig-produced iOS binaries.

## Problem
The Zig linker may emit Mach-O dynamic libraries whose `__TEXT` segment
`vmsize` and `filesize` fields are not rounded up to the 16 KB page boundary
required by arm64 iOS devices.  The macOS `codesign` tool and simulator
runtimes tolerate this, but real-device AMFI (Apple Mobile File Integrity)
kernel validation rejects the resulting code signature as structurally
invalid because page-hash boundaries do not align with segment limits.

## Approach
After each `zig build-lib` invocation we run a small `python3` one-liner
that reads the Mach-O header, locates the `__TEXT` LC_SEGMENT_64 load
command, and rounds `vmsize` / `filesize` up to the next 16 KB multiple
when they are not already aligned.  The patch is a no-op for binaries that
are already correctly aligned, so it is safe to apply unconditionally.

## Ownership
This module only owns the static shell snippet constant.  It is spliced
into the build-phase template by `ios_host_phase_entry.zig`.

## Escaping
The string is embedded inside a pbxproj `shellScript = "...";` value.
All double-quote characters that are part of the shell script content must
be escaped as `\"` in the pbxproj string, which means `\\\"` in the Zig
string literal.  Single quotes and other characters pass through unchanged.

## Public API

### `fix_macho_text_page_alignment` (const)

Shell function that page-aligns `__TEXT` vmsize/filesize of a 64-bit
Mach-O binary in-place.  Call as `fix_macho_text_page_alignment <path>`.

The function is intentionally a no-op (exit 0) when:
- The file is not a 64-bit Mach-O (wrong magic).
- The `__TEXT` segment is already page-aligned.
- `python3` is not available (should never happen on macOS).

```zig
pub const fix_macho_text_page_alignment =
```
