//! Shared CLI-level error tags.
/// Canonical error set used across command handlers.
pub const CliError = error{
    InvalidArguments,
    CommandFailed,
    ValidationFailed,
    NotFound,
};
