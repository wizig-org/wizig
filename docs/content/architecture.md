# Architecture

## Goals

Ziggy is optimized for three constraints:

- Keep platform UX native and first-class.
- Share runtime/domain logic across hosts with Zig.
- Keep host interop typed and deterministic.

## Runtime Layers

1. **Host UI layer**
   - iOS: SwiftUI app target.
   - Android: Compose app module.
2. **Generated bridge layer**
   - Generated clients/events in Swift, Kotlin, Zig from one contract.
3. **FFI/runtime layer**
   - `ffi/src/root.zig` exports C ABI symbols.
   - `core/src/runtime.zig` provides runtime primitives.
4. **App domain layer**
   - Application business logic in `lib/` (Zig).

## Scaffold Layout

`ziggy create` produces:

- `lib/` app logic.
- `ios/` iOS host project.
- `android/` Android host project.
- `.ziggy/sdk/` vendored host SDK wrappers.
- `.ziggy/runtime/` vendored runtime sources.
- `.ziggy/generated/` generated bridge + registrants.
- `plugins/` local plugin packages.
- `ziggy.yaml` app configuration.
- `ziggy.api.zig` API contract.

Vendoring `.ziggy/` assets is deliberate: projects remain portable and do not depend on Ziggy repository-relative paths.

## SDK Resolution

Ziggy resolves SDK roots with strict precedence:

1. CLI flag `--sdk-root`
2. env `ZIGGY_SDK_ROOT`
3. install-relative bundles (`../share/ziggy`)
4. development workspace fallback markers

Resolution validates required markers and reports attempted roots when lookup fails.

## Run Pipeline

`ziggy run` uses one unified flow:

1. Resolve project root and available hosts.
2. Run codegen preflight (`ziggy.api.zig`, fallback `ziggy.api.json`).
3. Discover runnable iOS/Android targets.
4. Select target (interactive or non-interactive).
5. Delegate to platform build/install/launch flow.
6. Write run log to `.ziggy/logs/run.log`.

## Type-Safety Boundary

Type safety is generated from the contract into all target languages:

- Host call signatures are generated, not handwritten.
- Event sink interfaces are generated, not handwritten.
- Contract edits fail fast during compile if host code drifts.

The transport boundary still uses C ABI for runtime interoperability, but application-facing APIs stay typed.

## Web Expansion Hooks

Current web scope is interface-only:

- Target abstraction exists in codegen design.
- Runtime host capability abstractions reserve future web integration.
- No production web runtime is shipped in this phase.
