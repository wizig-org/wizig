#!/usr/bin/env python3
"""Android template generation from seed projects.

This module renders Android scaffold files, applies centralized version policy
from toolchains manifest values, and writes source/theme boilerplate used by
created projects.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

from common import (
    ANDROID_PACKAGE_PATH_SEGMENT,
    ANDROID_PACKAGE_TOKEN,
    APP_TOKEN,
    APP_TYPE_TOKEN,
    is_text_file,
)


def write_android_gradle_files(out_android_dir: Path, defaults: dict) -> None:
    """Write baseline Gradle project files with SDK/JVM values from defaults."""
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
        f"""plugins {{\n    alias(libs.plugins.android.application)\n    alias(libs.plugins.kotlin.compose)\n}}\n\nandroid {{\n    namespace = \"{ANDROID_PACKAGE_TOKEN}\"\n    compileSdk = {compile_sdk}\n\n    defaultConfig {{\n        applicationId = \"{ANDROID_PACKAGE_TOKEN}\"\n        minSdk = {min_sdk}\n        targetSdk = {target_sdk}\n        versionCode = 1\n        versionName = \"1.0\"\n        testInstrumentationRunner = \"androidx.test.runner.AndroidJUnitRunner\"\n    }}\n\n    buildTypes {{\n        release {{\n            isMinifyEnabled = false\n            proguardFiles(\n                getDefaultProguardFile(\"proguard-android-optimize.txt\"),\n                \"proguard-rules.pro\"\n            )\n        }}\n    }}\n\n    compileOptions {{\n        sourceCompatibility = JavaVersion.VERSION_{java_version}\n        targetCompatibility = JavaVersion.VERSION_{java_version}\n    }}\n\n    buildFeatures {{\n        compose = true\n    }}\n\n    externalNativeBuild {{\n        cmake {{\n            path = rootProject.file(\"../.wizig/generated/android/jni/CMakeLists.txt\")\n        }}\n    }}\n\n    sourceSets {{\n        getByName(\"main\") {{\n            kotlin.directories.add(rootProject.file(\"../.wizig/sdk/android/src/main/kotlin\").path)\n            jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\").path)\n        }}\n    }}\n\n    packaging {{\n        resources {{\n            excludes += \"/META-INF/{{AL2.0,LGPL2.1}}\"\n        }}\n    }}\n}}\n\nkotlin {{\n    jvmToolchain({kotlin_target})\n}}\n\nval wizigAbiTargets: Map<String, String> = mapOf(\n    \"arm64-v8a\" to \"aarch64-linux-android\",\n    \"armeabi-v7a\" to \"arm-linux-androideabi\",\n    \"x86_64\" to \"x86_64-linux-android\",\n    \"x86\" to \"x86-linux-android\",\n)\n\nval requestedWizigAbi: String? = providers.gradleProperty(\"wizig.ffi.abi\").orNull\nif (requestedWizigAbi != null && requestedWizigAbi !in wizigAbiTargets.keys) {{\n    throw org.gradle.api.GradleException(\n        \"Unsupported Wizig FFI ABI '${{requestedWizigAbi}}'. Supported values: ${{wizigAbiTargets.keys.joinToString(\", \")}}\"\n    )\n}}\n\nfun abiTaskSuffix(abi: String): String =\n    abi.split('-', '_').joinToString(\"\") {{ segment ->\n        segment.replaceFirstChar {{ ch ->\n            if (ch.isLowerCase()) ch.titlecase() else ch.toString()\n        }}\n    }}\n\nfun registerWizigFfiTask(abi: String, zigTarget: String) =\n    tasks.register<Exec>(\"buildWizigFfi${{abiTaskSuffix(abi)}}\") {{\n        val appRoot = rootProject.file(\"..\")\n        val outDir = appRoot.resolve(\".wizig/generated/android/jniLibs/$abi\")\n        val outFile = outDir.resolve(\"libwizigffi.so\")\n        val generatedRoot = appRoot.resolve(\".wizig/generated/zig\")\n        val runtimeRoot = appRoot.resolve(\".wizig/runtime\")\n        val libRoot = appRoot.resolve(\"lib\")\n\n        group = \"wizig\"\n        description = \"Build Wizig FFI for Android ABI $abi\"\n\n        inputs.file(generatedRoot.resolve(\"WizigGeneratedFfiRoot.zig\"))\n        inputs.file(runtimeRoot.resolve(\"core/src/root.zig\"))\n        inputs.file(libRoot.resolve(\"WizigGeneratedAppModule.zig\"))\n        inputs.property(\"abi\", abi)\n        inputs.property(\"zigTarget\", zigTarget)\n        outputs.file(outFile)\n\n        onlyIf {{ requestedWizigAbi == null || requestedWizigAbi == abi }}\n\n        doFirst {{\n            outDir.mkdirs()\n        }}\n\n        commandLine(\n            \"zig\",\n            \"build-lib\",\n            \"-OReleaseFast\",\n            \"-target\",\n            zigTarget,\n            \"--dep\",\n            \"wizig_core\",\n            \"--dep\",\n            \"wizig_app\",\n            \"-Mroot=${{generatedRoot.path}}/WizigGeneratedFfiRoot.zig\",\n            \"-Mwizig_core=${{runtimeRoot.path}}/core/src/root.zig\",\n            \"-Mwizig_app=${{libRoot.path}}/WizigGeneratedAppModule.zig\",\n            \"--name\",\n            \"wizigffi\",\n            \"-dynamic\",\n            \"-femit-bin=${{outFile.path}}\",\n        )\n    }}\n\nval buildWizigFfiTasks = wizigAbiTargets.map {{ (abi, zigTarget) ->\n    registerWizigFfiTask(abi, zigTarget)\n}}\n\ntasks.register(\"buildWizigFfi\") {{\n    group = \"wizig\"\n    description = \"Build Wizig FFI shared libraries for required Android ABI targets\"\n    dependsOn(buildWizigFfiTasks)\n}}\n\ntasks.matching {{ it.name.startsWith(\"configureCMake\") || it.name.startsWith(\"buildCMake\") }}.configureEach {{\n    dependsOn(\"buildWizigFfi\")\n}}\n\ntasks.matching {{ it.name.startsWith(\"merge\") && it.name.endsWith(\"JniLibFolders\") }}.configureEach {{\n    dependsOn(\"buildWizigFfi\")\n}}\n\ndependencies {{\n    implementation(libs.androidx.core.ktx)\n    implementation(libs.androidx.lifecycle.runtime.ktx)\n    implementation(libs.androidx.activity.compose)\n    implementation(platform(libs.androidx.compose.bom))\n    implementation(libs.androidx.compose.ui)\n    implementation(libs.androidx.compose.ui.graphics)\n    implementation(libs.androidx.compose.ui.tooling.preview)\n    implementation(libs.androidx.compose.material3)\n    implementation(\"net.java.dev.jna:jna:5.14.0\")\n\n    testImplementation(libs.junit)\n    androidTestImplementation(libs.androidx.junit)\n    androidTestImplementation(libs.androidx.espresso.core)\n    androidTestImplementation(platform(libs.androidx.compose.bom))\n    androidTestImplementation(libs.androidx.compose.ui.test.junit4)\n\n    debugImplementation(libs.androidx.compose.ui.tooling)\n    debugImplementation(libs.androidx.compose.ui.test.manifest)\n}}\n""",
        encoding="utf-8",
    )


def write_android_gradle_wrapper(out_android_dir: Path, toolchains: dict) -> None:
    """Render Gradle wrapper properties from centralized toolchain policy."""
    wrapper = toolchains["templates"]["android"]["gradle_wrapper"]
    version = str(wrapper["version"])
    distribution_type = str(wrapper.get("distribution_type", "bin"))
    distribution_url = f"https://services.gradle.org/distributions/gradle-{version}-{distribution_type}.zip"
    distribution_sha256 = str(wrapper.get("distribution_sha256", "")).strip()
    network_timeout = int(wrapper.get("network_timeout", 10000))
    validate_distribution_url = bool(wrapper.get("validate_distribution_url", True))

    lines = [
        "distributionBase=GRADLE_USER_HOME",
        "distributionPath=wrapper/dists",
    ]
    if distribution_sha256:
        lines.append(f"distributionSha256Sum={distribution_sha256}")
    lines.extend([
        f"distributionUrl={distribution_url.replace(':', '\\:')}",
        f"networkTimeout={network_timeout}",
        f"validateDistributionUrl={'true' if validate_distribution_url else 'false'}",
        "zipStoreBase=GRADLE_USER_HOME",
        "zipStorePath=wrapper/dists",
        "",
    ])
    (out_android_dir / "gradle" / "wrapper" / "gradle-wrapper.properties").write_text(
        "\n".join(lines),
        encoding="utf-8",
    )


def apply_android_toolchain_overrides(out_android_dir: Path, toolchains: dict) -> None:
    """Apply version-catalog and dependency pins from toolchain policy."""
    versions = toolchains["templates"]["android"]["versions"]

    libs_versions_toml = out_android_dir / "gradle" / "libs.versions.toml"
    libs_text = libs_versions_toml.read_text(encoding="utf-8")
    libs_text = re.sub(r'^agp = "[^"]+"$', f'agp = "{versions["agp"]}"', libs_text, flags=re.MULTILINE)
    libs_text = re.sub(r'^kotlin = "[^"]+"$', f'kotlin = "{versions["kotlin"]}"', libs_text, flags=re.MULTILINE)
    libs_text = re.sub(r'^androidx-core-ktx = "[^"]+"$', f'androidx-core-ktx = "{versions["androidx_core_ktx"]}"', libs_text, flags=re.MULTILINE)
    libs_text = re.sub(
        r'^androidx-lifecycle-runtime-ktx = "[^"]+"$',
        f'androidx-lifecycle-runtime-ktx = "{versions["androidx_lifecycle_runtime_ktx"]}"',
        libs_text,
        flags=re.MULTILINE,
    )
    libs_text = re.sub(
        r'^androidx-activity-compose = "[^"]+"$',
        f'androidx-activity-compose = "{versions["androidx_activity_compose"]}"',
        libs_text,
        flags=re.MULTILINE,
    )
    libs_text = re.sub(
        r'^androidx-compose-bom = "[^"]+"$',
        f'androidx-compose-bom = "{versions["androidx_compose_bom"]}"',
        libs_text,
        flags=re.MULTILINE,
    )
    libs_text = re.sub(r'^junit = "[^"]+"$', f'junit = "{versions["junit"]}"', libs_text, flags=re.MULTILINE)
    libs_text = re.sub(r'^androidx-junit = "[^"]+"$', f'androidx-junit = "{versions["androidx_junit"]}"', libs_text, flags=re.MULTILINE)
    libs_text = re.sub(r'^espresso-core = "[^"]+"$', f'espresso-core = "{versions["espresso_core"]}"', libs_text, flags=re.MULTILINE)
    libs_versions_toml.write_text(libs_text, encoding="utf-8")

    app_build_kts = out_android_dir / "app" / "build.gradle.kts"
    app_text = app_build_kts.read_text(encoding="utf-8")
    app_text = re.sub(
        r'implementation\("net\.java\.dev\.jna:jna:[^"]+"\)',
        f'implementation("net.java.dev.jna:jna:{versions["jna"]}")',
        app_text,
    )
    app_text = app_text.replace(
        '            "zig",\n',
        '            discoverWizigZigBinary(),\n',
    )
    app_text = app_text.replace(
        'commandLine("zig",',
        'commandLine(discoverWizigZigBinary(),',
    )
    app_text = app_text.replace(
        '            "-OReleaseFast",\n',
        '            "-O${requestedWizigOptimize}",\n',
    )
    app_text = app_text.replace(
        '"-OReleaseFast",',
        '"-O${requestedWizigOptimize}",',
    )

    compatibility_marker = "fun abiTaskSuffix(abi: String): String ="
    if "fun discoverWizigZigBinary(): String {" not in app_text and compatibility_marker in app_text:
        compatibility_block = (
            "val supportedWizigOptimizeModes: Set<String> = setOf(\"Debug\", \"ReleaseFast\", \"ReleaseSafe\", \"ReleaseSmall\")\n\n"
            "val requestedWizigOptimize: String = providers.gradleProperty(\"wizig.ffi.optimize\").orNull ?: \"Debug\"\n"
            "if (requestedWizigOptimize !in supportedWizigOptimizeModes) {\n"
            "    throw org.gradle.api.GradleException(\n"
            "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\", \")}\"\n"
            "    )\n"
            "}\n\n"
            "fun discoverWizigZigBinary(): String {\n"
            "    val explicit = providers.gradleProperty(\"wizig.zig.bin\").orNull ?: System.getenv(\"ZIG_BINARY\")\n"
            "    if (!explicit.isNullOrBlank()) return explicit\n\n"
            "    val localPropertiesFile = rootProject.file(\"local.properties\")\n"
            "    if (localPropertiesFile.isFile) {\n"
            "        val fromLocalProperties = runCatching {\n"
            "            localPropertiesFile.readLines()\n"
            "                .asSequence()\n"
            "                .map { line -> line.trim() }\n"
            "                .firstOrNull { line -> line.startsWith(\"wizig.zig.bin=\") }\n"
            "                ?.substringAfter(\"=\")\n"
            "                ?.trim()\n"
            "        }.getOrNull()\n"
            "        if (!fromLocalProperties.isNullOrBlank()) return fromLocalProperties\n"
            "    }\n\n"
            "    val pathProbe = runCatching {\n"
            "        val process = ProcessBuilder(\"which\", \"zig\").redirectErrorStream(true).start()\n"
            "        val output = process.inputStream.bufferedReader().readText().trim()\n"
            "        if (process.waitFor() == 0 && output.isNotEmpty()) output else null\n"
            "    }.getOrNull()\n"
            "    if (!pathProbe.isNullOrBlank()) return pathProbe\n\n"
            "    val home = System.getProperty(\"user.home\") ?: \"\"\n"
            "    val candidates = listOf(\n"
            "        \"$home/.zvm/master/zig\",\n"
            "        \"$home/.zvm/bin/zig\",\n"
            "        \"$home/.local/bin/zig\",\n"
            "        \"/opt/homebrew/bin/zig\",\n"
            "        \"/usr/local/bin/zig\",\n"
            "    )\n"
            "    for (candidate in candidates) {\n"
            "        if (rootProject.file(candidate).canExecute()) return candidate\n"
            "    }\n\n"
            "    throw org.gradle.api.GradleException(\n"
            "        \"zig is not installed or discoverable (PATH/wizig.zig.bin/ZIG_BINARY/common locations)\"\n"
            "    )\n"
            "}\n\n"
        )
        app_text = app_text.replace(compatibility_marker, compatibility_block + compatibility_marker, 1)

    app_build_kts.write_text(app_text, encoding="utf-8")

    write_android_gradle_wrapper(out_android_dir, toolchains)


def write_android_sources(out_android_dir: Path) -> None:
    """Write Kotlin entrypoint and theme sources for the generated template."""
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


def generate_android(seeds_root: Path, out_android_dir: Path, defaults: dict, toolchains: dict) -> None:
    """Generate Android template output tree and apply toolchain policy pins."""
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
    apply_android_toolchain_overrides(out_android_dir, toolchains)
    write_android_sources(out_android_dir)
