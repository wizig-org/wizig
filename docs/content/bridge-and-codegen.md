# Bridge And Codegen

## Contract File

The typed boundary is defined by `ziggy.api.json` in app root.

Minimal shape:

```json
{
  "namespace": "app",
  "methods": [
    { "name": "echo", "input": "string", "output": "string" }
  ],
  "events": [
    { "name": "ready", "payload": "string" }
  ]
}
```

## Generated Artifacts

`ziggy codegen` emits:

- Zig: `.ziggy/generated/zig/ZiggyGeneratedApi.zig`
- Swift: `.ziggy/generated/swift/ZiggyGeneratedApi.swift`
- Kotlin: `.ziggy/generated/kotlin/dev/ziggy/generated/ZiggyGeneratedApi.kt`

## Type Safety

All generated client surfaces share the same source contract, which gives:

- Stable method names/arity
- Stable payload types
- Early compile-time errors in host code when contract changes

## Operational Notes

- `ziggy create` runs initial codegen before host generation.
- `ziggy run` reruns codegen preflight automatically.
- iOS host regeneration is performed before build to include newly generated Swift files.
