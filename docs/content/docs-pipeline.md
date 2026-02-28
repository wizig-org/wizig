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

1. Discover source files for Zig (`.zig`), Swift (`.swift`), and Kotlin (`.kt`).
2. Extract module and declaration docs from language-native comment styles:
   - Zig: `//!`, `///`
   - Swift: `///`, `/** ... */`
   - Kotlin: `/** ... */`
3. Generate markdown reference pages under `docs/content/reference/`.
4. Render all markdown to static HTML under `docs/site/`.

## Modes

Reference only:

```sh
python3 scripts/docs_build.py --reference-only
```

Site render only:

```sh
python3 scripts/docs_build.py --site-only
```

Determinism + freshness check:

```sh
python3 scripts/docs_build.py --check
```

`--check` runs two isolated generations and compares them for deterministic output, then verifies checked-in `docs/content/reference/` freshness. If `docs/site/` exists locally, it also validates site freshness.

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

For Swift doc comment formatting, follow [Swift Doc Comments](swift-doc-comments.md).
