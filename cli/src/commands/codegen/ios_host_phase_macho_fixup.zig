//! Mach-O __TEXT segment page-alignment fixup for zig-produced iOS binaries.
//!
//! ## Problem
//! The Zig linker may emit Mach-O dynamic libraries whose `__TEXT` segment
//! `vmsize` and `filesize` fields are not rounded up to the 16 KB page boundary
//! required by arm64 iOS devices.  The macOS `codesign` tool and simulator
//! runtimes tolerate this, but real-device AMFI (Apple Mobile File Integrity)
//! kernel validation rejects the resulting code signature as structurally
//! invalid because page-hash boundaries do not align with segment limits.
//!
//! ## Approach
//! After each `zig build-lib` invocation we run a small `python3` one-liner
//! that reads the Mach-O header, locates the `__TEXT` LC_SEGMENT_64 load
//! command, and rounds `vmsize` / `filesize` up to the next 16 KB multiple
//! when they are not already aligned.  The patch is a no-op for binaries that
//! are already correctly aligned, so it is safe to apply unconditionally.
//!
//! ## Ownership
//! This module only owns the static shell snippet constant.  It is spliced
//! into the build-phase template by `ios_host_phase_entry.zig`.
//!
//! ## Escaping
//! The string is embedded inside a pbxproj `shellScript = "...";` value.
//! All double-quote characters that are part of the shell script content must
//! be escaped as `\"` in the pbxproj string, which means `\\\"` in the Zig
//! string literal.  Single quotes and other characters pass through unchanged.

/// Shell function that page-aligns `__TEXT` vmsize/filesize of a 64-bit
/// Mach-O binary in-place.  Call as `fix_macho_text_page_alignment <path>`.
///
/// The function is intentionally a no-op (exit 0) when:
///   - The file is not a 64-bit Mach-O (wrong magic).
///   - The `__TEXT` segment is already page-aligned.
///   - `python3` is not available (should never happen on macOS).
pub const fix_macho_text_page_alignment =
    "fix_macho_text_page_alignment() {\\n" ++
    "  python3 -c \\\"\\n" ++
    "import struct, sys\\n" ++
    "p=sys.argv[1]\\n" ++
    "d=bytearray(open(p,'rb').read())\\n" ++
    "if struct.unpack_from('<I',d,0)[0]!=0xFEEDFACF: sys.exit(0)\\n" ++
    "o=32\\n" ++
    "for _ in range(struct.unpack_from('<I',d,16)[0]):\\n" ++
    "  c,s=struct.unpack_from('<II',d,o)\\n" ++
    "  if c==0x19 and d[o+8:o+24].split(b'\\\\x00')[0]==b'__TEXT':\\n" ++
    "    m=0\\n" ++
    "    for f in(32,48):\\n" ++
    "      v=struct.unpack_from('<Q',d,o+f)[0]; a=(v+16383)&~16383\\n" ++
    "      if v!=a: struct.pack_into('<Q',d,o+f,a); m=1\\n" ++
    "    if m: open(p,'wb').write(d)\\n" ++
    "    break\\n" ++
    "  o+=s\\n" ++
    "\\\" \\\"$1\\\"\\n" ++
    "}\\n";
