# Docs Pipeline

Ziggy docs are generated with a Python-based pipeline using the `Markdown` package.

Entry point:

```sh
python3 scripts/docs_build.py
```

## Stages

1. Parse Zig source comments:
   - module docs from `//!`
   - exported declaration docs from `///`
2. Emit Markdown reference pages under `docs/content/reference/`
3. Render all markdown pages into static HTML under `docs/site/`

## Modes

```sh
python3 scripts/docs_build.py --reference-only
python3 scripts/docs_build.py --site-only
```

## Styling

The generated HTML site uses custom theme assets from:

- `docs/theme/styles.css`
