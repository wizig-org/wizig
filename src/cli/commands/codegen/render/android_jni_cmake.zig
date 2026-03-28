//! Renderer for generated Android JNI CMake entrypoint.

const std = @import("std");

pub fn renderAndroidJniCmake(arena: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(
        arena,
        "cmake_minimum_required(VERSION 3.22.1)\n" ++
            "project(wizig_generated_jni C)\n\n" ++
            "add_library(wizigffi SHARED IMPORTED)\n" ++
            "set_target_properties(wizigffi PROPERTIES\n" ++
            "    IMPORTED_LOCATION \"${{CMAKE_CURRENT_LIST_DIR}}/../jniLibs/${{ANDROID_ABI}}/libwizigffi.so\"\n" ++
            ")\n\n" ++
            "add_library(wizigjni SHARED WizigGeneratedApiBridge.c)\n" ++
            "target_link_libraries(wizigjni wizigffi log dl)\n",
        .{},
    );
}
