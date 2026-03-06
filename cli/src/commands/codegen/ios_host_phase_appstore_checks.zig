//! Shared iOS App Store safety checks injected into Xcode build-phase scripts.
//!
//! These checks fail the build when private frameworks or denylisted private
//! symbols are imported by the generated device framework binary.
//!
//! Note: once the device framework has been codesigned, `xcrun nm -u -j` can
//! reject Zig-produced Mach-O binaries as malformed even though the binary is
//! valid and launchable. `xcrun dyld_info -imports` remains reliable after
//! signing, so the generated shell snippet prefers that tool and falls back to
//! `nm` for older toolchains.

/// Shell snippet that validates private framework/symbol linkage.
pub const private_api_guards =
    "if [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ]; then\\n" ++
    "  LINKS=\\\"$(xcrun otool -L \\\"${OUT_FRAMEWORK_BIN}\\\" 2>/dev/null || true)\\\"\\n" ++
    "  if [ -z \\\"${LINKS}\\\" ]; then\\n" ++
    "    echo \\\"error: failed to inspect linked dylibs for App Store safety checks\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "  PRIVATE_LINKS=\\\"$(printf '%s\\\\n' \\\"${LINKS}\\\" | awk 'NR>1 {print $1}' | grep -E '(^|/)PrivateFrameworks/[^[:space:]]+\\\\.framework/' || true)\\\"\\n" ++
    "  if [ -n \\\"${PRIVATE_LINKS}\\\" ]; then\\n" ++
    "    echo \\\"error: private framework linkage detected in WizigFFI\\\" >&2\\n" ++
    "    printf '%s\\\\n' \\\"${PRIVATE_LINKS}\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "  PRIVATE_API_SYMBOL_DENYLIST_REGEX=\\\"${WIZIG_IOS_PRIVATE_SYMBOL_DENYLIST_REGEX:-^(_MGCopyAnswer|_MGGetBoolAnswer|_OBJC_(CLASS|METACLASS)_[$]_LSApplicationWorkspace|_OBJC_(CLASS|METACLASS)_[$]_LSApplicationProxy)$}\\\"\\n" ++
    "  if UNDEF=\\\"$(xcrun dyld_info -imports \\\"${OUT_FRAMEWORK_BIN}\\\" 2>/dev/null | awk '/^[[:space:]]*_/ { print $1 }')\\\"; then\\n" ++
    "    :\\n" ++
    "  elif UNDEF=\\\"$(xcrun nm -u -j \\\"${OUT_FRAMEWORK_BIN}\\\" 2>/dev/null)\\\"; then\\n" ++
    "    :\\n" ++
    "  else\\n" ++
    "    echo \\\"error: failed to inspect imported symbols for App Store safety checks\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "  PRIVATE_SYMBOLS=\\\"$(printf '%s\\\\n' \\\"${UNDEF}\\\" | grep -E \\\"${PRIVATE_API_SYMBOL_DENYLIST_REGEX}\\\" || true)\\\"\\n" ++
    "  if [ -n \\\"${PRIVATE_SYMBOLS}\\\" ]; then\\n" ++
    "    echo \\\"error: imported private iOS symbols detected in WizigFFI\\\" >&2\\n" ++
    "    printf '%s\\\\n' \\\"${PRIVATE_SYMBOLS}\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "fi\\n";
