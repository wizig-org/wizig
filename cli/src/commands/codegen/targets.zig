//! Code generation target definitions.
/// Enumerates known host/language codegen outputs.
pub const CodegenTarget = enum {
    zig,
    swift,
    kotlin,
    typescript,
};

/// Reports whether a target is implemented in the current release.
pub fn supportedNow(target: CodegenTarget) bool {
    return switch (target) {
        .zig, .swift, .kotlin => true,
        .typescript => false,
    };
}
