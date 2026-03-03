//! Shared shell-script snippets for deterministic iOS Zig toolchain selection.
//!
//! This module keeps the main build-phase template focused on orchestration
//! while encapsulating lock-based Zig resolution and optional auto-install.

/// Resolves `ZIG_BIN` deterministically from lock metadata.
///
/// Behavior:
/// - Reads `.wizig/toolchain.lock.json` for zig detected/min version.
/// - Prefers explicit `ZIG_BINARY`, then cached lock-pinned installs.
/// - Supports opt-in network install (`WIZIG_ZIG_AUTO_INSTALL=1`).
/// - Enforces lock version minimum unless drift override is explicitly set.
pub const resolve_zig =
    "LOCK_PATH=\\\"${APP_ROOT}/.wizig/toolchain.lock.json\\\"\\n" ++
    "LOCK_ZIG_VERSION=\\\"\\\"\\n" ++
    "if [ -f \\\"${LOCK_PATH}\\\" ]; then\\n" ++
    "  LOCK_ZIG_VERSION=\\\"$(awk '/\\\"zig\\\"[[:space:]]*:[[:space:]]*\\{/{inzig=1;next} inzig&&/^[[:space:]]*\\}/{inzig=0} inzig&&/\\\"detected_version\\\"[[:space:]]*:[[:space:]]*\\\"/{line=$0; sub(/.*\\\"detected_version\\\"[[:space:]]*:[[:space:]]*\\\"/,\\\"\\\",line); sub(/\\\".*/,\\\"\\\",line); print line; exit}' \\\"${LOCK_PATH}\\\" || true)\\\"\\n" ++
    "  if [ -z \\\"${LOCK_ZIG_VERSION}\\\" ]; then\\n" ++
    "    LOCK_ZIG_VERSION=\\\"$(awk '/\\\"zig\\\"[[:space:]]*:[[:space:]]*\\{/{inzig=1;next} inzig&&/^[[:space:]]*\\}/{inzig=0} inzig&&/\\\"min_version\\\"[[:space:]]*:[[:space:]]*\\\"/{line=$0; sub(/.*\\\"min_version\\\"[[:space:]]*:[[:space:]]*\\\"/,\\\"\\\",line); sub(/\\\".*/,\\\"\\\",line); print line; exit}' \\\"${LOCK_PATH}\\\" || true)\\\"\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
    "version_at_least() {\\n" ++
    "  awk -v have=\\\"$1\\\" -v need=\\\"$2\\\" 'function norm(v,a,n,i){gsub(/[^0-9.]/,\\\".\\\",v); n=split(v,a,\\\".\\\"); for(i=1;i<=4;i++) if(a[i]==\\\"\\\") a[i]=0;} BEGIN{norm(have,H); norm(need,N); for(i=1;i<=4;i++){if((H[i]+0)>(N[i]+0)) exit 0; if((H[i]+0)<(N[i]+0)) exit 1;} exit 0;}'\\n" ++
    "}\\n" ++
    "detect_zig_version() {\\n" ++
    "  \\\"$1\\\" version 2>/dev/null | head -n 1 | tr -d '\\\\r'\\n" ++
    "}\\n" ++
    "ZIG_BIN=\\\"${ZIG_BINARY:-}\\\"\\n" ++
    "WIZIG_ZIG_CACHE_ROOT=\\\"${WIZIG_ZIG_CACHE_ROOT:-${HOME}/Library/Caches/wizig/zig}\\\"\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ] && [ -n \\\"${LOCK_ZIG_VERSION}\\\" ]; then\\n" ++
    "  LOCKED_ROOT=\\\"${WIZIG_ZIG_CACHE_ROOT}/${LOCK_ZIG_VERSION}\\\"\\n" ++
    "  if [ -x \\\"${LOCKED_ROOT}/zig\\\" ]; then\\n" ++
    "    ZIG_BIN=\\\"${LOCKED_ROOT}/zig\\\"\\n" ++
    "  else\\n" ++
    "    ZIG_BIN=\\\"$(find \\\"${LOCKED_ROOT}\\\" -maxdepth 3 -type f -name zig -perm -111 2>/dev/null | head -n 1 || true)\\\"\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
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
    "if [ -z \\\"${ZIG_BIN}\\\" ] && [ -n \\\"${LOCK_ZIG_VERSION}\\\" ] && [ \\\"${WIZIG_ZIG_AUTO_INSTALL:-0}\\\" = \\\"1\\\" ]; then\\n" ++
    "  case \\\"$(uname -s)\\\" in Darwin) ZIG_OS=macos ;; *) ZIG_OS=\\\"\\\" ;; esac\\n" ++
    "  case \\\"$(uname -m)\\\" in arm64|aarch64) ZIG_ARCH=aarch64 ;; x86_64) ZIG_ARCH=x86_64 ;; *) ZIG_ARCH=\\\"\\\" ;; esac\\n" ++
    "  if [ -n \\\"${ZIG_OS}\\\" ] && [ -n \\\"${ZIG_ARCH}\\\" ]; then\\n" ++
    "    ZIG_ARCHIVE=\\\"zig-${ZIG_OS}-${ZIG_ARCH}-${LOCK_ZIG_VERSION}.tar.xz\\\"\\n" ++
    "    ZIG_URL_TEMPLATE=\\\"${WIZIG_ZIG_DOWNLOAD_URL_TEMPLATE:-https://ziglang.org/download/{version}/{archive}}\\\"\\n" ++
    "    ZIG_URL=\\\"${WIZIG_ZIG_DOWNLOAD_URL:-$(printf '%s' \\\"${ZIG_URL_TEMPLATE}\\\" | sed \\\"s|{version}|${LOCK_ZIG_VERSION}|g; s|{archive}|${ZIG_ARCHIVE}|g\\\")}\\\"\\n" ++
    "    ZIG_INSTALL_ROOT=\\\"${WIZIG_ZIG_CACHE_ROOT}/${LOCK_ZIG_VERSION}\\\"\\n" ++
    "    ZIG_ARCHIVE_PATH=\\\"${TMP_BASE}/wizig-zig-${LOCK_ZIG_VERSION}.tar.xz\\\"\\n" ++
    "    ZIG_EXTRACT_ROOT=\\\"${TMP_BASE}/wizig-zig-${LOCK_ZIG_VERSION}\\\"\\n" ++
    "    mkdir -p \\\"${WIZIG_ZIG_CACHE_ROOT}\\\"\\n" ++
    "    rm -rf \\\"${ZIG_EXTRACT_ROOT}\\\"\\n" ++
    "    if ! curl -fsSL \\\"${ZIG_URL}\\\" -o \\\"${ZIG_ARCHIVE_PATH}\\\"; then\\n" ++
    "      echo \\\"error: failed to download locked Zig toolchain from ${ZIG_URL}\\\" >&2\\n" ++
    "      exit 1\\n" ++
    "    fi\\n" ++
    "    mkdir -p \\\"${ZIG_EXTRACT_ROOT}\\\"\\n" ++
    "    if ! tar -xJf \\\"${ZIG_ARCHIVE_PATH}\\\" -C \\\"${ZIG_EXTRACT_ROOT}\\\"; then\\n" ++
    "      echo \\\"error: failed to extract downloaded Zig archive ${ZIG_ARCHIVE_PATH}\\\" >&2\\n" ++
    "      exit 1\\n" ++
    "    fi\\n" ++
    "    rm -rf \\\"${ZIG_INSTALL_ROOT}\\\"\\n" ++
    "    mkdir -p \\\"${ZIG_INSTALL_ROOT}\\\"\\n" ++
    "    cp -R \\\"${ZIG_EXTRACT_ROOT}/.\\\" \\\"${ZIG_INSTALL_ROOT}\\\"\\n" ++
    "    ZIG_BIN=\\\"$(find \\\"${ZIG_INSTALL_ROOT}\\\" -maxdepth 3 -type f -name zig -perm -111 | head -n 1 || true)\\\"\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  echo \\\"error: zig is not installed or discoverable (PATH/ZIG_BINARY/common locations); required for Wizig iOS FFI build\\\" >&2\\n" ++
    "  if [ -n \\\"${LOCK_ZIG_VERSION}\\\" ]; then\\n" ++
    "    echo \\\"hint: set WIZIG_ZIG_AUTO_INSTALL=1 to download locked Zig ${LOCK_ZIG_VERSION}\\\" >&2\\n" ++
    "  fi\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "if [ -n \\\"${LOCK_ZIG_VERSION}\\\" ]; then\\n" ++
    "  DETECTED_ZIG_VERSION=\\\"$(detect_zig_version \\\"${ZIG_BIN}\\\")\\\"\\n" ++
    "  if [ -z \\\"${DETECTED_ZIG_VERSION}\\\" ]; then\\n" ++
    "    echo \\\"error: failed to resolve Zig version from ${ZIG_BIN}\\\" >&2\\n" ++
    "    exit 1\\n" ++
    "  fi\\n" ++
    "  if ! version_at_least \\\"${DETECTED_ZIG_VERSION}\\\" \\\"${LOCK_ZIG_VERSION}\\\"; then\\n" ++
    "    if [ \\\"${WIZIG_FFI_ALLOW_TOOLCHAIN_DRIFT:-0}\\\" = \\\"1\\\" ]; then\\n" ++
    "      echo \\\"warning: Zig toolchain drift detected (${DETECTED_ZIG_VERSION} < ${LOCK_ZIG_VERSION}); continuing because WIZIG_FFI_ALLOW_TOOLCHAIN_DRIFT=1\\\" >&2\\n" ++
    "    else\\n" ++
    "      echo \\\"error: Zig toolchain drift detected (${DETECTED_ZIG_VERSION} < ${LOCK_ZIG_VERSION}); set WIZIG_FFI_ALLOW_TOOLCHAIN_DRIFT=1 to bypass\\\" >&2\\n" ++
    "      exit 1\\n" ++
    "    fi\\n" ++
    "  fi\\n" ++
    "fi\\n";
