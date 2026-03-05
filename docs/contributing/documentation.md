# Documentation Guide

## Building Documentation

Install dependencies:

```sh
pip install -r docs/requirements.txt
```

Build the documentation site:

```sh
zig build docs
```

Preview locally:

```sh
mkdocs serve
```

This starts a local server at `http://127.0.0.1:8000` with live reload.

## Documentation Structure

Documentation lives in `docs/` and is organized by audience:

| Directory | Audience |
|-----------|----------|
| `getting-started/` | New users |
| `architecture/` | Developers wanting to understand internals |
| `guide/` | Users building apps |
| `reference/` | Users looking up specific details |
| `contributing/` | Contributors to the Wizig project |
| `adr/` | Design decision records |

Navigation is defined in `mkdocs.yml` at the project root.

## API Reference Generation

API reference pages are auto-generated from source code comments:

```sh
python3 scripts/docs_build.py --reference-only
```

This scans `.zig`, `.swift`, and `.kt` files and generates markdown under `docs/reference/api/`.

The `zig build docs` step runs this automatically before building the MkDocs site.

## Writing Documentation

### Style

- Use clear, direct language.
- Lead with the most important information.
- Use tables for structured data instead of long lists.
- Include code examples for any non-trivial concept.

### Zig Source Comments

For Zig source documentation that feeds into API reference:

- Use `//!` at file top for module-level context.
- Use `///` on public declarations with behavior/constraints.
- Keep comments focused on invariants and contracts, not obvious syntax.

### Swift Source Comments

For Swift source documentation:

- Use `///` for short declaration docs.
- Use `/** ... */` for multi-line blocks.
- Start with a concise summary sentence.
- Use Apple markup callouts: `- Parameters:`, `- Returns:`, `- Throws:`, `- Important:`, `- Warning:`, `- Note:`

Example:

```swift
/// Echoes a UTF-8 string through the Wizig runtime.
///
/// - Parameter input: UTF-8 text to pass to Zig.
/// - Returns: The echoed UTF-8 text returned by the runtime.
/// - Throws: `WizigRuntimeError` when runtime setup or FFI calls fail.
public func echo(_ input: String) throws -> String
```

### Kotlin Source Comments

- Use `/** ... */` blocks on public/open declarations.
- Private and internal declarations are filtered from generated docs.

### Adding a New Page

1. Create the markdown file in the appropriate `docs/` subdirectory.
2. Add the page to the `nav` section in `mkdocs.yml`.
3. Build and preview: `mkdocs serve`.

## Determinism Checks

The API reference generation is deterministic — running it twice produces identical output. CI validates this with:

```sh
python3 scripts/docs_build.py --check
```
