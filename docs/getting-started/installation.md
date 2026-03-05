# Installation

## Prerequisites

Wizig requires the following tools installed on your development machine.

### Required

| Tool | Version | Purpose |
|------|---------|---------|
| Zig | `0.15.1` | Compiles shared runtime and app logic |
| Xcode | `26+` | iOS builds (`xcodebuild`, `xcrun`) |
| Java | `21` | Android builds |
| Gradle | `9.3.1` | Android build system |
| Android SDK | latest | `adb`, emulator, platform SDKs |

### Optional

| Tool | Purpose |
|------|---------|
| XcodeGen | Legacy iOS project regeneration |
| Python | `3.10+` for docs tooling |

## macOS Setup (Homebrew)

```sh
# Core tools
brew install gradle openjdk@21 python

# Android tooling
brew install --cask android-platform-tools android-commandlinetools

# Optional
brew install xcodegen
```

### Zig

Install Zig `0.15.1` from [ziglang.org/download](https://ziglang.org/download/):

```sh
# Example: download and add to PATH
curl -LO https://ziglang.org/download/0.15.1/zig-macos-aarch64-0.15.1.tar.xz
tar xf zig-macos-aarch64-0.15.1.tar.xz
export PATH="$PWD/zig-macos-aarch64-0.15.1:$PATH"
```

### Android SDK

After installing command-line tools, accept licenses and install platform SDKs:

```sh
sdkmanager --licenses
sdkmanager "platforms;android-36" "build-tools;36.0.0"
```

## Verify Installation

Run the Wizig doctor to validate your environment:

```sh
zig build && ./zig-out/bin/wizig doctor --sdk-root .
```

Doctor checks each tool against the minimum version policy defined in `toolchains.toml` and reports any issues.

## Next Steps

Once your environment is set up, proceed to the [Quick Start](quick-start.md) to create your first app.
