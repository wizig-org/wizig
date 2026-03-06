# `cli/src/commands/codegen/ios_host_phase_appstore_checks.zig`

_Language: Zig_

Shared iOS App Store safety checks injected into Xcode build-phase scripts.

These checks fail the build when private frameworks or denylisted private
symbols are imported by the generated device framework binary.

Note: once the device framework has been codesigned, `xcrun nm -u -j` can
reject Zig-produced Mach-O binaries as malformed even though the binary is
valid and launchable. `xcrun dyld_info -imports` remains reliable after
signing, so the generated shell snippet prefers that tool and falls back to
`nm` for older toolchains.

## Public API

### `private_api_guards` (const)

Shell snippet that validates private framework/symbol linkage.

```zig
pub const private_api_guards =
```
