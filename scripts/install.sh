#!/bin/sh
# Wizig installer — https://wizig.org
#
# Usage:
#   curl -fsSL wizig.org/install.sh | sh                    # latest
#   curl -fsSL wizig.org/install.sh | sh -s -- 0.1.0        # specific version
#   curl -fsSL wizig.org/install.sh | sh -s -- --uninstall   # uninstall
#
# Environment variables:
#   WIZIG_VERSION       Install a specific version (default: latest)
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

    printf "Resolving latest version...\n"

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
    TARBALL="wizig-${VERSION}-${OS}-${ARCH}.tar.gz"

    # Try the tag as-is first (handles both "v0.1.0" and "0.1.0" tags),
    # then fall back to the opposite convention.
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

    # Extract.
    tar xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

    # Install.
    mkdir -p "$WIZIG_INSTALL_DIR"
    cp -R "$TMPDIR/wizig-${VERSION}-${OS}-${ARCH}/"* "$WIZIG_INSTALL_DIR/"
    chmod +x "$WIZIG_INSTALL_DIR/bin/wizig"

    # Remove macOS quarantine attribute.
    if [ "$OS" = "macos" ]; then
        xattr -d com.apple.quarantine "$WIZIG_INSTALL_DIR/bin/wizig" 2>/dev/null || true
    fi

    printf "Installed to %s\n" "$WIZIG_INSTALL_DIR"
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
