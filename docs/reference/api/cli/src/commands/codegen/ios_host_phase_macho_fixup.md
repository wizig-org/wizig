# `cli/src/commands/codegen/ios_host_phase_macho_fixup.zig`

_Language: Zig_

iOS Mach-O __TEXT segment page alignment fixup.

Zig's self-hosted Mach-O linker may produce __TEXT segments whose vmsize
and filesize are not aligned to 16 KB (16384 bytes).  iOS devices with
arm64 require 16 KB page-aligned code pages for AMFI kernel code-signature
validation.  This fixup rounds both values up to the next 16 KB boundary.

## Public API

### `fix_macho_text_page_alignment` (const)

Shell function that patches a Mach-O binary's __TEXT segment to 16 KB
page-size alignment.  Called after each `build_ffi_slice` invocation in
the Xcode build phase.

```zig
pub const fix_macho_text_page_alignment =
```
