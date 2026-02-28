#!/usr/bin/env python3
"""Build Ziggy documentation.

Pipeline:
1) Parse Zig module/declaration docs from source comments (`//!` and `///`).
2) Generate Markdown API reference pages under `docs/content/reference/`.
3) Render all docs markdown pages into static HTML under `docs/site/`.

Uses the `Markdown` Python package for rendering.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = ROOT / "docs"
CONTENT_DIR = DOCS_DIR / "content"
REFERENCE_DIR = CONTENT_DIR / "reference"
SITE_DIR = DOCS_DIR / "site"
THEME_DIR = DOCS_DIR / "theme"
NAV_FILE = CONTENT_DIR / "_nav.txt"

SKIP_PARTS = {".git", ".zig-cache", "zig-out"}


@dataclass
class Declaration:
    kind: str
    name: str
    signature: str
    docs: list[str]


def discover_zig_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*.zig"):
        rel = path.relative_to(ROOT)
        if any(part in SKIP_PARTS for part in rel.parts):
            continue
        files.append(path)
    files.sort(key=lambda p: p.relative_to(ROOT).as_posix())
    return files


def extract_module_docs(lines: list[str]) -> list[str]:
    docs: list[str] = []
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if stripped.startswith("//!"):
            docs.append(stripped[3:].strip())
            index += 1
            continue
        if stripped == "" and docs:
            docs.append("")
            index += 1
            continue
        break
    while docs and docs[-1] == "":
        docs.pop()
    return docs


def extract_decl_docs(lines: list[str], decl_line: int) -> list[str]:
    docs_rev: list[str] = []
    cursor = decl_line - 1
    while cursor >= 0 and lines[cursor].strip() == "":
        cursor -= 1
    while cursor >= 0:
        stripped = lines[cursor].lstrip()
        if not stripped.startswith("///"):
            break
        docs_rev.append(stripped[3:].strip())
        cursor -= 1
    docs_rev.reverse()
    return docs_rev


def parse_decl_header(line: str) -> tuple[str, str] | None:
    stripped = line.strip()

    export_fn = re.match(r"^pub export fn\s+([A-Za-z0-9_]+)", stripped)
    if export_fn:
        return "export fn", export_fn.group(1)

    pub_fn = re.match(r"^pub fn\s+([A-Za-z0-9_]+)", stripped)
    if pub_fn:
        return "fn", pub_fn.group(1)

    pub_const = re.match(r"^pub const\s+([A-Za-z0-9_]+)", stripped)
    if pub_const:
        return "const", pub_const.group(1)

    return None


def collect_signature(lines: list[str], start: int, kind: str) -> str:
    signature = [lines[start].rstrip()]

    if kind in {"fn", "export fn"} and "{" not in lines[start]:
        cursor = start + 1
        while cursor < len(lines) and len(signature) < 24:
            signature.append(lines[cursor].rstrip())
            if "{" in lines[cursor]:
                break
            cursor += 1

    return "\n".join(signature).rstrip()


def extract_declarations(lines: list[str]) -> list[Declaration]:
    declarations: list[Declaration] = []
    for index, line in enumerate(lines):
        parsed = parse_decl_header(line)
        if parsed is None:
            continue
        kind, name = parsed
        declarations.append(
            Declaration(
                kind=kind,
                name=name,
                signature=collect_signature(lines, index, kind),
                docs=extract_decl_docs(lines, index),
            )
        )
    return declarations


def render_reference_page(rel_path: Path, module_docs: list[str], declarations: list[Declaration]) -> str:
    out: list[str] = []
    out.append(f"# `{rel_path.as_posix()}`")
    out.append("")

    if module_docs:
        out.extend(module_docs)
        out.append("")

    out.append("## Public API")
    out.append("")

    if not declarations:
        out.append("This file does not expose public declarations.")
        out.append("")
        return "\n".join(out)

    for decl in declarations:
        out.append(f"### `{decl.name}` ({decl.kind})")
        out.append("")
        if decl.docs:
            out.extend(decl.docs)
        else:
            out.append("No declaration docs available.")
        out.append("")
        out.append("```zig")
        out.append(decl.signature)
        out.append("```")
        out.append("")

    return "\n".join(out)


def generate_reference_markdown() -> list[Path]:
    if REFERENCE_DIR.exists():
        shutil.rmtree(REFERENCE_DIR)
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)

    pages: list[Path] = []

    for zig_file in discover_zig_files():
        rel = zig_file.relative_to(ROOT)
        lines = zig_file.read_text(encoding="utf-8").splitlines()
        module_docs = extract_module_docs(lines)
        declarations = extract_declarations(lines)

        output_path = REFERENCE_DIR / rel.with_suffix(".md")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            render_reference_page(rel, module_docs, declarations),
            encoding="utf-8",
        )
        pages.append(output_path)

    pages.sort(key=lambda p: p.relative_to(CONTENT_DIR).as_posix())

    index_lines = [
        "# API Reference",
        "",
        f"Auto-generated on {dt.datetime.now(tz=dt.UTC).strftime('%Y-%m-%d %H:%M:%SZ')}.",
        "",
        "## Source Files",
        "",
    ]

    for page in pages:
        rel_page = page.relative_to(REFERENCE_DIR)
        label = rel_page.as_posix().replace(".md", "")
        href = rel_page.as_posix()
        index_lines.append(f"- [`{label}`]({href})")

    index_lines.append("")
    (REFERENCE_DIR / "index.md").write_text("\n".join(index_lines), encoding="utf-8")

    return pages


def extract_page_title(md_text: str, fallback: str) -> str:
    for line in md_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    return fallback


def load_nav_entries(md_files: list[Path]) -> list[Path]:
    selected: list[Path] = []
    seen: set[Path] = set()

    if NAV_FILE.exists():
        for raw_line in NAV_FILE.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            rel = Path(line)
            candidate = CONTENT_DIR / rel
            if candidate.exists() and candidate.suffix == ".md" and candidate not in seen:
                selected.append(candidate)
                seen.add(candidate)

    for path in sorted(md_files, key=lambda p: p.relative_to(CONTENT_DIR).as_posix()):
        if path in seen:
            continue
        selected.append(path)
        seen.add(path)

    return selected


def rewrite_markdown_links(rendered_html: str) -> str:
    def replacer(match: re.Match[str]) -> str:
        target = match.group(1)
        anchor = match.group(2) or ""
        if "://" in target:
            return match.group(0)
        return f'href="{target}.html{anchor}"'

    return re.sub(r'href="([^"]+?)\.md(#[^"]*)?"', replacer, rendered_html)


def relative_href(from_html: Path, to_html: Path) -> str:
    rel = os.path.relpath(to_html, start=from_html.parent)
    return rel.replace(os.sep, "/")


def render_sidebar(current_md: Path, nav: list[Path], title_map: dict[Path, str]) -> str:
    current_html = current_md.with_suffix(".html")
    lines = ["<ul class=\"nav-list\">"]
    for entry in nav:
        entry_html = entry.with_suffix(".html")
        href = relative_href(current_html, entry_html)
        title = title_map.get(entry, entry.stem.replace("-", " ").title())
        active_class = " class=\"active\"" if entry == current_md else ""
        lines.append(f"<li{active_class}><a href=\"{href}\">{title}</a></li>")
    lines.append("</ul>")
    return "\n".join(lines)


def render_page_template(title: str, sidebar_html: str, body_html: str, css_href: str) -> str:
    return f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>{title} | Ziggy Docs</title>
  <link rel=\"stylesheet\" href=\"{css_href}\">
</head>
<body>
  <header class=\"topbar\">
    <a class=\"brand\" href=\"index.html\">Ziggy Documentation</a>
  </header>
  <div class=\"layout\">
    <aside class=\"sidebar\">{sidebar_html}</aside>
    <main class=\"content\"><article>{body_html}</article></main>
  </div>
</body>
</html>
"""


def build_site() -> None:
    md_files = sorted(
        [
            path
            for path in CONTENT_DIR.rglob("*.md")
            if path.name != "_nav.txt"
        ],
        key=lambda p: p.relative_to(CONTENT_DIR).as_posix(),
    )
    if not md_files:
        raise RuntimeError("No markdown files found in docs/content")

    if SITE_DIR.exists():
        shutil.rmtree(SITE_DIR)
    (SITE_DIR / "assets").mkdir(parents=True, exist_ok=True)
    shutil.copy2(THEME_DIR / "styles.css", SITE_DIR / "assets" / "styles.css")

    nav = load_nav_entries(md_files)
    title_map: dict[Path, str] = {}

    for md_path in md_files:
        rel = md_path.relative_to(CONTENT_DIR)
        fallback = rel.stem.replace("-", " ").title()
        title_map[md_path] = extract_page_title(md_path.read_text(encoding="utf-8"), fallback)

    extensions = [
        "fenced_code",
        "tables",
        "toc",
        "sane_lists",
        "attr_list",
        "codehilite",
    ]

    for md_path in md_files:
        rel = md_path.relative_to(CONTENT_DIR)
        out_path = SITE_DIR / rel.with_suffix(".html")
        out_path.parent.mkdir(parents=True, exist_ok=True)

        raw_text = md_path.read_text(encoding="utf-8")
        body_html = markdown.markdown(raw_text, extensions=extensions)
        body_html = rewrite_markdown_links(body_html)

        sidebar_html = render_sidebar(md_path, nav, title_map)
        css_href = relative_href(out_path, SITE_DIR / "assets" / "styles.css")

        page_html = render_page_template(
            title=title_map[md_path],
            sidebar_html=sidebar_html,
            body_html=body_html,
            css_href=css_href,
        )
        out_path.write_text(page_html, encoding="utf-8")



def main() -> None:
    parser = argparse.ArgumentParser(description="Generate and build Ziggy documentation")
    parser.add_argument(
        "--reference-only",
        action="store_true",
        help="Generate API reference markdown only",
    )
    parser.add_argument(
        "--site-only",
        action="store_true",
        help="Build HTML site from existing markdown only",
    )
    args = parser.parse_args()

    if args.reference_only and args.site_only:
        raise SystemExit("--reference-only and --site-only are mutually exclusive")

    CONTENT_DIR.mkdir(parents=True, exist_ok=True)
    THEME_DIR.mkdir(parents=True, exist_ok=True)

    if args.reference_only:
        pages = generate_reference_markdown()
        print(f"Generated {len(pages)} reference pages in {REFERENCE_DIR}")
        return

    if args.site_only:
        build_site()
        print(f"Built site at {SITE_DIR}")
        return

    pages = generate_reference_markdown()
    build_site()
    print(f"Generated {len(pages)} reference pages in {REFERENCE_DIR}")
    print(f"Built site at {SITE_DIR}")


if __name__ == "__main__":
    main()
