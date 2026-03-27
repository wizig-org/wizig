# Wizig Runtime Sources

This directory is bundled with Wizig and copied into generated apps under `.wizig/runtime`.
It contains the Zig runtime sources used to build platform runtime artifacts from app-local state.

The `core/` and `ffi/` entries are symlinks to the canonical source directories at the
repository root. The build system follows these symlinks when installing, so generated
apps receive real file copies with no symlink dependency.
