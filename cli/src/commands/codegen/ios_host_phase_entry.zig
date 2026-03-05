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
const ios_phase_appstore_checks = @import("ios_host_phase_appstore_checks.zig");
const ios_phase_toolchain = @import("ios_host_phase_toolchain.zig");

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
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/ios/wizig.h\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/ios/WizigGeneratedApi.h\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/ios/WizigFFI.h\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/ios/module.modulemap\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/runtime/core/src/root.zig\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../lib/WizigGeneratedAppModule.zig\",\n" ++
    "\t\t\t);\n" ++
    "\t\t\tname = \"" ++ phase_name ++ "\";\n" ++
    "\t\t\toutputPaths = (\n" ++
    "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/WizigFFI.framework/WizigFFI\",\n" ++
    "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/WizigFFI.framework/Info.plist\",\n" ++
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
    "GENERATED_IOS_CANONICAL_HEADER=\\\"${GENERATED_IOS_ROOT}/wizig.h\\\"\\n" ++
    "GENERATED_IOS_API_HEADER=\\\"${GENERATED_IOS_ROOT}/WizigGeneratedApi.h\\\"\\n" ++
    "GENERATED_IOS_FRAMEWORK_HEADER=\\\"${GENERATED_IOS_ROOT}/WizigFFI.h\\\"\\n" ++
    "GENERATED_IOS_MODULEMAP=\\\"${GENERATED_IOS_ROOT}/module.modulemap\\\"\\n" ++
    "OUT_DIR=\\\"${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}\\\"\\n" ++
    "OUT_FRAMEWORK_DIR=\\\"${OUT_DIR}/WizigFFI.framework\\\"\\n" ++
    "OUT_FRAMEWORK_BIN=\\\"${OUT_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "OUT_FRAMEWORK_INFO=\\\"${OUT_FRAMEWORK_DIR}/Info.plist\\\"\\n" ++
    "TMP_BASE=\\\"${TARGET_TEMP_DIR:-${TEMP_DIR:-/tmp}}\\\"\\n" ++
    "TMP_FRAMEWORK_INFO=\\\"${TMP_BASE}/WizigFFI-Info.plist\\\"\\n" ++
    "TMP_DEVICE_FRAMEWORK_DIR=\\\"${TMP_BASE}/wizig-ios-device/WizigFFI.framework\\\"\\n" ++
    "TMP_DEVICE_FRAMEWORK_BIN=\\\"${TMP_DEVICE_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "TMP_SIM_ARM64_FRAMEWORK_DIR=\\\"${TMP_BASE}/wizig-ios-sim-arm64/WizigFFI.framework\\\"\\n" ++
    "TMP_SIM_ARM64_FRAMEWORK_BIN=\\\"${TMP_SIM_ARM64_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "TMP_SIM_X64_FRAMEWORK_DIR=\\\"${TMP_BASE}/wizig-ios-sim-x86_64/WizigFFI.framework\\\"\\n" ++
    "TMP_SIM_X64_FRAMEWORK_BIN=\\\"${TMP_SIM_X64_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "TMP_SIM_UNIVERSAL_FRAMEWORK_DIR=\\\"${TMP_BASE}/wizig-ios-sim-universal/WizigFFI.framework\\\"\\n" ++
    "TMP_SIM_UNIVERSAL_FRAMEWORK_BIN=\\\"${TMP_SIM_UNIVERSAL_FRAMEWORK_DIR}/WizigFFI\\\"\\n" ++
    "TMP_XCFRAMEWORK_DIR=\\\"${TMP_BASE}/WizigFFI.xcframework\\\"\\n" ++
    "XCFRAMEWORK_DIR=\\\"${GENERATED_IOS_ROOT}/WizigFFI.xcframework\\\"\\n" ++
    "mkdir -p \\\"${OUT_DIR}\\\" \\\"${GENERATED_IOS_ROOT}\\\"\\n" ++
    "rm -rf \\\"$(dirname \\\"${TMP_DEVICE_FRAMEWORK_DIR}\\\")\\\" \\\"$(dirname \\\"${TMP_SIM_ARM64_FRAMEWORK_DIR}\\\")\\\" \\\"$(dirname \\\"${TMP_SIM_X64_FRAMEWORK_DIR}\\\")\\\" \\\"$(dirname \\\"${TMP_SIM_UNIVERSAL_FRAMEWORK_DIR}\\\")\\\" \\\"${TMP_XCFRAMEWORK_DIR}\\\"\\n" ++
    "for required_file in \\\"${GENERATED_IOS_CANONICAL_HEADER}\\\" \\\"${GENERATED_IOS_API_HEADER}\\\" \\\"${GENERATED_IOS_FRAMEWORK_HEADER}\\\" \\\"${GENERATED_IOS_MODULEMAP}\\\"; do\\n" ++
    "  if [ ! -f \\\"${required_file}\\\" ]; then\\n" ++
    "    echo \\\"error: missing generated iOS framework interop artifact: ${required_file}\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "done\\n" ++
    "CACHE_BASE=\\\"${TMP_BASE}\\\"\\n" ++
    "ZIG_LOCAL_CACHE_DIR=\\\"${CACHE_BASE}/wizig-zig-local-cache\\\"\\n" ++
    "ZIG_GLOBAL_CACHE_DIR=\\\"${CACHE_BASE}/wizig-zig-global-cache\\\"\\n" ++
    "mkdir -p \\\"${ZIG_LOCAL_CACHE_DIR}\\\" \\\"${ZIG_GLOBAL_CACHE_DIR}\\\"\\n" ++
    "export ZIG_LOCAL_CACHE_DIR\\n" ++
    "export ZIG_GLOBAL_CACHE_DIR\\n" ++
    "ZIG_OPTIMIZE=\\\"ReleaseFast\\\"\\n" ++
    "case \\\"${CONFIGURATION:-}\\\" in\\n" ++
    "  Debug|*Debug*) ZIG_OPTIMIZE=\\\"Debug\\\" ;;\\n" ++
    "esac\\n" ++
    "if [ \\\"${WIZIG_FFI_ALLOW_OPTIMIZE_OVERRIDE:-0}\\\" = \\\"1\\\" ] && [ -n \\\"${WIZIG_FFI_OPTIMIZE:-}\\\" ]; then\\n" ++
    "  ZIG_OPTIMIZE=\\\"${WIZIG_FFI_OPTIMIZE}\\\"\\n" ++
    "fi\\n" ++
    "ARCH_VALUE=\\\"${CURRENT_ARCH:-}\\\"\\n" ++
    "if [ -z \\\"${ARCH_VALUE}\\\" ] || [ \\\"${ARCH_VALUE}\\\" = \\\"undefined_arch\\\" ]; then\\n" ++
    "  ARCH_VALUE=\\\"${NATIVE_ARCH_ACTUAL:-}\\\"\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ARCH_VALUE}\\\" ] || [ \\\"${ARCH_VALUE}\\\" = \\\"undefined_arch\\\" ]; then\\n" ++
    "  set -- ${ARCHS:-}\\n" ++
    "  ARCH_VALUE=\\\"${1:-}\\\"\\n" ++
    "fi\\n" ++
    ios_phase_toolchain.resolve_zig ++
    "IOS_SDKROOT=\\\"$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)\\\"\\n" ++
    "SIM_SDKROOT=\\\"$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)\\\"\\n" ++
    "if [ -z \\\"${IOS_SDKROOT}\\\" ] && [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ]; then IOS_SDKROOT=\\\"${SDKROOT}\\\"; fi\\n" ++
    "if [ -z \\\"${SIM_SDKROOT}\\\" ] && [ \\\"${PLATFORM_NAME}\\\" = \\\"iphonesimulator\\\" ]; then SIM_SDKROOT=\\\"${SDKROOT}\\\"; fi\\n" ++
    "if [ -z \\\"${IOS_SDKROOT}\\\" ] || [ -z \\\"${SIM_SDKROOT}\\\" ]; then\\n" ++
    "  echo \\\"error: failed to resolve iphoneos/iphonesimulator SDK paths for Wizig FFI build\\\" >&2\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "build_ffi_slice() {\\n" ++
    "  TARGET_NAME=\\\"$1\\\"\\n" ++
    "  SYSROOT_PATH=\\\"$2\\\"\\n" ++
    "  OUTPUT_BIN=\\\"$3\\\"\\n" ++
    "  mkdir -p \\\"$(dirname \\\"${OUTPUT_BIN}\\\")\\\"\\n" ++
    "  \\\"${ZIG_BIN}\\\" build-lib -dynamic -O\\\"${ZIG_OPTIMIZE}\\\" -fno-error-tracing -fno-unwind-tables -fstrip -target \\\"${TARGET_NAME}\\\" --dep wizig_core --dep wizig_app -Mroot=\\\"${GENERATED_ROOT}/WizigGeneratedFfiRoot.zig\\\" -Mwizig_core=\\\"${RUNTIME_ROOT}/core/src/root.zig\\\" -Mwizig_app=\\\"${LIB_ROOT}/WizigGeneratedAppModule.zig\\\" --name WizigFFI --sysroot \\\"${SYSROOT_PATH}\\\" -L/usr/lib -F/System/Library/Frameworks -lc -femit-bin=\\\"${OUTPUT_BIN}\\\"\\n" ++
    "}\\n" ++
    "build_ffi_slice \\\"aarch64-ios\\\" \\\"${IOS_SDKROOT}\\\" \\\"${TMP_DEVICE_FRAMEWORK_BIN}\\\"\\n" ++
    "build_ffi_slice \\\"aarch64-ios-simulator\\\" \\\"${SIM_SDKROOT}\\\" \\\"${TMP_SIM_ARM64_FRAMEWORK_BIN}\\\"\\n" ++
    "HAS_SIM_X64=0\\n" ++
    "if build_ffi_slice \\\"x86_64-ios-simulator\\\" \\\"${SIM_SDKROOT}\\\" \\\"${TMP_SIM_X64_FRAMEWORK_BIN}\\\"; then\\n" ++
    "  HAS_SIM_X64=1\\n" ++
    "else\\n" ++
    "  echo \\\"warning: failed to build x86_64-ios-simulator Wizig FFI slice; continuing with arm64 simulator slice only\\\" >&2\\n" ++
    "fi\\n" ++
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
    "prepare_framework_metadata() {\\n" ++
    "  FRAMEWORK_DIR=\\\"$1\\\"\\n" ++
    "  mkdir -p \\\"${FRAMEWORK_DIR}/Headers\\\" \\\"${FRAMEWORK_DIR}/Modules\\\"\\n" ++
    "  cp -f \\\"${TMP_FRAMEWORK_INFO}\\\" \\\"${FRAMEWORK_DIR}/Info.plist\\\"\\n" ++
    "  cp -f \\\"${GENERATED_IOS_CANONICAL_HEADER}\\\" \\\"${FRAMEWORK_DIR}/Headers/wizig.h\\\"\\n" ++
    "  cp -f \\\"${GENERATED_IOS_API_HEADER}\\\" \\\"${FRAMEWORK_DIR}/Headers/WizigGeneratedApi.h\\\"\\n" ++
    "  cp -f \\\"${GENERATED_IOS_FRAMEWORK_HEADER}\\\" \\\"${FRAMEWORK_DIR}/Headers/WizigFFI.h\\\"\\n" ++
    "  cp -f \\\"${GENERATED_IOS_MODULEMAP}\\\" \\\"${FRAMEWORK_DIR}/Modules/module.modulemap\\\"\\n" ++
    "}\\n" ++
    "prepare_framework_metadata \\\"${TMP_DEVICE_FRAMEWORK_DIR}\\\"\\n" ++
    "prepare_framework_metadata \\\"${TMP_SIM_ARM64_FRAMEWORK_DIR}\\\"\\n" ++
    "if [ \\\"${HAS_SIM_X64}\\\" = \\\"1\\\" ]; then\\n" ++
    "  prepare_framework_metadata \\\"${TMP_SIM_X64_FRAMEWORK_DIR}\\\"\\n" ++
    "fi\\n" ++
    "ACTIVE_FRAMEWORK_BIN=\\\"\\\"\\n" ++
    "if [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ]; then\\n" ++
    "  ACTIVE_FRAMEWORK_BIN=\\\"${TMP_DEVICE_FRAMEWORK_BIN}\\\"\\n" ++
    "elif [ \\\"${PLATFORM_NAME}\\\" = \\\"iphonesimulator\\\" ]; then\\n" ++
    "  case \\\"${ARCH_VALUE}\\\" in\\n" ++
    "    arm64) ACTIVE_FRAMEWORK_BIN=\\\"${TMP_SIM_ARM64_FRAMEWORK_BIN}\\\" ;;\\n" ++
    "    x86_64)\\n" ++
    "      if [ \\\"${HAS_SIM_X64}\\\" != \\\"1\\\" ]; then\\n" ++
    "        echo \\\"error: x86_64 simulator slice required for active build but not available\\\" >&2\\n" ++
    "        exit 1\\n" ++
    "      fi\\n" ++
    "      ACTIVE_FRAMEWORK_BIN=\\\"${TMP_SIM_X64_FRAMEWORK_BIN}\\\"\\n" ++
    "      ;;\\n" ++
    "    *) echo \\\"error: unsupported iOS simulator arch '${ARCH_VALUE}' for Wizig FFI build\\\" >&2; exit 1 ;;\\n" ++
    "  esac\\n" ++
    "else\\n" ++
    "  echo \\\"error: unsupported Apple platform '${PLATFORM_NAME}' for Wizig FFI build\\\" >&2\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "mkdir -p \\\"${OUT_FRAMEWORK_DIR}\\\"\\n" ++
    "cp -f \\\"${ACTIVE_FRAMEWORK_BIN}\\\" \\\"${OUT_FRAMEWORK_BIN}\\\"\\n" ++
    "cp -f \\\"${TMP_FRAMEWORK_INFO}\\\" \\\"${OUT_FRAMEWORK_INFO}\\\"\\n" ++
    "if [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ]; then\\n" ++
    "  ARCH_INFO=\\\"$(xcrun lipo -info \\\"${OUT_FRAMEWORK_BIN}\\\" 2>/dev/null || true)\\\"\\n" ++
    "  if [ -z \\\"${ARCH_INFO}\\\" ]; then\\n" ++
    "    echo \\\"error: failed to inspect device framework architectures for App Store safety checks\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "  if ! printf '%s' \\\"${ARCH_INFO}\\\" | grep -Eq 'arm64'; then\\n" ++
    "    echo \\\"error: device framework must contain arm64 architecture (got: ${ARCH_INFO})\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "  if printf '%s' \\\"${ARCH_INFO}\\\" | grep -Eq 'x86_64|i386'; then\\n" ++
    "    echo \\\"error: device framework unexpectedly contains simulator architectures (got: ${ARCH_INFO})\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
    ios_phase_appstore_checks.private_api_guards ++
    "SIM_XC_FRAMEWORK_DIR=\\\"${TMP_SIM_ARM64_FRAMEWORK_DIR}\\\"\\n" ++
    "if [ \\\"${HAS_SIM_X64}\\\" = \\\"1\\\" ]; then\\n" ++
    "  mkdir -p \\\"${TMP_SIM_UNIVERSAL_FRAMEWORK_DIR}\\\"\\n" ++
    "  xcrun lipo -create \\\"${TMP_SIM_ARM64_FRAMEWORK_BIN}\\\" \\\"${TMP_SIM_X64_FRAMEWORK_BIN}\\\" -output \\\"${TMP_SIM_UNIVERSAL_FRAMEWORK_BIN}\\\"\\n" ++
    "  prepare_framework_metadata \\\"${TMP_SIM_UNIVERSAL_FRAMEWORK_DIR}\\\"\\n" ++
    "  SIM_XC_FRAMEWORK_DIR=\\\"${TMP_SIM_UNIVERSAL_FRAMEWORK_DIR}\\\"\\n" ++
    "fi\\n" ++
    "xcodebuild -create-xcframework -framework \\\"${TMP_DEVICE_FRAMEWORK_DIR}\\\" -framework \\\"${SIM_XC_FRAMEWORK_DIR}\\\" -output \\\"${TMP_XCFRAMEWORK_DIR}\\\" >/dev/null\\n" ++
    "rm -rf \\\"${XCFRAMEWORK_DIR}\\\"\\n" ++
    "mkdir -p \\\"${XCFRAMEWORK_DIR}\\\"\\n" ++
    "cp -R \\\"${TMP_XCFRAMEWORK_DIR}/.\\\" \\\"${XCFRAMEWORK_DIR}\\\"\\n\";\n" ++
    "\t\t};\n";
