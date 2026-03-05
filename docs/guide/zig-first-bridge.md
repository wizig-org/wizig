# Zig-First Bridge Design

This page explains why Wizig moved from JSON-first contracts to Zig-first contracts and what this means for native package interop.

## Why Zig-First

A Zig contract (`wizig.api.zig`) gives better cohesion than a parallel JSON schema:

- Contract and runtime are expressed in the same language family.
- Changes are easier to review in one ecosystem.
- Project scaffolds avoid schema drift between runtime and bindings.

JSON remains supported for compatibility, but new apps should use Zig contracts.

## Contract Model

`wizig.api.zig` uses a minimal declaration subset intentionally:

```zig
pub const namespace = "dev.wizig.app";

pub const methods = .{
    .{ .name = "echo", .input = .string, .output = .string },
};

pub const events = .{
    .{ .name = "log", .payload = .string },
};
```

Current scalar type system: `.string`, `.int`, `.bool`, `.void`.

This keeps the parser deterministic while the bridge surface is stabilized.

## Type Safety Model

Type safety is enforced across the generated surface:

- Contract defines canonical method/event signatures.
- Swift and Kotlin clients are generated from the same source.
- Zig client stubs are generated from the same source.
- Host build breaks if code uses stale signatures.

The runtime transport boundary remains C ABI-based, but application-facing APIs remain typed.

## Native Package Interop

### Swift Packages (SPM)

- Some Swift code can expose C-compatible APIs, but most packages are not authored as stable C ABI libraries.
- Swift ABI stability does not imply universal C ABI compatibility.
- Converting arbitrary SPM package graphs into reusable C surfaces is high-friction and brittle across toolchain changes.

### Kotlin/Android Packages (Maven)

- JVM/ART-based libraries are not C ABI libraries.
- NDK-facing libraries can expose C APIs, but typical Android dependencies do not.
- Automatic JVM-to-C conversion is not a viable default architecture.

## Recommended Interop Strategy

Use a split-responsibility model:

1. **Keep native package logic in host language** (Swift/Kotlin).
2. **Keep shared business/runtime logic in Zig**.
3. **Bridge host and Zig through generated typed APIs/events**.
4. **Restrict direct C ABI import** to dependencies that explicitly ship C interfaces.

This is reliable across iOS and Android toolchains and aligns with Wizig plugin v2 static registration.

## Migration from JSON Contracts

For existing JSON-contract projects:

1. Add `wizig.api.zig` with equivalent namespace/method/event definitions.
2. Update `wizig.yaml` `api:` to `wizig.api.zig`.
3. Run `wizig codegen`.
4. Remove stale hand-written host wrappers replaced by generated APIs.

If both files exist, Zig contract takes precedence unless `--api` overrides.
