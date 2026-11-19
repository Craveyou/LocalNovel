cmake_minimum_required(VERSION 3.22)
project(XLibAndroidArchive LANGUAGES C CXX)
# NDK's legacy AGP toolchain reports CMAKE_SYSTEM_VERSION=1. The actual
# compiler API comes from ANDROID_PLATFORM_LEVEL; expose that to the core guard.
if(ANDROID_PLATFORM_LEVEL LESS 23)
    message(FATAL_ERROR "Android archive reader requires API 23")
endif()
set(CMAKE_SYSTEM_VERSION "${ANDROID_PLATFORM_LEVEL}")
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../packages/native-archive" "archive-core")
# The upstream stored-file path repeatedly zero-initializes 4 MiB vectors.
# Native -O0 makes tiny RAR4 pages take seconds in the shipped debug APK.
# Keep symbols while using the same optimized decoding path in both builds.
target_compile_options(XLibArchiveCore PRIVATE -O2)
target_compile_options(XLibUnRAR PRIVATE -O2)
target_include_directories(XLibArchiveCore PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(XLibUnRAR PRIVATE "-include${CMAKE_CURRENT_SOURCE_DIR}/android_unrar_compat.h")
add_library(xlib_archive SHARED archive_jni.cpp)
target_compile_features(xlib_archive PRIVATE cxx_std_17)
target_link_libraries(xlib_archive PRIVATE xlib::archive xlib::unrar)
target_compile_options(xlib_archive PRIVATE -Wall -Wextra)
target_link_options(xlib_archive PRIVATE -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384)
