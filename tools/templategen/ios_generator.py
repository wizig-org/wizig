#!/usr/bin/env python3
"""iOS template generation from seed projects.

This module applies file/path token replacement, normalizes Xcode project
settings from centralized defaults, and writes generated Swift entry sources.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

from common import (
    APP_IDENTIFIER_TOKEN,
    APP_TOKEN,
    IOS_APP_PATH_SEGMENT,
    is_text_file,
    replace_all,
)


def normalize_ios_pbxproj(text: str, ios_deployment_target: str) -> str:
    """Normalize key build settings and inject local Wizig package linkage."""
    text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {ios_deployment_target};", text)
    text = re.sub(r"^\s*MACOSX_DEPLOYMENT_TARGET = [^;]+;\n", "", text, flags=re.MULTILINE)
    text = re.sub(r'SUPPORTED_PLATFORMS = "[^"]+";', 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";', text)
    text = re.sub(r'TARGETED_DEVICE_FAMILY = "[^"]+";', 'TARGETED_DEVICE_FAMILY = "1,2";', text)
    text = text.replace("SDKROOT = auto;", "SDKROOT = iphoneos;")
    text = inject_wizig_package_reference(text)
    return text


def inject_wizig_package_reference(text: str) -> str:
    """Inject local Swift package references if not already present."""
    if "XCLocalSwiftPackageReference" in text and "Wizig */ = {isa = XCSwiftPackageProductDependency;" in text:
        return text

    build_file_id = "D0A0A0A0A0A0A0A0A0A0A001"
    product_id = "D0A0A0A0A0A0A0A0A0A0A002"
    package_ref_id = "D0A0A0A0A0A0A0A0A0A0A003"

    build_file_section = (
        "/* Begin PBXBuildFile section */\n"
        f"\t\t{build_file_id} /* Wizig in Frameworks */ = {{isa = PBXBuildFile; productRef = {product_id} /* Wizig */; }};\n"
        "/* End PBXBuildFile section */\n\n"
    )
    text = text.replace("/* Begin PBXContainerItemProxy section */\n", build_file_section + "/* Begin PBXContainerItemProxy section */\n", 1)

    text = text.replace(
        "\t\tAB2597A02F532F6600C45779 /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
        "\t\tAB2597A02F532F6600C45779 /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
        f"\t\t\t\t{build_file_id} /* Wizig in Frameworks */,\n"
        "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
        1,
    )

    text = text.replace(
        "\t\t\tpackageProductDependencies = (\n\t\t\t);\n",
        "\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{product_id} /* Wizig */,\n"
        "\t\t\t);\n",
        1,
    )

    text = text.replace(
        "\t\t\tminimizedProjectReferenceProxies = 1;\n",
        "\t\t\tminimizedProjectReferenceProxies = 1;\n"
        "\t\t\tpackageReferences = (\n"
        f"\t\t\t\t{package_ref_id} /* XCLocalSwiftPackageReference \"../.wizig/sdk/ios\" */,\n"
        "\t\t\t);\n",
        1,
    )

    package_sections = (
        "/* Begin XCLocalSwiftPackageReference section */\n"
        f"\t\t{package_ref_id} /* XCLocalSwiftPackageReference \"../.wizig/sdk/ios\" */ = {{\n"
        "\t\t\tisa = XCLocalSwiftPackageReference;\n"
        "\t\t\trelativePath = ../.wizig/sdk/ios;\n"
        "\t\t};\n"
        "/* End XCLocalSwiftPackageReference section */\n\n"
        "/* Begin XCSwiftPackageProductDependency section */\n"
        f"\t\t{product_id} /* Wizig */ = {{\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tproductName = Wizig;\n"
        "\t\t};\n"
        "/* End XCSwiftPackageProductDependency section */\n\n"
    )
    text = text.replace("/* Begin XCConfigurationList section */\n", package_sections + "/* Begin XCConfigurationList section */\n", 1)

    return text


def write_ios_swift_sources(app_sources_dir: Path) -> None:
    """Replace seed app sources with deterministic Wizig runtime bootstrap."""
    app_file = app_sources_dir / f"{IOS_APP_PATH_SEGMENT}App.swift"
    content_file = app_sources_dir / "ContentView.swift"
    item_file = app_sources_dir / "Item.swift"
    generated_dir = app_sources_dir / "Generated"

    app_file.write_text(
        """import SwiftUI\nimport Wizig\n\n@main\nstruct {{APP_TYPE_NAME}}App: App {\n    @State private var message: String = \"Loading runtime...\"\n    private let runtime = WizigRuntime(appName: \"{{APP_NAME}}\")\n    private let api = try? WizigGeneratedApi()\n\n    var body: some Scene {\n        WindowGroup {\n            ContentView(message: message, runtimeAvailable: runtime.isAvailable)\n                .task {\n                    guard let api else {\n                        message = \"Wizig runtime unavailable\"\n                        return\n                    }\n                    message = (try? api.echo(\"hello\")) ?? \"Wizig runtime unavailable\"\n                }\n        }\n    }\n}\n""",
        encoding="utf-8",
    )

    content_file.write_text(
        """import SwiftUI\n\nstruct ContentView: View {\n    let message: String\n    let runtimeAvailable: Bool\n\n    var body: some View {\n        VStack(alignment: .leading, spacing: 12) {\n            Text(\"{{APP_NAME}}\")\n                .font(.title2.bold())\n            Text(\"Runtime available: \\(runtimeAvailable ? \"yes\" : \"no\")\")\n                .foregroundStyle(.secondary)\n            Text(\"Wizig runtime response\")\n                .foregroundStyle(.secondary)\n            Text(message)\n                .font(.caption)\n                .foregroundStyle(.secondary)\n        }\n        .padding(24)\n    }\n}\n\n#Preview {\n    ContentView(message: \"Preview\", runtimeAvailable: true)\n}\n""",
        encoding="utf-8",
    )

    if item_file.exists():
        item_file.unlink()
    generated_dir.mkdir(parents=True, exist_ok=True)


def generate_ios(seeds_root: Path, out_ios_dir: Path, defaults: dict) -> None:
    """Generate iOS template output tree from `templates/seeds/ios`."""
    ios_seed = seeds_root / "ios"
    xcodeproj = next(ios_seed.glob("*.xcodeproj"), None)
    if xcodeproj is None:
        raise RuntimeError(f"iOS seed missing .xcodeproj in {ios_seed}")

    base_name = xcodeproj.stem
    test_name = f"{base_name}Tests"
    ui_test_name = f"{base_name}UITests"

    replacements = [
        (ui_test_name, f"{APP_TOKEN}UITests"),
        (test_name, f"{APP_TOKEN}Tests"),
        (base_name, APP_TOKEN),
        (base_name.lower(), APP_IDENTIFIER_TOKEN),
    ]

    if out_ios_dir.exists():
        shutil.rmtree(out_ios_dir)
    out_ios_dir.mkdir(parents=True, exist_ok=True)

    ios_target = defaults["host"]["ios_deployment_target"]

    for src_path in sorted(ios_seed.rglob("*")):
        rel = src_path.relative_to(ios_seed)

        rel_text = rel.as_posix()
        rel_text = rel_text.replace(f"{base_name}.xcodeproj", f"{IOS_APP_PATH_SEGMENT}.xcodeproj")
        rel_text = rel_text.replace(ui_test_name, f"{IOS_APP_PATH_SEGMENT}UITests")
        rel_text = rel_text.replace(test_name, f"{IOS_APP_PATH_SEGMENT}Tests")
        rel_text = rel_text.replace(base_name, IOS_APP_PATH_SEGMENT)

        dst_path = out_ios_dir / rel_text

        if src_path.is_dir():
            dst_path.mkdir(parents=True, exist_ok=True)
            continue

        dst_path.parent.mkdir(parents=True, exist_ok=True)
        if is_text_file(src_path):
            text = src_path.read_text(encoding="utf-8")
            text = replace_all(text, replacements)
            if dst_path.name == "project.pbxproj":
                text = normalize_ios_pbxproj(text, ios_target)
            dst_path.write_text(text, encoding="utf-8")
        else:
            shutil.copy2(src_path, dst_path)

    app_sources_dir = out_ios_dir / IOS_APP_PATH_SEGMENT
    write_ios_swift_sources(app_sources_dir)
