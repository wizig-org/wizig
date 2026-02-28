# Swift Doc Comments

Use Swift doc comments that are compatible with Apple's documentation markup parser (Quick Help and DocC ingestion).

## Preferred Style

- Use `///` for short declaration docs.
- Use `/** ... */` for multi-line blocks.
- Start with a concise summary sentence in sentence case.
- Keep wrapped lines stable; avoid reflow-only churn in generated docs.

## Apple Markup Callouts

Use Apple's expected callout keywords and punctuation:

- `- Parameters:`
- `- Parameter <name>:`
- `- Returns:`
- `- Throws:`
- `- Important:`
- `- Warning:`
- `- Note:`
- `- Precondition:`
- `- Postcondition:`

## Example

```swift
/// Echoes a UTF-8 string through the Wizig runtime.
///
/// - Parameter input: UTF-8 text to pass to Zig.
/// - Returns: The echoed UTF-8 text returned by the runtime.
/// - Throws: `WizigRuntimeError` when runtime setup or FFI calls fail.
public func echo(_ input: String) throws -> String
```

## Authoring Rules

- Document observable behavior and invariants, not implementation mechanics.
- Describe failure modes with `- Throws:` when applicable.
- Keep parameter names in comments exactly matching function signatures.
- Avoid non-standard headers/callouts so generated markdown stays consistent.
