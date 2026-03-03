//! Shared iOS host build phase template for framework-based FFI packaging.
//!
//! ## Goal
//! Emit a stable PBX shell phase entry that builds app-specific Zig FFI as an
//! Apple framework and mirrors it into an `.xcframework` artifact. This avoids
//! raw dylib staging and aligns with App Store-friendly bundle structure.
//!
//! ## Ownership
//! This module only owns static template constants. Project scanning and pbxproj
//! mutation logic live in `ios_host_patch.zig`.

/// Deterministic PBX shell phase display name.
pub const phase_name = "Wizig Build iOS FFI";

/// Stable PBX object id used for idempotent phase replacement.
pub const phase_id = "D0A0A0A0A0A0A0A0A0A0AF01";

/// Build phase reference line inserted into app target `buildPhases`.
pub const phase_ref_line = "\t\t\t\t" ++ phase_id ++ " /* " ++ phase_name ++ " */,\n";

/// Full PBX shell script phase entry.
pub const phase_entry =
    "\t\t" ++ phase_id ++ " /* " ++ phase_name ++ " */ = {\n" ++
    "\t\t\tisa = PBXShellScriptBuildPhase;\n" ++
    "\t\t\tbuildActionMask = 2147483647;\n" ++
    "\t\t\tfiles = (\n" ++
    "\t\t\t);\n" ++
    "\t\t\tinputPaths = (\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/zig/WizigGeneratedFfiRoot.zig\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/runtime/core/src/root.zig\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../lib/WizigGeneratedAppModule.zig\",\n" ++
    "\t\t\t);\n" ++
    "\t\t\tname = \"" ++ phase_name ++ "\";\n" ++
    "\t\t\toutputPaths = (\n" ++
    "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/WizigFFI.framework/WizigFFI\",\n" ++
    "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/WizigFFI.framework/Info.plist\",\n" ++
    "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/WizigFFI.framework/_CodeSignature/CodeResources\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/ios/WizigFFI.xcframework/Info.plist\",\n" ++
    "\t\t\t);\n" ++
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n" ++
    "\t\t\tshellPath = /bin/sh;\n" ++
    "\t\t\tshellScript = \"set -eu\\n" ++
    "APP_ROOT=\\\"${SRCROOT}/..\\\"\\n" ++
    "GENERATED_ROOT=\\\"${APP_ROOT}/.wizig/generated/zig\\\"\\n" ++
    "RUNTIME_ROOT=\\\"${APP_ROOT}/.wizig/runtime\\\"\\n" ++
    "LIB_ROOT=\\\"${APP_ROOT}/lib\\\"\\n" ++
    "GENERATED_IOS_ROOT=\\\"${APP_ROOT}/.wizig/generated/ios\\\"\\n" ++
    "OUT_DIR=\\\"${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}\\\"\\n" ++
    "OUT_FRAMEWORK_DIR=\\\"${OUT_DIR}/WizigFFI.framework\\\"\\n" ++
    "OUT_FRAMEWORK_BIN=\\\"${OUT_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "OUT_FRAMEWORK_INFO=\\\"${OUT_FRAMEWORK_DIR}/Info.plist\\\"\\n" ++
    "TMP_BASE=\\\"${TARGET_TEMP_DIR:-${TEMP_DIR:-/tmp}}\\\"\\n" ++
    "TMP_FRAMEWORK_DIR=\\\"${TMP_BASE}/WizigFFI.framework\\\"\\n" ++
    "TMP_FRAMEWORK_BIN=\\\"${TMP_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "TMP_FRAMEWORK_INFO=\\\"${TMP_FRAMEWORK_DIR}/Info.plist\\\"\\n" ++
    "TMP_XCFRAMEWORK_DIR=\\\"${TMP_BASE}/WizigFFI.xcframework\\\"\\n" ++
    "XCFRAMEWORK_DIR=\\\"${GENERATED_IOS_ROOT}/WizigFFI.xcframework\\\"\\n" ++
    "mkdir -p \\\"${OUT_DIR}\\\" \\\"${GENERATED_IOS_ROOT}\\\"\\n" ++
    "rm -rf \\\"${TMP_FRAMEWORK_DIR}\\\" \\\"${TMP_XCFRAMEWORK_DIR}\\\"\\n" ++
    "mkdir -p \\\"${TMP_FRAMEWORK_DIR}\\\"\\n" ++
    "CACHE_BASE=\\\"${TMP_BASE}\\\"\\n" ++
    "ZIG_LOCAL_CACHE_DIR=\\\"${CACHE_BASE}/wizig-zig-local-cache\\\"\\n" ++
    "ZIG_GLOBAL_CACHE_DIR=\\\"${CACHE_BASE}/wizig-zig-global-cache\\\"\\n" ++
    "mkdir -p \\\"${ZIG_LOCAL_CACHE_DIR}\\\" \\\"${ZIG_GLOBAL_CACHE_DIR}\\\"\\n" ++
    "export ZIG_LOCAL_CACHE_DIR\\n" ++
    "export ZIG_GLOBAL_CACHE_DIR\\n" ++
    "ZIG_OPTIMIZE=\\\"${WIZIG_FFI_OPTIMIZE:-ReleaseFast}\\\"\\n" ++
    "if [ -z \\\"${WIZIG_FFI_OPTIMIZE:-}\\\" ]; then\\n" ++
    "  case \\\"${CONFIGURATION:-}\\\" in\\n" ++
    "    Debug|*Debug*) ZIG_OPTIMIZE=\\\"Debug\\\" ;;\\n" ++
    "  esac\\n" ++
    "fi\\n" ++
    "ARCH_VALUE=\\\"${CURRENT_ARCH:-}\\\"\\n" ++
    "if [ -z \\\"${ARCH_VALUE}\\\" ] || [ \\\"${ARCH_VALUE}\\\" = \\\"undefined_arch\\\" ]; then\\n" ++
    "  ARCH_VALUE=\\\"${NATIVE_ARCH_ACTUAL:-}\\\"\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ARCH_VALUE}\\\" ] || [ \\\"${ARCH_VALUE}\\\" = \\\"undefined_arch\\\" ]; then\\n" ++
    "  set -- ${ARCHS:-}\\n" ++
    "  ARCH_VALUE=\\\"${1:-}\\\"\\n" ++
    "fi\\n" ++
    "if [ \\\"${PLATFORM_NAME}\\\" = \\\"iphonesimulator\\\" ]; then\\n" ++
    "  case \\\"${ARCH_VALUE}\\\" in\\n" ++
    "    arm64) ZIG_TARGET=\\\"aarch64-ios-simulator\\\" ;;\\n" ++
    "    x86_64) ZIG_TARGET=\\\"x86_64-ios-simulator\\\" ;;\\n" ++
    "    *) echo \\\"error: unsupported iOS simulator arch '${ARCH_VALUE}' for Wizig FFI build\\\" >&2; exit 1 ;;\\n" ++
    "  esac\\n" ++
    "elif [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ]; then\\n" ++
    "  ZIG_TARGET=\\\"aarch64-ios\\\"\\n" ++
    "else\\n" ++
    "  echo \\\"error: unsupported Apple platform '${PLATFORM_NAME}' for Wizig FFI build\\\" >&2\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "ZIG_BIN=\\\"${ZIG_BINARY:-}\\\"\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  if command -v zig >/dev/null 2>&1; then\\n" ++
    "    ZIG_BIN=\\\"$(command -v zig)\\\"\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  for candidate in \\\"${HOME}/.zvm/master/zig\\\" \\\"${HOME}/.zvm/bin/zig\\\" \\\"${HOME}/.local/bin/zig\\\" \\\"/opt/homebrew/bin/zig\\\" \\\"/usr/local/bin/zig\\\"; do\\n" ++
    "    if [ -x \\\"${candidate}\\\" ]; then\\n" ++
    "      ZIG_BIN=\\\"${candidate}\\\"\\n" ++
    "      break\\n" ++
    "    fi\\n" ++
    "  done\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  echo \\\"error: zig is not installed or discoverable (PATH/ZIG_BINARY/common locations); required for Wizig iOS FFI build\\\" >&2\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "\\\"${ZIG_BIN}\\\" build-lib -O\\\"${ZIG_OPTIMIZE}\\\" -fno-error-tracing -fno-unwind-tables -fstrip -target \\\"${ZIG_TARGET}\\\" --dep wizig_core --dep wizig_app -Mroot=\\\"${GENERATED_ROOT}/WizigGeneratedFfiRoot.zig\\\" -Mwizig_core=\\\"${RUNTIME_ROOT}/core/src/root.zig\\\" -Mwizig_app=\\\"${LIB_ROOT}/WizigGeneratedAppModule.zig\\\" --name WizigFFI -dynamic -install_name @rpath/WizigFFI.framework/WizigFFI -headerpad_max_install_names --sysroot \\\"${SDKROOT}\\\" -L/usr/lib -F/System/Library/Frameworks -lc -femit-bin=\\\"${TMP_FRAMEWORK_BIN}\\\"\\n" ++
    "FRAMEWORK_BUNDLE_ID=\\\"dev.wizig.WizigFFI.framework\\\"\\n" ++
    "if [ -n \\\"${PRODUCT_BUNDLE_IDENTIFIER:-}\\\" ]; then\\n" ++
    "  FRAMEWORK_BUNDLE_ID=\\\"${PRODUCT_BUNDLE_IDENTIFIER}.wizigffi\\\"\\n" ++
    "fi\\n" ++
    "cat > \\\"${TMP_FRAMEWORK_INFO}\\\" <<EOF\\n" ++
    "<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?>\\n" ++
    "<!DOCTYPE plist PUBLIC \\\"-//Apple//DTD PLIST 1.0//EN\\\" \\\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\\">\\n" ++
    "<plist version=\\\"1.0\\\">\\n" ++
    "<dict>\\n" ++
    "    <key>CFBundleDevelopmentRegion</key>\\n" ++
    "    <string>en</string>\\n" ++
    "    <key>CFBundleExecutable</key>\\n" ++
    "    <string>WizigFFI</string>\\n" ++
    "    <key>CFBundleIdentifier</key>\\n" ++
    "    <string>${FRAMEWORK_BUNDLE_ID}</string>\\n" ++
    "    <key>CFBundleInfoDictionaryVersion</key>\\n" ++
    "    <string>6.0</string>\\n" ++
    "    <key>CFBundleName</key>\\n" ++
    "    <string>WizigFFI</string>\\n" ++
    "    <key>CFBundlePackageType</key>\\n" ++
    "    <string>FMWK</string>\\n" ++
    "    <key>CFBundleShortVersionString</key>\\n" ++
    "    <string>1.0</string>\\n" ++
    "    <key>CFBundleVersion</key>\\n" ++
    "    <string>1</string>\\n" ++
    "</dict>\\n" ++
    "</plist>\\n" ++
    "EOF\\n" ++
    "mkdir -p \\\"${OUT_FRAMEWORK_DIR}\\\"\\n" ++
    "cp -f \\\"${TMP_FRAMEWORK_BIN}\\\" \\\"${OUT_FRAMEWORK_BIN}\\\"\\n" ++
    "cp -f \\\"${TMP_FRAMEWORK_INFO}\\\" \\\"${OUT_FRAMEWORK_INFO}\\\"\\n" ++
    "if [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ] && [ \\\"${CODE_SIGNING_ALLOWED:-NO}\\\" = \\\"YES\\\" ]; then\\n" ++
    "  SIGNED=0\\n" ++
    "  for SIGN_IDENTITY in \\\"${EXPANDED_CODE_SIGN_IDENTITY:-}\\\" \\\"${EXPANDED_CODE_SIGN_IDENTITY_NAME:-}\\\" \\\"${CODE_SIGN_IDENTITY:-}\\\"; do\\n" ++
    "    if [ -z \\\"${SIGN_IDENTITY}\\\" ]; then\\n" ++
    "      continue\\n" ++
    "    fi\\n" ++
    "    if /usr/bin/codesign --force --sign \\\"${SIGN_IDENTITY}\\\" --timestamp=none --generate-entitlement-der \\\"${OUT_FRAMEWORK_DIR}\\\"; then\\n" ++
    "      SIGNED=1\\n" ++
    "      break\\n" ++
    "    fi\\n" ++
    "  done\\n" ++
    "  if [ \\\"${SIGNED}\\\" != \\\"1\\\" ]; then\\n" ++
    "    echo \\\"error: failed to sign WizigFFI.framework (tried EXPANDED_CODE_SIGN_IDENTITY, EXPANDED_CODE_SIGN_IDENTITY_NAME, CODE_SIGN_IDENTITY)\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
    "xcodebuild -create-xcframework -framework \\\"${TMP_FRAMEWORK_DIR}\\\" -output \\\"${TMP_XCFRAMEWORK_DIR}\\\" >/dev/null\\n" ++
    "rm -rf \\\"${XCFRAMEWORK_DIR}\\\"\\n" ++
    "mkdir -p \\\"${XCFRAMEWORK_DIR}\\\"\\n" ++
    "cp -R \\\"${TMP_XCFRAMEWORK_DIR}/.\\\" \\\"${XCFRAMEWORK_DIR}\\\"\\n\";\n" ++
    "\t\t};\n";
