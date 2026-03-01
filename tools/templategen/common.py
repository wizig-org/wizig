#!/usr/bin/env python3
"""Shared helpers and manifest access for template generation.

This module centralizes token constants, text-file detection, and loading of
`host_defaults.toml` plus `toolchains.toml` so platform generators consume a
single policy input model.
"""

from __future__ import annotations

from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[2]
APP_TOKEN = "{{APP_NAME}}"
APP_IDENTIFIER_TOKEN = "{{APP_IDENTIFIER}}"
APP_TYPE_TOKEN = "{{APP_TYPE_NAME}}"
ANDROID_PACKAGE_TOKEN = "{{ANDROID_PACKAGE}}"
ANDROID_PACKAGE_PATH_SEGMENT = "__ANDROID_PACKAGE_PATH__"
IOS_APP_PATH_SEGMENT = "__APP_NAME__"

TEXT_SUFFIXES = {
    ".swift",
    ".pbxproj",
    ".plist",
    ".xcworkspacedata",
    ".json",
    ".txt",
    ".md",
    ".yml",
    ".yaml",
    ".kts",
    ".gradle",
    ".xml",
    ".pro",
    ".properties",
    ".gitignore",
    ".toml",
}


def is_text_file(path: Path) -> bool:
    """Best-effort text/binary detection for template seed files."""
    if path.suffix in TEXT_SUFFIXES:
        return True
    try:
        path.read_text(encoding="utf-8")
        return True
    except Exception:
        return False


def read_toolchains() -> dict:
    """Load centralized toolchain policy values from `toolchains.toml`."""
    manifest_path = ROOT / "toolchains.toml"
    return tomllib.loads(manifest_path.read_text(encoding="utf-8"))


def read_defaults() -> dict:
    """Load defaults and derive host values from the toolchains manifest."""
    spec_path = ROOT / "templates" / "spec" / "host_defaults.toml"
    defaults = tomllib.loads(spec_path.read_text(encoding="utf-8"))
    toolchains = read_toolchains()
    defaults["host"] = {
        "ios_deployment_target": str(toolchains["templates"]["ios"]["deployment_target"]),
        "android_compile_sdk": int(toolchains["templates"]["android"]["compile_sdk"]),
        "android_min_sdk": int(toolchains["templates"]["android"]["min_sdk"]),
        "android_target_sdk": int(toolchains["templates"]["android"]["target_sdk"]),
        "android_java_version": int(toolchains["templates"]["android"]["java_version"]),
        "android_kotlin_jvm_target": str(toolchains["templates"]["android"]["kotlin_jvm_target"]),
    }
    return defaults


def replace_all(text: str, replacements: list[tuple[str, str]]) -> str:
    """Apply replacement tuples in declaration order."""
    out = text
    for old, new in replacements:
        out = out.replace(old, new)
    return out
