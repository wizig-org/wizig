cmake_minimum_required(VERSION 3.22.1)
project(wizig_generated_jni C)

add_library(wizigffi SHARED IMPORTED)
set_target_properties(wizigffi PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libwizigffi.so"
)

add_library(wizigjni SHARED WizigGeneratedApiBridge.c)
target_link_libraries(wizigjni wizigffi log dl)
