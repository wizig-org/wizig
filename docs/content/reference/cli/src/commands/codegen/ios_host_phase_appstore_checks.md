# `cli/src/commands/codegen/ios_host_phase_appstore_checks.zig`

_Language: Zig_

Shared iOS App Store safety checks injected into Xcode build-phase scripts.

These checks fail the build when private frameworks or denylisted private
symbols are imported by the generated device framework binary.

## Public API

### `private_api_guards` (const)

Shell snippet that validates private framework/symbol linkage.

```zig
pub const private_api_guards =
```
