# Docs Pipeline

Wizig documentation is generated with a Python pipeline and rendered as static HTML.

## Tooling

The pipeline depends on Python and the [`Markdown`](https://pypi.org/project/Markdown/) package.

Install dependency:

```sh
python3 -m pip install --upgrade markdown
```

## Entry Points

Run full pipeline:

```sh
zig build docs
# equivalent to:
python3 scripts/docs_build.py
```

## Stages

1. Discover Zig source files.
2. Extract module docs from `//!` comments.
3. Extract public declaration docs from `///` comments.
4. Generate markdown reference pages under `docs/content/reference/`.
5. Render all markdown to static HTML under `docs/site/`.

## Modes

Reference only:

```sh
python3 scripts/docs_build.py --reference-only
```

Site render only:

```sh
python3 scripts/docs_build.py --site-only
```

## Inputs And Outputs

- Navigation file: `docs/content/_nav.txt`
- Manual docs: `docs/content/*.md`
- Theme assets: `docs/theme/styles.css`
- Generated reference: `docs/content/reference/`
- Built site: `docs/site/`

## Authoring Guidance

For Zig source documentation quality:

- Use `//!` at file top for module-level context.
- Use `///` on public declarations with behavior/constraints.
- Keep comments focused on invariants and contracts, not obvious syntax.
