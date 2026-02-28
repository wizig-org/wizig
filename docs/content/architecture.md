# Architecture

## Design Direction

Ziggy uses a hybrid model:

- Native UI hosts on each platform
- Zig core for shared domain logic/runtime
- Typed code-generated bridge boundary

This keeps platform UX native while sharing the majority of app behavior.

## Project Layout

`ziggy create` scaffolds:

- `lib/` app Zig logic
- `ios/` native iOS host
- `android/` native Android host
- `.ziggy/sdk/` app-local host SDK wrappers
- `.ziggy/runtime/` app-local runtime/FFI sources
- `.ziggy/generated/` typed generated bindings

## SDK Resolution

SDK lookup precedence:

1. `--sdk-root`
2. `ZIGGY_SDK_ROOT`
3. install-relative bundles (`share/ziggy`)
4. dev workspace fallback markers

## Run Pipeline

Unified run flow:

1. Resolve project root and host presence
2. Run codegen preflight (`ziggy.api.json`)
3. Enumerate available iOS/Android targets
4. Delegate to platform runner
5. Build/install/launch app

iOS path additionally regenerates Xcode project from `project.yml` before build to keep generated source inclusion correct.

## Runtime Boundary

- `core/src/runtime.zig` provides shared runtime primitives
- `ffi/src/root.zig` exposes C ABI entrypoints
- Host runtimes consume `ziggy_runtime_*` exported functions
