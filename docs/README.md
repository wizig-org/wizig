# Wizig Documentation

Wizig docs are built with [MkDocs](https://www.mkdocs.org/) using the [Material](https://squidfunk.github.io/mkdocs-material/) theme.

API reference pages are auto-generated from source comments (Zig `//!`/`///`, Swift `///`/`/** */`, Kotlin `/** */`).

## Requirements

- Python 3.10+
- Dependencies: `pip install -r docs/requirements.txt`

## Commands

```sh
# Build the full documentation site
zig build docs

# Or run steps individually:
python3 scripts/docs_build.py --reference-only   # Generate API reference
mkdocs build                                      # Build static site

# Preview locally with live reload
mkdocs serve

# Verify API reference determinism
python3 scripts/docs_build.py --check
```

Output site directory: `site/` (at project root, per MkDocs default).
