# Wizig Documentation Build

Wizig docs are generated from:

- Manual markdown pages in `docs/content/`
- Zig source comments (`//!`, `///`)
- Swift source comments (`///`, `/** ... */`)
- Kotlin source comments (`/** ... */`)

Generated API reference pages are written to `docs/content/reference/`.

## Requirements

- Python 3.12+
- Python package: `Markdown`

Install if missing:

```sh
python3 -m pip install Markdown
```

## Commands

```sh
# Generate reference + build static site
python3 scripts/docs_build.py

# Only regenerate API reference markdown
python3 scripts/docs_build.py --reference-only

# Only rebuild static site from existing markdown
python3 scripts/docs_build.py --site-only

# Verify deterministic generation + checked-in reference freshness
python3 scripts/docs_build.py --check
```

Output site directory:

- `docs/site/`
