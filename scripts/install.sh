#!/bin/sh
# Wizig installer — https://wizig.org
#
# Usage:
#   curl -fsSL wizig.org/install.sh | sh                          # latest stable
#   curl -fsSL wizig.org/install.sh | sh -s -- nightly             # latest nightly
#   curl -fsSL wizig.org/install.sh | sh -s -- nightly-20260328    # specific nightly
#   curl -fsSL wizig.org/install.sh | sh -s -- 0.1.0              # specific version
#   curl -fsSL wizig.org/install.sh | sh -s -- --uninstall         # uninstall
#
# Environment variables:
#   WIZIG_VERSION       "nightly", "nightly-YYYYMMDD", or semver (default: latest)
#   WIZIG_INSTALL_DIR   Custom install location (default: $HOME/.wizig)

set -eu

WIZIG_REPO="wizig-org/wizig"
WIZIG_INSTALL_DIR="${WIZIG_INSTALL_DIR:-$HOME/.wizig}"

main() {
    if [ "${1:-}" = "--uninstall" ]; then
        do_uninstall
        return
    fi

    # Accept version as positional argument (overrides WIZIG_VERSION env var).
    if [ -n "${1:-}" ]; then
        WIZIG_VERSION="${1#v}"
    fi

    need_cmd curl
    need_cmd tar

    detect_platform
    resolve_version
    download_and_install
    setup_path

    printf "\nwizig %s installed successfully!\n" "$VERSION"
    printf "Run 'wizig doctor' to verify your environment.\n"
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)
            err "unsupported OS: $OS"
            ;;
    esac

    case "$ARCH" in
        arm64|aarch64) ARCH="arm64" ;;
        x86_64|amd64)  ARCH="x86_64" ;;
        *)
            err "unsupported architecture: $ARCH"
            ;;
    esac
}

resolve_version() {
    if [ -n "${WIZIG_VERSION:-}" ]; then
        VERSION="$WIZIG_VERSION"
        return
    fi

    printf "Resolving latest stable version...\n"

    RESPONSE="$(curl -fsSL "https://api.github.com/repos/${WIZIG_REPO}/releases/latest" 2>/dev/null)" || {
        err "could not fetch latest release from GitHub. Check your internet connection or set WIZIG_VERSION manually."
    }

    # Extract tag_name, then strip optional leading "v".
    TAG="$(printf '%s' "$RESPONSE" | grep '"tag_name"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    if [ -z "$TAG" ]; then
        err "could not parse latest version from GitHub response"
    fi
    VERSION="${TAG#v}"
}

download_and_install() {
    case "$VERSION" in
        nightly|nightly-[0-9]*)
            download_nightly
            ;;
        *)
            download_stable
            ;;
    esac

    printf "Installing wizig %s (%s-%s)...\n" "$VERSION" "$OS" "$ARCH"

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    # Download tarball.
    curl -fsSL "$URL" -o "$TMPDIR/$TARBALL" || {
        err "failed to download $URL\nhint: version $VERSION may not have a release for $OS-$ARCH"
    }

    # Verify checksum if available.
    if curl -fsSL "$CHECKSUM_URL" -o "$TMPDIR/checksum.txt" 2>/dev/null; then
        verify_checksum "$TMPDIR/$TARBALL" "$TMPDIR/checksum.txt"
    fi

    # Extract — strip the top-level directory name so any nightly date+sha
    # suffix is normalised into the install dir.
    tar xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

    # Find the single extracted directory (handles both stable and nightly names).
    EXTRACTED_DIR="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    if [ -z "$EXTRACTED_DIR" ]; then
        err "tarball did not contain an expected directory"
    fi

    # Install.
    mkdir -p "$WIZIG_INSTALL_DIR"
    cp -R "$EXTRACTED_DIR/"* "$WIZIG_INSTALL_DIR/"
    chmod +x "$WIZIG_INSTALL_DIR/bin/wizig"

    # Remove macOS quarantine attribute.
    if [ "$OS" = "macos" ]; then
        xattr -d com.apple.quarantine "$WIZIG_INSTALL_DIR/bin/wizig" 2>/dev/null || true
    fi

    printf "Installed to %s\n" "$WIZIG_INSTALL_DIR"
}

# Resolve a nightly release asset URL via GitHub API.  Nightly tarballs
# include a date+sha suffix (e.g. wizig-nightly-20260328-abc12345-macos-arm64)
# so we cannot predict the exact filename.
#
# Accepts VERSION = "nightly" (rolling latest) or "nightly-YYYYMMDD" (dated).
download_nightly() {
    NIGHTLY_TAG="$VERSION"
    printf "Resolving %s release...\n" "$NIGHTLY_TAG"

    RESPONSE="$(curl -fsSL "https://api.github.com/repos/${WIZIG_REPO}/releases/tags/${NIGHTLY_TAG}" 2>/dev/null)" || {
        err "could not fetch release '${NIGHTLY_TAG}'. Is there a release at\nhttps://github.com/${WIZIG_REPO}/releases/tag/${NIGHTLY_TAG} ?"
    }

    # Match the asset whose name ends with <os>-<arch>.tar.gz (not .sha256).
    ASSET_PATTERN="${OS}-${ARCH}\\.tar\\.gz\""
    TARBALL="$(printf '%s' "$RESPONSE" | grep '"name"' | grep "$ASSET_PATTERN" | grep -v '\.sha256' | head -n1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

    if [ -z "$TARBALL" ]; then
        err "no nightly asset found for ${OS}-${ARCH}\nhint: the ${NIGHTLY_TAG} release may not have been published yet"
    fi

    URL="https://github.com/${WIZIG_REPO}/releases/download/${NIGHTLY_TAG}/${TARBALL}"
    CHECKSUM_URL="${URL}.sha256"
}

# Resolve the stable release asset URL.  Tries both "vX.Y.Z" and "X.Y.Z" tag
# conventions.
download_stable() {
    TARBALL="wizig-${VERSION}-${OS}-${ARCH}.tar.gz"

    TAG_CANDIDATES="v${VERSION} ${VERSION}"
    URL=""
    for TAG_CANDIDATE in $TAG_CANDIDATES; do
        CANDIDATE_URL="https://github.com/${WIZIG_REPO}/releases/download/${TAG_CANDIDATE}/${TARBALL}"
        if curl -fsSL --head "$CANDIDATE_URL" >/dev/null 2>&1; then
            URL="$CANDIDATE_URL"
            break
        fi
    done
    if [ -z "$URL" ]; then
        URL="https://github.com/${WIZIG_REPO}/releases/download/v${VERSION}/${TARBALL}"
    fi
    CHECKSUM_URL="${URL}.sha256"
}

verify_checksum() {
    FILE="$1"
    CHECKSUM_FILE="$2"

    EXPECTED="$(awk '{print $1}' "$CHECKSUM_FILE")"

    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "$FILE" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        ACTUAL="$(shasum -a 256 "$FILE" | awk '{print $1}')"
    else
        printf "warning: no sha256 tool found, skipping checksum verification\n"
        return
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        err "checksum mismatch\n  expected: $EXPECTED\n  actual:   $ACTUAL"
    fi
}

setup_path() {
    BIN_DIR="$WIZIG_INSTALL_DIR/bin"

    # Already in PATH?
    case ":${PATH:-}:" in
        *":$BIN_DIR:"*)
            return
            ;;
    esac

    PROFILE_LINE="export PATH=\"$BIN_DIR:\$PATH\""

    # Detect shell profile.
    PROFILE=""
    case "${SHELL:-}" in
        */zsh)
            PROFILE="$HOME/.zshrc"
            ;;
        */bash)
            if [ -f "$HOME/.bash_profile" ]; then
                PROFILE="$HOME/.bash_profile"
            elif [ -f "$HOME/.bashrc" ]; then
                PROFILE="$HOME/.bashrc"
            else
                PROFILE="$HOME/.profile"
            fi
            ;;
        *)
            if [ -f "$HOME/.profile" ]; then
                PROFILE="$HOME/.profile"
            fi
            ;;
    esac

    if [ -n "$PROFILE" ]; then
        if ! grep -qF "$BIN_DIR" "$PROFILE" 2>/dev/null; then
            printf '\n# Wizig\n%s\n' "$PROFILE_LINE" >> "$PROFILE"
            printf "Added %s to PATH in %s\n" "$BIN_DIR" "$PROFILE"
        fi
    fi

    printf "\nTo use wizig now, run:\n  export PATH=\"%s:\$PATH\"\n" "$BIN_DIR"
}

do_uninstall() {
    if [ ! -d "$WIZIG_INSTALL_DIR" ]; then
        printf "wizig is not installed at %s\n" "$WIZIG_INSTALL_DIR"
        return
    fi

    printf "Removing wizig from %s...\n" "$WIZIG_INSTALL_DIR"
    rm -rf "$WIZIG_INSTALL_DIR"
    printf "Removed.\n\n"
    printf "You may want to remove the PATH entry from your shell profile.\n"
    printf "Look for and remove the line: export PATH=\"%s/bin:\$PATH\"\n" "$WIZIG_INSTALL_DIR"
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "'$1' is required but not found"
    fi
}

err() {
    printf "error: %b\n" "$1" >&2
    exit 1
}

main "$@"
