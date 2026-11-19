cmake_minimum_required(VERSION 3.22)
project(XLibArchiveCore VERSION 3.8.9 LANGUAGES C CXX)

# Official UnRAR 7.23, decoder-only DLL profile, deliberately no RAR_SMP.
add_library(XLibUnRAR STATIC
    unrar/rar.cpp
    unrar/strlist.cpp
    unrar/strfn.cpp
    unrar/pathfn.cpp
    unrar/smallfn.cpp
    unrar/global.cpp
    unrar/file.cpp
    unrar/filefn.cpp
    unrar/filcreat.cpp
    unrar/archive.cpp
    unrar/arcread.cpp
    unrar/unicode.cpp
    unrar/system.cpp
    unrar/crypt.cpp
    unrar/crc.cpp
    unrar/rawread.cpp
    unrar/encname.cpp
    unrar/resource.cpp
    unrar/match.cpp
    unrar/timefn.cpp
    unrar/rdwrfn.cpp
    unrar/consio.cpp
    unrar/options.cpp
    unrar/errhnd.cpp
    unrar/rarvm.cpp
    unrar/secpassword.cpp
    unrar/rijndael.cpp
    unrar/getbits.cpp
    unrar/sha1.cpp
    unrar/sha256.cpp
    unrar/blake2s.cpp
    unrar/hash.cpp
    unrar/extinfo.cpp
    unrar/extract.cpp
    unrar/volume.cpp
    unrar/list.cpp
    unrar/find.cpp
    unrar/unpack.cpp
    unrar/headers.cpp
    unrar/threadpool.cpp
    unrar/rs16.cpp
    unrar/cmddata.cpp
    unrar/ui.cpp
    unrar/largepage.cpp
    unrar/filestr.cpp
    unrar/scantree.cpp
    unrar/dll.cpp
    unrar/qopen.cpp
    unrar-bridge/XLibUnRAR.cpp)
add_library(xlib::unrar ALIAS XLibUnRAR)
set_target_properties(XLibUnRAR PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_STANDARD 11 CXX_STANDARD_REQUIRED ON)
target_compile_definitions(XLibUnRAR PRIVATE RARDLL SILENT _FILE_OFFSET_BITS=64)
target_include_directories(XLibUnRAR PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/unrar-bridge/include"
    PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/unrar")
if(UNIX AND NOT ANDROID)
    find_package(Threads REQUIRED)
    target_link_libraries(XLibUnRAR PUBLIC Threads::Threads)
endif()
if(ANDROID)
    target_compile_options(XLibUnRAR PRIVATE
        "-include${CMAKE_CURRENT_SOURCE_DIR}/config/android-unrar.h")
    target_link_options(XLibUnRAR INTERFACE
        "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")
endif()

# Keep this explicit: adding a vendored writer/filter must not enable it.
set(XLIB_ARCHIVE_SOURCES
    libarchive/archive_acl.c
    libarchive/archive_blake2s_ref.c
    libarchive/archive_blake2sp_ref.c
    libarchive/archive_check_magic.c
    libarchive/archive_cryptor.c
    libarchive/archive_digest.c
    libarchive/archive_entry.c
    libarchive/archive_entry_copy_stat.c
    libarchive/archive_entry_sparse.c
    libarchive/archive_entry_stat.c
    libarchive/archive_entry_strmode.c
    libarchive/archive_entry_xattr.c
    libarchive/archive_hmac.c
    libarchive/archive_options.c
    libarchive/archive_pack_dev.c
    libarchive/archive_ppmd7.c
    libarchive/archive_ppmd8.c
    libarchive/archive_random.c
    libarchive/archive_rb.c
    libarchive/archive_read.c
    libarchive/archive_read_add_passphrase.c
    libarchive/archive_read_open_fd.c
    libarchive/archive_read_open_filename.c
    libarchive/archive_read_open_memory.c
    libarchive/archive_read_set_options.c
    libarchive/archive_read_support_filter_none.c
    libarchive/archive_read_support_format_rar.c
    libarchive/archive_read_support_format_rar5.c
    libarchive/archive_read_support_format_zip.c
    libarchive/archive_string.c
    libarchive/archive_string_sprintf.c
    libarchive/archive_time.c
    libarchive/archive_util.c
    libarchive/archive_version_details.c
    libarchive/archive_virtual.c
)

add_library(XLibArchiveCore STATIC ${XLIB_ARCHIVE_SOURCES})
add_library(xlib::archive ALIAS XLibArchiveCore)
set_target_properties(XLibArchiveCore PROPERTIES
    POSITION_INDEPENDENT_CODE ON C_STANDARD 99 C_STANDARD_REQUIRED ON)
target_include_directories(XLibArchiveCore
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/libarchive")
target_compile_definitions(XLibArchiveCore PUBLIC __LIBARCHIVE_STATIC)

if(ANDROID)
    # The NDK legacy toolchain intentionally sets CMAKE_SYSTEM_VERSION=1;
    # its actual minimum API is ANDROID_PLATFORM_LEVEL. Native CMake Android
    # toolchains instead expose CMAKE_ANDROID_API/CMAKE_SYSTEM_VERSION.
    if(DEFINED ANDROID_PLATFORM_LEVEL)
        set(XLIB_ANDROID_API "${ANDROID_PLATFORM_LEVEL}")
    elseif(DEFINED CMAKE_ANDROID_API)
        set(XLIB_ANDROID_API "${CMAKE_ANDROID_API}")
    else()
        set(XLIB_ANDROID_API "${CMAKE_SYSTEM_VERSION}")
    endif()
    if(NOT XLIB_ANDROID_API MATCHES "^[0-9]+$" OR XLIB_ANDROID_API LESS 23)
        message(FATAL_ERROR "XLib archive Android builds require API 23 or newer")
    endif()
    target_compile_definitions(XLibArchiveCore PRIVATE
        PLATFORM_CONFIG_H="config/read-only-posix.h")
    target_include_directories(XLibArchiveCore PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/config")
    target_link_libraries(XLibArchiveCore PUBLIC z)
    # A static archive has no ELF LOAD segments. Propagate these to its JNI .so.
    target_link_options(XLibArchiveCore INTERFACE
        "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")
elseif(APPLE)
    # Preserve the independently tested SwiftPM Apple configuration.
    target_compile_definitions(XLibArchiveCore PRIVATE HAVE_CONFIG_H)
    target_link_libraries(XLibArchiveCore PUBLIC z iconv)
elseif(UNIX)
    # Useful for a portable no-iconv smoke build; not Android acceptance.
    target_compile_definitions(XLibArchiveCore PRIVATE
        PLATFORM_CONFIG_H="config/read-only-posix.h")
    find_package(ZLIB REQUIRED)
    find_package(Threads REQUIRED)
    target_link_libraries(XLibArchiveCore PUBLIC ZLIB::ZLIB Threads::Threads)
else()
    message(FATAL_ERROR "XLib archive has no reviewed configuration for this platform")
endif()

# One platform-neutral C facade for BOTH engines. Consumers must not reproduce
# the RAR4 metadata-only/UnRAR alignment policy independently in JNI.
set(XLIB_COMIC_BRIDGE "${CMAKE_CURRENT_SOURCE_DIR}/../apple-shared/Sources/CComicArchive")
add_library(XLibComicArchive STATIC "${XLIB_COMIC_BRIDGE}/CComicArchive.c")
add_library(xlib::comic ALIAS XLibComicArchive)
set_target_properties(XLibComicArchive PROPERTIES
    POSITION_INDEPENDENT_CODE ON C_STANDARD 99 C_STANDARD_REQUIRED ON)
target_include_directories(XLibComicArchive PUBLIC "${XLIB_COMIC_BRIDGE}/include")
target_link_libraries(XLibComicArchive PUBLIC xlib::archive xlib::unrar)

option(XLIB_ARCHIVE_BUILD_TESTS "Build the developer-only portable smoke test" OFF)
if(XLIB_ARCHIVE_BUILD_TESTS)
    enable_testing()
    add_executable(xlib_archive_smoke tests/portable-smoke.c)
    target_link_libraries(xlib_archive_smoke PRIVATE xlib::archive)
    add_test(NAME xlib_archive_memory_zip COMMAND xlib_archive_smoke)
    add_executable(xlib_comic_security tests/comic-security.c)
    target_link_libraries(xlib_comic_security PRIVATE xlib::comic)
    add_library(xlib_comic_link_probe SHARED tests/link-probe.c)
    target_link_libraries(xlib_comic_link_probe PRIVATE xlib::comic)
    if(NOT ANDROID)
        add_test(NAME xlib_comic_paired_decoder_regression COMMAND xlib_comic_security
            "${CMAKE_CURRENT_SOURCE_DIR}/../../contracts/fixtures/documents" "${CMAKE_CURRENT_BINARY_DIR}")
    endif()
endif()
