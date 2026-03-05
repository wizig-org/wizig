#!/usr/bin/env python3
"""Generate Wizig API reference documentation.

Pipeline:
1) Parse Zig/Swift/Kotlin module and declaration docs from source comments.
2) Generate Markdown API reference pages under `docs/reference/api/`.

Site rendering is handled by MkDocs (see mkdocs.yml).
"""

from __future__ import annotations

import argparse
import re
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = ROOT / "docs"
REFERENCE_DIR = DOCS_DIR / "reference" / "api"

SKIP_PARTS = {".git", ".zig-cache", "zig-out", "build"}
SKIP_PREFIXES = ("wizig-",)
LANGUAGE_BY_SUFFIX = {
    ".zig": "zig",
    ".swift": "swift",
    ".kt": "kotlin",
}
LANGUAGE_LABELS = {
    "zig": "Zig",
    "swift": "Swift",
    "kotlin": "Kotlin",
}
LANGUAGE_ORDER = ("zig", "swift", "kotlin")
LANGUAGE_ORDER_INDEX = {language: index for index, language in enumerate(LANGUAGE_ORDER)}

SWIFT_TYPE_DECL_RE = re.compile(
    r"^(?:public|open)\s+(?:final\s+)?(?P<kind>class|struct|enum|protocol|actor)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
SWIFT_MEMBER_DECL_RE = re.compile(
    r"^(?:public|open)\s+(?:private\(set\)\s+)?(?:(?:static|class)\s+)?(?P<kind>func|var|let)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
SWIFT_INIT_DECL_RE = re.compile(r"^(?:public|open)\s+init\b")

KOTLIN_DECL_RE = re.compile(
    r"^(?:(?:public|open|final|abstract|sealed|data|value|enum|external|actual|expect|override|suspend|inline|operator|infix|tailrec)\s+)*(?P<kind>class|interface|object|fun|val|var)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
KOTLIN_HIDDEN_MODIFIER_RE = re.compile(r"^(private|internal|protected)\b")


@dataclass
class SourceFile:
    language: str
    path: Path
    rel_path: Path


@dataclass
class Declaration:
    kind: str
    name: str
    signature: str
    docs: list[str]


@dataclass
class GeneratedReferencePage:
    language: str
    source_rel_path: Path
    output_rel_path: Path


@dataclass
class KotlinScope:
    kind: str
    hidden: bool


def discover_source_files() -> list[SourceFile]:
    files: list[SourceFile] = []
    for suffix, language in LANGUAGE_BY_SUFFIX.items():
        for path in ROOT.rglob(f"*{suffix}"):
            rel = path.relative_to(ROOT)
            if any(part in SKIP_PARTS or any(part.startswith(prefix) for prefix in SKIP_PREFIXES) for part in rel.parts):
                continue
            files.append(SourceFile(language=language, path=path, rel_path=rel))

    files.sort(key=lambda item: (LANGUAGE_ORDER_INDEX[item.language], item.rel_path.as_posix()))
    return files


def trim_blank_lines(lines: list[str]) -> list[str]:
    start = 0
    end = len(lines)
    while start < end and lines[start] == "":
        start += 1
    while end > start and lines[end - 1] == "":
        end -= 1
    return lines[start:end]


def parse_doc_block_lines(block_lines: list[str]) -> list[str]:
    docs: list[str] = []
    for index, raw_line in enumerate(block_lines):
        text = raw_line.strip()
        if index == 0 and text.startswith("/**"):
            text = text[3:]
        if index == len(block_lines) - 1 and text.endswith("*/"):
            text = text[:-2]
        text = text.lstrip()
        if text.startswith("*"):
            text = text[1:]
            if text.startswith(" "):
                text = text[1:]
        docs.append(text.rstrip())
    return trim_blank_lines(docs)


def extract_top_doc_block(lines: list[str]) -> list[str]:
    index = 0
    while index < len(lines) and lines[index].strip() == "":
        index += 1

    if index >= len(lines):
        return []

    stripped = lines[index].lstrip()
    if stripped.startswith("///"):
        docs: list[str] = []
        while index < len(lines):
            candidate = lines[index].lstrip()
            if not candidate.startswith("///"):
                break
            docs.append(candidate[3:].strip())
            index += 1
        return trim_blank_lines(docs)

    if lines[index].strip().startswith("/**"):
        end = index
        while end < len(lines):
            if "*/" in lines[end]:
                return parse_doc_block_lines(lines[index : end + 1])
            end += 1

    return []


def extract_zig_module_docs(lines: list[str]) -> list[str]:
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
    return trim_blank_lines(docs)


def extract_zig_decl_docs(lines: list[str], decl_line: int) -> list[str]:
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
    return trim_blank_lines(docs_rev)


def extract_doc_block_before_line(lines: list[str], decl_line: int) -> list[str]:
    cursor = decl_line - 1
    while cursor >= 0 and lines[cursor].strip() == "":
        cursor -= 1
    if cursor < 0:
        return []

    stripped = lines[cursor].lstrip()
    if stripped.startswith("///"):
        docs_rev: list[str] = []
        while cursor >= 0:
            candidate = lines[cursor].lstrip()
            if not candidate.startswith("///"):
                break
            docs_rev.append(candidate[3:].strip())
            cursor -= 1
        docs_rev.reverse()
        return trim_blank_lines(docs_rev)

    if lines[cursor].strip().endswith("*/"):
        start = cursor
        while start >= 0:
            line = lines[start].strip()
            if line.startswith("/**"):
                return parse_doc_block_lines(lines[start : cursor + 1])
            if "/*" in line and not line.startswith("/**"):
                break
            start -= 1

    return []


def parse_zig_decl_header(line: str) -> tuple[str, str] | None:
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


def parse_swift_decl_header(line: str) -> tuple[str, str] | None:
    stripped = line.strip()
    if not stripped:
        return None

    match = SWIFT_TYPE_DECL_RE.match(stripped)
    if match:
        return match.group("kind"), match.group("name")

    match = SWIFT_MEMBER_DECL_RE.match(stripped)
    if match:
        return match.group("kind"), match.group("name")

    if SWIFT_INIT_DECL_RE.match(stripped):
        return "init", "init"

    return None


def parse_kotlin_decl_header(line: str) -> tuple[str, str, bool] | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("//"):
        return None

    hidden = bool(KOTLIN_HIDDEN_MODIFIER_RE.match(stripped))
    if hidden:
        stripped = KOTLIN_HIDDEN_MODIFIER_RE.sub("", stripped, count=1).lstrip()

    match = KOTLIN_DECL_RE.match(stripped)
    if match:
        return match.group("kind"), match.group("name"), hidden
    return None


def collect_signature_until(lines: list[str], start: int, stop_tokens: tuple[str, ...]) -> str:
    signature = [lines[start].rstrip()]
    if any(token in lines[start] for token in stop_tokens):
        return "\n".join(signature).rstrip()

    cursor = start + 1
    while cursor < len(lines) and len(signature) < 24:
        signature.append(lines[cursor].rstrip())
        if any(token in lines[cursor] for token in stop_tokens):
            break
        cursor += 1
    return "\n".join(signature).rstrip()


def collect_zig_signature(lines: list[str], start: int, kind: str) -> str:
    if kind in {"fn", "export fn"} and "{" not in lines[start]:
        return collect_signature_until(lines, start, ("{",))
    return lines[start].rstrip()


def collect_swift_signature(lines: list[str], start: int, kind: str) -> str:
    if kind in {"func", "init"} and "{" not in lines[start]:
        return collect_signature_until(lines, start, ("{",))
    return lines[start].rstrip()


def collect_kotlin_signature(lines: list[str], start: int, kind: str) -> str:
    if kind in {"class", "interface", "object", "fun"} and "{" not in lines[start] and "=" not in lines[start]:
        return collect_signature_until(lines, start, ("{", "="))
    return lines[start].rstrip()


def extract_zig_declarations(lines: list[str]) -> list[Declaration]:
    declarations: list[Declaration] = []
    for index, line in enumerate(lines):
        parsed = parse_zig_decl_header(line)
        if parsed is None:
            continue
        kind, name = parsed
        declarations.append(
            Declaration(
                kind=kind,
                name=name,
                signature=collect_zig_signature(lines, index, kind),
                docs=extract_zig_decl_docs(lines, index),
            )
        )
    return declarations


def extract_swift_declarations(lines: list[str]) -> list[Declaration]:
    declarations: list[Declaration] = []
    for index, line in enumerate(lines):
        parsed = parse_swift_decl_header(line)
        if parsed is None:
            continue
        kind, name = parsed
        declarations.append(
            Declaration(
                kind=kind,
                name=name,
                signature=collect_swift_signature(lines, index, kind),
                docs=extract_doc_block_before_line(lines, index),
            )
        )
    return declarations


def extract_kotlin_declarations(lines: list[str]) -> list[Declaration]:
    declarations: list[Declaration] = []
    scope_stack: list[KotlinScope] = []

    for index, line in enumerate(lines):
        parsed = parse_kotlin_decl_header(line)
        parent_hidden = any(scope.hidden for scope in scope_stack)
        parent_kind = scope_stack[-1].kind if scope_stack else None

        declaration_kind: str | None = None
        declaration_hidden = parent_hidden
        if parsed is not None:
            kind, name, hidden = parsed
            declaration_kind = kind
            declaration_hidden = parent_hidden or hidden
            depth = len(scope_stack)
            indentation = len(line) - len(line.lstrip(" \t"))

            include = False
            if not declaration_hidden:
                if kind in {"class", "interface", "object"}:
                    include = depth == 0 or parent_kind in {"class", "object", "interface"}
                elif kind in {"fun", "val", "var"}:
                    include = (depth == 0 and indentation == 0) or depth == 1

            if include:
                declarations.append(
                    Declaration(
                        kind=kind,
                        name=name,
                        signature=collect_kotlin_signature(lines, index, kind),
                        docs=extract_doc_block_before_line(lines, index),
                    )
                )

        open_count = line.count("{")
        close_count = line.count("}")
        if open_count > 0:
            first_kind = declaration_kind if declaration_kind is not None else "other"
            first_hidden = declaration_hidden
            scope_stack.append(KotlinScope(kind=first_kind, hidden=first_hidden))
            for _ in range(open_count - 1):
                scope_stack.append(KotlinScope(kind="other", hidden=first_hidden))

        for _ in range(close_count):
            if scope_stack:
                scope_stack.pop()

    return declarations


def extract_module_docs(language: str, lines: list[str]) -> list[str]:
    if language == "zig":
        return extract_zig_module_docs(lines)
    return extract_top_doc_block(lines)


def extract_declarations(language: str, lines: list[str]) -> list[Declaration]:
    if language == "zig":
        return extract_zig_declarations(lines)
    if language == "swift":
        return extract_swift_declarations(lines)
    if language == "kotlin":
        return extract_kotlin_declarations(lines)
    raise ValueError(f"unsupported language: {language}")


def code_fence_for_language(language: str) -> str:
    if language == "zig":
        return "zig"
    if language == "swift":
        return "swift"
    if language == "kotlin":
        return "kotlin"
    return ""


def reference_output_rel_path(source: SourceFile) -> Path:
    rel = source.rel_path.with_suffix(".md")
    if source.language == "zig":
        return rel
    return Path(source.language) / rel


def render_reference_page(
    language: str,
    rel_path: Path,
    module_docs: list[str],
    declarations: list[Declaration],
) -> str:
    out: list[str] = []
    out.append(f"# `{rel_path.as_posix()}`")
    out.append("")
    out.append(f"_Language: {LANGUAGE_LABELS[language]}_")
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

    code_fence = code_fence_for_language(language)
    for decl in declarations:
        out.append(f"### `{decl.name}` ({decl.kind})")
        out.append("")
        if decl.docs:
            out.extend(decl.docs)
        else:
            out.append("No declaration docs available.")
        out.append("")
        out.append(f"```{code_fence}")
        out.append(decl.signature)
        out.append("```")
        out.append("")

    return "\n".join(out)


def render_reference_index(pages: list[GeneratedReferencePage]) -> str:
    lines = [
        "# API Reference",
        "",
        "Auto-generated from Zig, Swift, and Kotlin source comments.",
        "",
        "## Source Files",
        "",
    ]

    for language in LANGUAGE_ORDER:
        language_pages = [page for page in pages if page.language == language]
        if not language_pages:
            continue

        lines.append(f"### {LANGUAGE_LABELS[language]}")
        lines.append("")
        for page in language_pages:
            lines.append(f"- [`{page.source_rel_path.as_posix()}`]({page.output_rel_path.as_posix()})")
        lines.append("")

    return "\n".join(lines)


def generate_reference_markdown(output_dir: Path = REFERENCE_DIR) -> list[GeneratedReferencePage]:
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    pages: list[GeneratedReferencePage] = []

    for source in discover_source_files():
        lines = source.path.read_text(encoding="utf-8").splitlines()
        module_docs = extract_module_docs(source.language, lines)
        declarations = extract_declarations(source.language, lines)

        output_rel_path = reference_output_rel_path(source)
        output_path = output_dir / output_rel_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            render_reference_page(source.language, source.rel_path, module_docs, declarations),
            encoding="utf-8",
        )
        pages.append(
            GeneratedReferencePage(
                language=source.language,
                source_rel_path=source.rel_path,
                output_rel_path=output_rel_path,
            )
        )

    pages.sort(key=lambda page: (LANGUAGE_ORDER_INDEX[page.language], page.source_rel_path.as_posix()))
    (output_dir / "index.md").write_text(render_reference_index(pages), encoding="utf-8")

    return pages


def snapshot_directory(root: Path) -> dict[str, bytes]:
    snapshot: dict[str, bytes] = {}
    if not root.exists():
        return snapshot
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        if not path.is_file():
            continue
        snapshot[path.relative_to(root).as_posix()] = path.read_bytes()
    return snapshot


def describe_snapshot_diff(
    *,
    expected: dict[str, bytes],
    actual: dict[str, bytes],
    expected_label: str,
    actual_label: str,
    scope: str,
) -> list[str]:
    problems: list[str] = []
    expected_keys = set(expected.keys())
    actual_keys = set(actual.keys())

    missing = sorted(expected_keys - actual_keys)
    extra = sorted(actual_keys - expected_keys)
    changed = sorted(path for path in (expected_keys & actual_keys) if expected[path] != actual[path])

    if missing:
        problems.append(f"{scope}: missing files in {actual_label} ({len(missing)}): {', '.join(missing[:10])}")
    if extra:
        problems.append(f"{scope}: unexpected files in {actual_label} ({len(extra)}): {', '.join(extra[:10])}")
    if changed:
        problems.append(f"{scope}: changed file contents between {expected_label} and {actual_label} ({len(changed)}): {', '.join(changed[:10])}")

    return problems


def check_docs() -> None:
    with tempfile.TemporaryDirectory(prefix="wizig-docs-check-a-") as temp_a, tempfile.TemporaryDirectory(
        prefix="wizig-docs-check-b-"
    ) as temp_b:
        ref_a_dir = Path(temp_a) / "reference" / "api"
        ref_b_dir = Path(temp_b) / "reference" / "api"
        generate_reference_markdown(output_dir=ref_a_dir)
        ref_a = snapshot_directory(ref_a_dir)
        generate_reference_markdown(output_dir=ref_b_dir)
        ref_b = snapshot_directory(ref_b_dir)

    ref_current = snapshot_directory(REFERENCE_DIR)

    problems: list[str] = []
    problems.extend(
        describe_snapshot_diff(
            expected=ref_a,
            actual=ref_b,
            expected_label="temp run A",
            actual_label="temp run B",
            scope="reference determinism",
        )
    )
    problems.extend(
        describe_snapshot_diff(
            expected=ref_a,
            actual=ref_current,
            expected_label="generated output",
            actual_label=str(REFERENCE_DIR),
            scope="reference freshness",
        )
    )

    if problems:
        print("docs check failed:")
        for problem in problems:
            print(f"- {problem}")
        print("")
        print("Run `python3 scripts/docs_build.py --reference-only` to regenerate docs/reference/api/.")
        raise SystemExit(1)

    page_count = len(ref_a)
    print(f"Docs check passed: deterministic output and fresh checked-in reference docs ({page_count} files).")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Wizig API reference documentation")
    parser.add_argument(
        "--reference-only",
        action="store_true",
        help="Generate API reference markdown only (default behavior)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate deterministic output and freshness of checked-in generated reference docs",
    )
    args = parser.parse_args()

    enabled_modes = sum([args.reference_only, args.check])
    if enabled_modes > 1:
        raise SystemExit("--reference-only and --check are mutually exclusive")

    if args.check:
        check_docs()
        return

    # Default behavior: generate reference markdown
    pages = generate_reference_markdown()
    print(f"Generated {len(pages)} reference pages in {REFERENCE_DIR}")


if __name__ == "__main__":
    main()
