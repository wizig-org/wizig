#!/usr/bin/env python3
"""Generate finalized Wizig scaffold templates from in-repo seeds.

Inputs:
- templates/seeds/ios
- templates/seeds/android
- templates/spec/host_defaults.toml

Output:
- <out>/app/...
"""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[2]
_SPEC_DIR = ROOT / "templates" / "spec"
_IOS_FFI_PHASE_ID = (_SPEC_DIR / "ios_ffi_phase_id.txt").read_text(encoding="utf-8")
_IOS_FFI_SHELL_SCRIPT = (_SPEC_DIR / "ios_ffi_build.sh").read_text(encoding="utf-8")

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
    if path.suffix in TEXT_SUFFIXES:
        return True
    try:
        path.read_text(encoding="utf-8")
        return True
    except Exception:
        return False


def read_defaults() -> dict:
    spec_path = ROOT / "templates" / "spec" / "host_defaults.toml"
    return tomllib.loads(spec_path.read_text(encoding="utf-8"))


def replace_all(text: str, replacements: list[tuple[str, str]]) -> str:
    out = text
    for old, new in replacements:
        out = out.replace(old, new)
    return out


def normalize_ios_pbxproj(text: str, ios_deployment_target: str) -> str:
    text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {ios_deployment_target};", text)
    text = re.sub(r"^\s*MACOSX_DEPLOYMENT_TARGET = [^;]+;\n", "", text, flags=re.MULTILINE)
    text = re.sub(r'SUPPORTED_PLATFORMS = "[^"]+";', 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";', text)
    text = re.sub(r'TARGETED_DEVICE_FAMILY = "[^"]+";', 'TARGETED_DEVICE_FAMILY = "1,2";', text)
    text = text.replace("ENABLE_USER_SCRIPT_SANDBOXING = YES;", "ENABLE_USER_SCRIPT_SANDBOXING = NO;")
    text = text.replace("SDKROOT = auto;", "SDKROOT = iphoneos;")
    text = inject_wizig_package_reference(text)
    return text


def inject_wizig_package_reference(text: str) -> str:
    build_file_id = "D0A0A0A0A0A0A0A0A0A0A001"
    product_id = "D0A0A0A0A0A0A0A0A0A0A002"
    package_ref_id = "D0A0A0A0A0A0A0A0A0A0A003"
    shell_phase_id = _IOS_FFI_PHASE_ID

    if build_file_id not in text:
        build_file_section = (
            "/* Begin PBXBuildFile section */\n"
            f"\t\t{build_file_id} /* Wizig in Frameworks */ = {{isa = PBXBuildFile; productRef = {product_id} /* Wizig */; }};\n"
            "/* End PBXBuildFile section */\n\n"
        )
        text = text.replace("/* Begin PBXContainerItemProxy section */\n", build_file_section + "/* Begin PBXContainerItemProxy section */\n", 1)

    if f"\t\t\t\t{build_file_id} /* Wizig in Frameworks */,\n" not in text:
        text = text.replace(
            "\t\tAB2597A02F532F6600C45779 /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
            "\t\tAB2597A02F532F6600C45779 /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
            f"\t\t\t\t{build_file_id} /* Wizig in Frameworks */,\n"
            "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
            1,
        )

    if f"\t\t\t\t{product_id} /* Wizig */,\n" not in text:
        text = text.replace(
            "\t\t\tpackageProductDependencies = (\n\t\t\t);\n",
            "\t\t\tpackageProductDependencies = (\n"
            f"\t\t\t\t{product_id} /* Wizig */,\n"
            "\t\t\t);\n",
            1,
        )

    if f"\t\t\t\t{package_ref_id} /* XCLocalSwiftPackageReference \"../.wizig/sdk/ios\" */,\n" not in text:
        text = text.replace(
            "\t\t\tminimizedProjectReferenceProxies = 1;\n",
            "\t\t\tminimizedProjectReferenceProxies = 1;\n"
            "\t\t\tpackageReferences = (\n"
            f"\t\t\t\t{package_ref_id} /* XCLocalSwiftPackageReference \"../.wizig/sdk/ios\" */,\n"
            "\t\t\t);\n",
            1,
        )

    if "XCLocalSwiftPackageReference section" not in text:
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

    if f"\t\t\t\t{shell_phase_id} /* Wizig FFI Build */,\n" not in text:
        text = text.replace(
            "\t\t\tbuildPhases = (\n\t\t\t\tAB25979F2F532F6600C45779 /* Sources */,\n\t\t\t\tAB2597A02F532F6600C45779 /* Frameworks */,\n\t\t\t\tAB2597A12F532F6600C45779 /* Resources */,\n\t\t\t);\n",
            "\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{shell_phase_id} /* Wizig FFI Build */,\n"
            "\t\t\t\tAB25979F2F532F6600C45779 /* Sources */,\n"
            "\t\t\t\tAB2597A02F532F6600C45779 /* Frameworks */,\n\t\t\t\tAB2597A12F532F6600C45779 /* Resources */,\n\t\t\t);\n",
            1,
        )

    if f"\t\t{shell_phase_id} /* Wizig FFI Build */ = {{\n" not in text:
        encoded = _IOS_FFI_SHELL_SCRIPT.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
        shell_section = (
            "/* Begin PBXShellScriptBuildPhase section */\n"
            f"\t\t{shell_phase_id} /* Wizig FFI Build */ = {{\n"
            "\t\t\tisa = PBXShellScriptBuildPhase;\n"
            "\t\t\talwaysOutOfDate = 1;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n"
            "\t\t\t);\n"
            "\t\t\tinputFileListPaths = (\n"
            "\t\t\t);\n"
            "\t\t\tinputPaths = (\n"
            "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/zig/WizigGeneratedFfiRoot.zig\",\n"
            "\t\t\t\t\"$(SRCROOT)/../.wizig/runtime/core/src/root.zig\",\n"
            "\t\t\t\t\"$(SRCROOT)/../lib/WizigGeneratedAppModule.zig\",\n"
            "\t\t\t);\n"
            "\t\t\tname = \"Wizig FFI Build\";\n"
            "\t\t\toutputFileListPaths = (\n"
            "\t\t\t);\n"
            "\t\t\toutputPaths = (\n"
            "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/Frameworks/wizigffi\",\n"
            "\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t\tshellPath = /bin/sh;\n"
            f"\t\t\tshellScript = \"{encoded}\";\n"
            "\t\t};\n"
            "/* End PBXShellScriptBuildPhase section */\n\n"
        )
        text = text.replace("/* Begin PBXSourcesBuildPhase section */\n", shell_section + "/* Begin PBXSourcesBuildPhase section */\n", 1)

    return text


def write_ios_swift_sources(app_sources_dir: Path) -> None:
    app_file = app_sources_dir / f"{IOS_APP_PATH_SEGMENT}App.swift"
    content_file = app_sources_dir / "ContentView.swift"
    item_file = app_sources_dir / "Item.swift"
    generated_dir = app_sources_dir / "Generated"

    app_file.write_text(
        """import SwiftUI\nimport Wizig\n\n@main\nstruct {{APP_TYPE_NAME}}App: App {\n    @State private var message: String = \"Loading runtime...\"\n    private let api = try? WizigGeneratedApi()\n\n    var body: some Scene {\n        WindowGroup {\n            ContentView(message: message, runtimeAvailable: api != nil)\n                .task {\n                    guard let api else {\n                        message = \"Wizig runtime unavailable\"\n                        return\n                    }\n                    message = (try? api.echo(\"hello\")) ?? \"Wizig runtime unavailable\"\n                }\n        }\n    }\n}\n""",
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


def android_package_path(package_name: str) -> str:
    return package_name.replace(".", "/")


def write_android_gradle_files(out_android_dir: Path, defaults: dict) -> None:
    compile_sdk = defaults["host"]["android_compile_sdk"]
    min_sdk = defaults["host"]["android_min_sdk"]
    target_sdk = defaults["host"]["android_target_sdk"]
    java_version = defaults["host"]["android_java_version"]
    kotlin_target = defaults["host"]["android_kotlin_jvm_target"]

    (out_android_dir / "build.gradle.kts").write_text(
        """// Top-level build file where you can add configuration options common to all sub-projects/modules.\nplugins {\n    alias(libs.plugins.android.application) apply false\n    alias(libs.plugins.kotlin.compose) apply false\n}\n""",
        encoding="utf-8",
    )

    (out_android_dir / "settings.gradle.kts").write_text(
        """pluginManagement {\n    repositories {\n        google {\n            content {\n                includeGroupByRegex(\"com\\\\.android.*\")\n                includeGroupByRegex(\"com\\\\.google.*\")\n                includeGroupByRegex(\"androidx.*\")\n            }\n        }\n        mavenCentral()\n        gradlePluginPortal()\n    }\n}\ndependencyResolutionManagement {\n    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)\n    repositories {\n        google()\n        mavenCentral()\n    }\n}\n\nrootProject.name = \"{{APP_NAME}}\"\ninclude(\":app\")\n""",
        encoding="utf-8",
    )

    (out_android_dir / "gradle" / "libs.versions.toml").write_text(
        """[versions]\nagp = \"9.0.1\"\nkotlin = \"2.0.21\"\nandroidx-core-ktx = \"1.10.1\"\nandroidx-lifecycle-runtime-ktx = \"2.6.1\"\nandroidx-activity-compose = \"1.8.0\"\nandroidx-compose-bom = \"2024.09.00\"\njunit = \"4.13.2\"\nandroidx-junit = \"1.1.5\"\nespresso-core = \"3.5.1\"\n\n[libraries]\nandroidx-core-ktx = { group = \"androidx.core\", name = \"core-ktx\", version.ref = \"androidx-core-ktx\" }\nandroidx-lifecycle-runtime-ktx = { group = \"androidx.lifecycle\", name = \"lifecycle-runtime-ktx\", version.ref = \"androidx-lifecycle-runtime-ktx\" }\nandroidx-activity-compose = { group = \"androidx.activity\", name = \"activity-compose\", version.ref = \"androidx-activity-compose\" }\nandroidx-compose-bom = { group = \"androidx.compose\", name = \"compose-bom\", version.ref = \"androidx-compose-bom\" }\nandroidx-compose-ui = { group = \"androidx.compose.ui\", name = \"ui\" }\nandroidx-compose-ui-graphics = { group = \"androidx.compose.ui\", name = \"ui-graphics\" }\nandroidx-compose-ui-tooling = { group = \"androidx.compose.ui\", name = \"ui-tooling\" }\nandroidx-compose-ui-tooling-preview = { group = \"androidx.compose.ui\", name = \"ui-tooling-preview\" }\nandroidx-compose-ui-test-manifest = { group = \"androidx.compose.ui\", name = \"ui-test-manifest\" }\nandroidx-compose-ui-test-junit4 = { group = \"androidx.compose.ui\", name = \"ui-test-junit4\" }\nandroidx-compose-material3 = { group = \"androidx.compose.material3\", name = \"material3\" }\njunit = { group = \"junit\", name = \"junit\", version.ref = \"junit\" }\nandroidx-junit = { group = \"androidx.test.ext\", name = \"junit\", version.ref = \"androidx-junit\" }\nandroidx-espresso-core = { group = \"androidx.test.espresso\", name = \"espresso-core\", version.ref = \"espresso-core\" }\n\n[plugins]\nandroid-application = { id = \"com.android.application\", version.ref = \"agp\" }\nkotlin-compose = { id = \"org.jetbrains.kotlin.plugin.compose\", version.ref = \"kotlin\" }\n""",
        encoding="utf-8",
    )

    (out_android_dir / "app" / "build.gradle.kts").write_text(
        f"""plugins {{\n    alias(libs.plugins.android.application)\n    alias(libs.plugins.kotlin.compose)\n}}\n\nandroid {{\n    namespace = \"{ANDROID_PACKAGE_TOKEN}\"\n    compileSdk = {compile_sdk}\n\n    defaultConfig {{\n        applicationId = \"{ANDROID_PACKAGE_TOKEN}\"\n        minSdk = {min_sdk}\n        targetSdk = {target_sdk}\n        versionCode = 1\n        versionName = \"1.0\"\n        testInstrumentationRunner = \"androidx.test.runner.AndroidJUnitRunner\"\n    }}\n\n    buildTypes {{\n        release {{\n            isMinifyEnabled = false\n            proguardFiles(\n                getDefaultProguardFile(\"proguard-android-optimize.txt\"),\n                \"proguard-rules.pro\"\n            )\n        }}\n    }}\n\n    compileOptions {{\n        sourceCompatibility = JavaVersion.VERSION_{java_version}\n        targetCompatibility = JavaVersion.VERSION_{java_version}\n    }}\n\n    buildFeatures {{\n        compose = true\n    }}\n\n    externalNativeBuild {{\n        cmake {{\n            path = rootProject.file(\"../.wizig/generated/android/jni/CMakeLists.txt\")\n        }}\n    }}\n\n    sourceSets {{\n        getByName(\"main\") {{\n            kotlin.srcDir(rootProject.file(\"../.wizig/sdk/android/src/main/kotlin\"))\n            jniLibs.srcDir(rootProject.file(\"../.wizig/generated/android/jniLibs\"))\n        }}\n    }}\n\n    packaging {{\n        resources {{\n            excludes += \"/META-INF/{{AL2.0,LGPL2.1}}\"\n        }}\n    }}\n}}\n\nkotlin {{\n    jvmToolchain({kotlin_target})\n}}\n\nfun registerWizigFfiTask(taskName: String, abi: String, zigTarget: String) = tasks.register<Exec>(taskName) {{\n    val appRoot = rootProject.file(\"..\")\n    val outDir = appRoot.resolve(\".wizig/generated/android/jniLibs/$abi\")\n    val generatedRoot = appRoot.resolve(\".wizig/generated/zig\")\n    val runtimeRoot = appRoot.resolve(\".wizig/runtime\")\n    val libRoot = appRoot.resolve(\"lib\")\n    doFirst {{\n        outDir.mkdirs()\n    }}\n    commandLine(\n        \"zig\",\n        \"build-lib\",\n        \"-OReleaseFast\",\n        \"-target\",\n        zigTarget,\n        \"--dep\",\n        \"wizig_core\",\n        \"--dep\",\n        \"wizig_app\",\n        \"-Mroot=${{generatedRoot.path}}/WizigGeneratedFfiRoot.zig\",\n        \"-Mwizig_core=${{runtimeRoot.path}}/core/src/root.zig\",\n        \"-Mwizig_app=${{libRoot.path}}/WizigGeneratedAppModule.zig\",\n        \"--name\",\n        \"wizigffi\",\n        \"-dynamic\",\n        \"-fstrip\",\n        \"-femit-bin=${{outDir.path}}/libwizigffi.so\",\n    )\n}}\n\nval buildWizigFfiArm64 = registerWizigFfiTask(\"buildWizigFfiArm64V8a\", \"arm64-v8a\", \"aarch64-linux-android\")\nval buildWizigFfiArmV7 = registerWizigFfiTask(\"buildWizigFfiArmeabiV7a\", \"armeabi-v7a\", \"arm-linux-androideabi\")\nval buildWizigFfiX64 = registerWizigFfiTask(\"buildWizigFfiX8664\", \"x86_64\", \"x86_64-linux-android\")\nval buildWizigFfiX86 = registerWizigFfiTask(\"buildWizigFfiX86\", \"x86\", \"x86-linux-android\")\n\ntasks.matching {{ it.name.startsWith(\"configureCMake\") || it.name.startsWith(\"buildCMake\") }}.configureEach {{\n    dependsOn(buildWizigFfiArm64, buildWizigFfiArmV7, buildWizigFfiX64, buildWizigFfiX86)\n}}\n\ndependencies {{\n    implementation(libs.androidx.core.ktx)\n    implementation(libs.androidx.lifecycle.runtime.ktx)\n    implementation(libs.androidx.activity.compose)\n    implementation(platform(libs.androidx.compose.bom))\n    implementation(libs.androidx.compose.ui)\n    implementation(libs.androidx.compose.ui.graphics)\n    implementation(libs.androidx.compose.ui.tooling.preview)\n    implementation(libs.androidx.compose.material3)\n    implementation(\"net.java.dev.jna:jna:5.14.0\")\n\n    testImplementation(libs.junit)\n    androidTestImplementation(libs.androidx.junit)\n    androidTestImplementation(libs.androidx.espresso.core)\n    androidTestImplementation(platform(libs.androidx.compose.bom))\n    androidTestImplementation(libs.androidx.compose.ui.test.junit4)\n\n    debugImplementation(libs.androidx.compose.ui.tooling)\n    debugImplementation(libs.androidx.compose.ui.test.manifest)\n}}\n""",
        encoding="utf-8",
    )


def write_android_sources(out_android_dir: Path) -> None:
    pkg_path = out_android_dir / "app" / "src" / "main" / "java" / ANDROID_PACKAGE_PATH_SEGMENT
    theme_dir = pkg_path / "ui" / "theme"
    pkg_path.mkdir(parents=True, exist_ok=True)
    theme_dir.mkdir(parents=True, exist_ok=True)
    (pkg_path / "MainActivity.kt").write_text(
        f"""package {ANDROID_PACKAGE_TOKEN}

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.wizig.WizigGeneratedApi
import {ANDROID_PACKAGE_TOKEN}.ui.theme.{APP_TYPE_TOKEN}Theme

class MainActivity : ComponentActivity() {{
    override fun onCreate(savedInstanceState: Bundle?) {{
        super.onCreate(savedInstanceState)
        val api = runCatching {{ WizigGeneratedApi() }}.getOrNull()
        val message = api?.let {{ runCatching {{ it.echo(\"hello\") }}.getOrNull() }} ?: \"Wizig runtime unavailable\"

        enableEdgeToEdge()
        setContent {{
            {APP_TYPE_TOKEN}Theme {{
                Scaffold(modifier = Modifier.fillMaxSize()) {{ innerPadding ->
                    Greeting(
                        name = message,
                        modifier = Modifier.padding(innerPadding)
                    )
                }}
            }}
        }}
    }}
}}

@Composable
private fun Greeting(name: String, modifier: Modifier = Modifier) {{
    Text(
        text = name,
        modifier = modifier
    )
}}

@Preview(showBackground = true)
@Composable
private fun GreetingPreview() {{
    {APP_TYPE_TOKEN}Theme {{
        Greeting(\"{APP_TOKEN}\")
    }}
}}
""",
        encoding="utf-8",
    )


    (theme_dir / "Color.kt").write_text(
        f"""package {ANDROID_PACKAGE_TOKEN}.ui.theme\n\nimport androidx.compose.ui.graphics.Color\n\nval Purple80 = Color(0xFFD0BCFF)\nval PurpleGrey80 = Color(0xFFCCC2DC)\nval Pink80 = Color(0xFFEFB8C8)\n\nval Purple40 = Color(0xFF6650A4)\nval PurpleGrey40 = Color(0xFF625B71)\nval Pink40 = Color(0xFF7D5260)\n""",
        encoding="utf-8",
    )

    (theme_dir / "Type.kt").write_text(
        f"""package {ANDROID_PACKAGE_TOKEN}.ui.theme\n\nimport androidx.compose.material3.Typography\n\nval Typography = Typography()\n""",
        encoding="utf-8",
    )

    (theme_dir / "Theme.kt").write_text(
        f"""package {ANDROID_PACKAGE_TOKEN}.ui.theme\n\nimport android.os.Build\nimport androidx.compose.foundation.isSystemInDarkTheme\nimport androidx.compose.material3.MaterialTheme\nimport androidx.compose.material3.darkColorScheme\nimport androidx.compose.material3.dynamicDarkColorScheme\nimport androidx.compose.material3.dynamicLightColorScheme\nimport androidx.compose.material3.lightColorScheme\nimport androidx.compose.runtime.Composable\nimport androidx.compose.ui.platform.LocalContext\n\nprivate val DarkColorScheme = darkColorScheme(\n    primary = Purple80,\n    secondary = PurpleGrey80,\n    tertiary = Pink80\n)\n\nprivate val LightColorScheme = lightColorScheme(\n    primary = Purple40,\n    secondary = PurpleGrey40,\n    tertiary = Pink40\n)\n\n@Composable\nfun {APP_TYPE_TOKEN}Theme(\n    darkTheme: Boolean = isSystemInDarkTheme(),\n    dynamicColor: Boolean = true,\n    content: @Composable () -> Unit\n) {{\n    val colorScheme = when {{\n        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {{\n            val context = LocalContext.current\n            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)\n        }}\n\n        darkTheme -> DarkColorScheme\n        else -> LightColorScheme\n    }}\n\n    MaterialTheme(\n        colorScheme = colorScheme,\n        typography = Typography,\n        content = content\n    )\n}}\n""",
        encoding="utf-8",
    )


def generate_android(seeds_root: Path, out_android_dir: Path, defaults: dict) -> None:
    android_seed = seeds_root / "android"
    if not android_seed.exists():
        raise RuntimeError(f"Android seed missing: {android_seed}")

    if out_android_dir.exists():
        shutil.rmtree(out_android_dir)
    out_android_dir.mkdir(parents=True, exist_ok=True)

    seed_package = defaults["seeds"]["android_package"]
    seed_pkg_path = seed_package.replace(".", "/")

    for src_path in sorted(android_seed.rglob("*")):
        rel = src_path.relative_to(android_seed)

        if rel.name == "local.properties":
            continue
        if ".idea" in rel.parts or ".gradle" in rel.parts:
            continue
        if rel.as_posix() == "gradle/gradle-daemon-jvm.properties":
            continue

        rel_text = rel.as_posix().replace(seed_pkg_path, ANDROID_PACKAGE_PATH_SEGMENT)
        dst_path = out_android_dir / rel_text

        if src_path.is_dir():
            dst_path.mkdir(parents=True, exist_ok=True)
            continue

        dst_path.parent.mkdir(parents=True, exist_ok=True)
        if is_text_file(src_path):
            text = src_path.read_text(encoding="utf-8")
            text = text.replace(seed_package, ANDROID_PACKAGE_TOKEN)
            text = text.replace("Theme.WizigTemplateAndroid", f"Theme.{APP_TYPE_TOKEN}")
            text = text.replace("WizigTemplateAndroid", APP_TOKEN)
            dst_path.write_text(text, encoding="utf-8")
        else:
            shutil.copy2(src_path, dst_path)

    write_android_gradle_files(out_android_dir, defaults)
    write_android_sources(out_android_dir)


def main() -> int:
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
    generate_android(seeds_root, out_app / "android", defaults)

    # Legacy xcodegen scaffold is intentionally removed.
    project_yml = out_app / "ios" / "project.yml"
    if project_yml.exists():
        project_yml.unlink()

    print(f"generated templates at {out_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
