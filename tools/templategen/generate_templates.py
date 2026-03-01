#!/usr/bin/env python3
"""Generate finalized Wizig scaffold templates from in-repo seeds.

Inputs:
- templates/seeds/ios
- templates/seeds/android
- templates/spec/host_defaults.toml
- toolchains.toml

Output:
- <out>/app/...
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from android_generator import generate_android
from common import ROOT, read_defaults, read_toolchains
from ios_generator import generate_ios


def main() -> int:
    """Render app templates using centralized defaults and toolchain policy."""
    parser = argparse.ArgumentParser(description="Generate finalized Wizig templates from seeds")
    parser.add_argument(
        "--out",
        default=str(ROOT / "build" / "generated" / "templates"),
        help="Output templates directory",
    )
    args = parser.parse_args()

    out_root = Path(args.out).resolve()
    seeds_root = ROOT / "templates" / "seeds"
    app_source_root = ROOT / "templates" / "app"

    defaults = read_defaults()
    toolchains = read_toolchains()

    if out_root.exists():
        shutil.rmtree(out_root)
    out_root.mkdir(parents=True, exist_ok=True)

    out_app = out_root / "app"
    shutil.copytree(app_source_root, out_app)

    # Host templates are fully generated from seeds/spec.
    for host_dir in (out_app / "ios", out_app / "android"):
        if host_dir.exists():
            shutil.rmtree(host_dir)

    generate_ios(seeds_root, out_app / "ios", defaults)
    generate_android(seeds_root, out_app / "android", defaults, toolchains)

    # Legacy xcodegen scaffold is intentionally removed.
    project_yml = out_app / "ios" / "project.yml"
    if project_yml.exists():
        project_yml.unlink()

    print(f"generated templates at {out_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
