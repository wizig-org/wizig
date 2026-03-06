//! iOS Mach-O __TEXT segment page alignment fixup.
//!
//! Zig's self-hosted Mach-O linker may produce __TEXT segments whose vmsize
//! and filesize are not aligned to 16 KB (16384 bytes).  iOS devices with
//! arm64 require 16 KB page-aligned code pages for AMFI kernel code-signature
//! validation.  This fixup rounds both values up to the next 16 KB boundary.

/// Shell function that patches a Mach-O binary's __TEXT segment to 16 KB
/// page-size alignment.  Called after each `build_ffi_slice` invocation in
/// the Xcode build phase.
pub const fix_macho_text_page_alignment =
    "fix_macho_text_page_alignment() {\\n" ++
    "  python3 -c '\\n" ++
    "import struct,sys\\n" ++
    "p=sys.argv[1]\\n" ++
    "d=bytearray(open(p,\\\"rb\\\").read())\\n" ++
    "if struct.unpack_from(\\\"<I\\\",d,0)[0]!=0xFEEDFACF: sys.exit(0)\\n" ++
    "o=32\\n" ++
    "for _ in range(struct.unpack_from(\\\"<I\\\",d,16)[0]):\\n" ++
    "    c,s=struct.unpack_from(\\\"<II\\\",d,o)\\n" ++
    "    if c==0x19 and d[o+8:o+14]==b\\\"__TEXT\\\" and d[o+14]==0:\\n" ++
    "        m=0\\n" ++
    "        for f in(32,48):\\n" ++
    "            v=struct.unpack_from(\\\"<Q\\\",d,o+f)[0]\\n" ++
    "            a=(v+16383)&~16383\\n" ++
    "            if v!=a:\\n" ++
    "                struct.pack_into(\\\"<Q\\\",d,o+f,a)\\n" ++
    "                m=1\\n" ++
    "        if m: open(p,\\\"wb\\\").write(d)\\n" ++
    "        break\\n" ++
    "    o+=s\\n" ++
    "' \\\"$1\\\"\\n" ++
    "}\\n";
