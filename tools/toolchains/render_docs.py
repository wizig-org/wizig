#!/usr/bin/env python3
"""Render toolchain-governance documentation from `toolchains.toml`.

This script keeps checked-in developer requirements docs synchronized with the
central toolchain policy manifest so version drift is caught early.
"""

from __future__ import annotations

import argparse
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[2]
TOOLCHAINS_PATH = ROOT / "toolchains.toml"
DOC_TARGETS = [
    ROOT / "docs" / "getting-started" / "development-requirements.md",
]


def load_toolchains() -> dict:
    """Load and parse the central toolchain manifest."""
    return tomllib.loads(TOOLCHAINS_PATH.read_text(encoding="utf-8"))


def render_markdown(manifest: dict) -> str:
    """Render the canonical development requirements markdown document."""
    doctor_tools = manifest["doctor"]["tools"]
    android = manifest["templates"]["android"]
    ios = manifest["templates"]["ios"]
    wrapper = android["gradle_wrapper"]
    docs = manifest["docs"]

    gradle_wrapper_version = str(wrapper["version"])
    python_min = str(docs["python_min"])

    return (
        "# Development Requirements\n\n"
        "## Core Toolchains\n\n"
        "Wizig framework development requires:\n\n"
        f"- Zig `{doctor_tools['zig']['min_version']}`\n"
        f"- Xcode `{doctor_tools['xcodebuild']['min_version'].split('.')[0]}+` and Apple CLT (`xcodebuild`, `xcrun`)\n"
        "- XcodeGen (optional for legacy regeneration flows)\n"
        f"- Java `{doctor_tools['java']['min_version'].split('.')[0]}`\n"
        f"- Gradle `{doctor_tools['gradle']['min_version']}`\n"
        "- Android SDK tools (`adb`, emulator, platform SDKs)\n"
        f"- Python `{python_min}+` for docs tooling\n\n"
        "## Homebrew Baseline\n\n"
        "```sh\n"
        "brew install gradle openjdk@21 xcodegen python\n"
        "brew install --cask android-platform-tools android-commandlinetools\n"
        "```\n\n"
        "## Android Notes\n\n"
        f"- App scaffolds pin Gradle wrapper `{gradle_wrapper_version}`.\n"
        f"- Android host defaults: `compileSdk {android['compile_sdk']}`, `minSdk {android['min_sdk']}`, `targetSdk {android['target_sdk']}`.\n"
        "- Kotlin/Compose versions are managed by generated version catalog.\n"
        "- Generated host bindings are sourced from `.wizig/generated/kotlin`.\n\n"
        "## iOS Notes\n\n"
        "- iOS scaffolds are generated from bundled Xcode project templates (no runtime IDE tooling dependency).\n"
        f"- Minimum deployment target is currently `{ios['deployment_target']}`.\n"
        "- Generated host bindings are sourced from `.wizig/generated/swift`.\n\n"
        "## Docs Tooling\n\n"
        "Install documentation dependencies:\n\n"
        "```sh\n"
        "pip install -r docs/requirements.txt\n"
        "```\n\n"
        "Build docs:\n\n"
        "```sh\n"
        "zig build docs\n"
        "```\n\n"
        "Serve docs locally for preview:\n\n"
        "```sh\n"
        "mkdocs serve\n"
        "```\n"
    )


def write_or_check(content: str, check: bool) -> int:
    """Write docs or validate that checked-in docs already match."""
    mismatches: list[str] = []
    for target in DOC_TARGETS:
        existing = target.read_text(encoding="utf-8") if target.exists() else ""
        if existing != content:
            if check:
                mismatches.append(str(target))
                continue
            target.write_text(content, encoding="utf-8")

    if mismatches:
        print("toolchain docs are out of date:")
        for item in mismatches:
            print(f"- {item}")
        return 1
    return 0


def main() -> int:
    """CLI entrypoint for docs rendering/check mode."""
    parser = argparse.ArgumentParser(description="Render docs from toolchains.toml")
    parser.add_argument("--check", action="store_true", help="Fail if docs are not synchronized")
    args = parser.parse_args()

    manifest = load_toolchains()
    rendered = render_markdown(manifest)
    return write_or_check(rendered, args.check)


if __name__ == "__main__":
    raise SystemExit(main())
