set -euo pipefail
APP_ROOT="${SRCROOT}/.."
WIZIG_BIN="${WIZIG_BIN:-}"
if [ -z "${WIZIG_BIN}" ] && command -v wizig >/dev/null 2>&1; then
  WIZIG_BIN="$(command -v wizig)"
fi
if [ -n "${WIZIG_BIN}" ]; then
  if ! "${WIZIG_BIN}" codegen "${APP_ROOT}" >/dev/null 2>&1; then
    echo "warning: wizig codegen failed from Xcode build; continuing with existing generated artifacts"
  fi
fi
GENERATED_ROOT="${APP_ROOT}/.wizig/generated/zig"
RUNTIME_ROOT="${APP_ROOT}/.wizig/runtime"
APP_MODULE="${APP_ROOT}/lib/WizigGeneratedAppModule.zig"
FFI_ROOT="${GENERATED_ROOT}/WizigGeneratedFfiRoot.zig"
if [ ! -f "${FFI_ROOT}" ]; then
  echo "warning: missing ${FFI_ROOT}; run 'wizig codegen ${APP_ROOT}'"
  exit 0
fi
OUT_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
mkdir -p "${OUT_DIR}"
PLATFORM="${PLATFORM_NAME:-iphonesimulator}"
ARCH="${NATIVE_ARCH_ACTUAL:-${CURRENT_ARCH:-arm64}}"
if [ "${PLATFORM}" = "iphoneos" ]; then
  TARGET_TRIPLE="aarch64-ios"
  SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
elif [ "${ARCH}" = "x86_64" ]; then
  TARGET_TRIPLE="x86_64-ios-simulator"
  SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
else
  TARGET_TRIPLE="aarch64-ios-simulator"
  SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
fi
ZIG_BIN="${WIZIG_ZIG_BIN:-${ZIG_BIN:-}}"
if [ -z "${ZIG_BIN}" ] && command -v zig >/dev/null 2>&1; then
  ZIG_BIN="$(command -v zig)"
fi
if [ -z "${ZIG_BIN}" ] && [ -n "${WIZIG_BIN}" ]; then
  WIZIG_BIN_DIR="$(cd "$(dirname "${WIZIG_BIN}")" && pwd)"
  for candidate in "${WIZIG_BIN_DIR}/zig" "${WIZIG_BIN_DIR}/../zig"; do
    if [ -x "${candidate}" ]; then
      ZIG_BIN="${candidate}"
      break
    fi
  done
fi
if [ -z "${ZIG_BIN}" ]; then
  for candidate in "/opt/homebrew/bin/zig" "/usr/local/bin/zig" "${HOME}/.zvm/bin/zig" "${HOME}/.zvm/master/zig"; do
    if [ -x "${candidate}" ]; then
      ZIG_BIN="${candidate}"
      break
    fi
  done
fi
if [ -z "${ZIG_BIN}" ]; then
  echo "error: unable to find zig compiler (set WIZIG_ZIG_BIN or add zig to PATH)"
  exit 1
fi
"${ZIG_BIN}" build-lib -OReleaseFast -target "${TARGET_TRIPLE}" --dep wizig_core --dep wizig_app \
  -Mroot="${FFI_ROOT}" \
  -Mwizig_core="${RUNTIME_ROOT}/core/src/root.zig" \
  -Mwizig_app="${APP_MODULE}" \
  --name wizigffi -dynamic -fstrip -install_name @rpath/wizigffi --sysroot "${SDK_PATH}" -L/usr/lib -F/System/Library/Frameworks -lc \
  -femit-bin="${OUT_DIR}/wizigffi"
