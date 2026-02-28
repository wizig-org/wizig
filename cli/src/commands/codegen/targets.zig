pub const CodegenTarget = enum {
    zig,
    swift,
    kotlin,
    typescript,
};

pub fn supportedNow(target: CodegenTarget) bool {
    return switch (target) {
        .zig, .swift, .kotlin => true,
        .typescript => false,
    };
}
