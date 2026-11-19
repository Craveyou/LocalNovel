#!/usr/bin/env bash
# Compile the pinned read-only core without CMake/Homebrew or signing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
core="$root/packages/native-archive"
mode="${1:-}"
if [[ -n "$mode" && "$mode" != "--security-test" ]]; then
    echo "Usage: $0 [--security-test]" >&2
    exit 2
fi
specs=("macosx arm64-apple-macos14.0" "iphonesimulator arm64-apple-ios17.0-simulator" "iphoneos arm64-apple-ios17.0")
flags=(-O2)
if [[ "$mode" == "--security-test" ]]; then
    specs=("macosx arm64-apple-macos14.0")
    flags=(-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all)
fi
unrar_sources=(
    rar
    strlist
    strfn
    pathfn
    smallfn
    global
    file
    filefn
    filcreat
    archive
    arcread
    unicode
    system
    crypt
    crc
    rawread
    encname
    resource
    match
    timefn
    rdwrfn
    consio
    options
    errhnd
    rarvm
    secpassword
    rijndael
    getbits
    sha1
    sha256
    blake2s
    hash
    extinfo
    extract
    volume
    list
    find
    unpack
    headers
    threadpool
    rs16
    cmddata
    ui
    largepage
    filestr
    scantree
    dll
    qopen
)
build="$(mktemp -d /private/tmp/xlib-comic-native.XXXXXX)"
for spec in "${specs[@]}"; do
    read -r sdk triple <<< "$spec"
    sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
    objects="$build/$sdk"
    mkdir -p "$objects"
    for source in "$core"/libarchive/*.c; do
        xcrun --sdk "$sdk" clang -target "$triple" -isysroot "$sdkpath" "${flags[@]}" \
            -DHAVE_CONFIG_H -D__LIBARCHIVE_STATIC -I"$core/libarchive" \
            -c "$source" -o "$objects/$(basename "${source%.c}").o"
    done
    xcrun --sdk "$sdk" clang -target "$triple" -isysroot "$sdkpath" "${flags[@]}" \
        -I"$core/include" -I"$core/unrar-bridge/include" \
        -I"$root/packages/apple-shared/Sources/CComicArchive/include" \
        -c "$root/packages/apple-shared/Sources/CComicArchive/CComicArchive.c" -o "$objects/bridge.o"
    for source in "${unrar_sources[@]}"; do
        xcrun --sdk "$sdk" clang++ -target "$triple" -isysroot "$sdkpath" "${flags[@]}" -std=c++11 \
            -DRARDLL -DSILENT -D_FILE_OFFSET_BITS=64 -I"$core/unrar" \
            -c "$core/unrar/$source.cpp" -o "$objects/unrar-$source.o"
    done
    xcrun --sdk "$sdk" clang++ -target "$triple" -isysroot "$sdkpath" "${flags[@]}" -std=c++11 \
        -DRARDLL -DSILENT -D_FILE_OFFSET_BITS=64 -I"$core/unrar" -I"$core/unrar-bridge/include" \
        -c "$core/unrar-bridge/XLibUnRAR.cpp" -o "$objects/unrar-bridge.o"
    xcrun libtool -static -o "$build/libXLibComic-$sdk.a" "$objects"/*.o
    echo "Built $triple: $build/libXLibComic-$sdk.a"
done
if [[ "$mode" == "--security-test" ]]; then
    xcrun --sdk macosx clang++ -target arm64-apple-macos14.0 "${flags[@]}" -std=c++11 \
        -DRARDLL -DSILENT -I"$core/unrar" "$core/tests/unrar-rawint.cpp" -o "$build/unrar-rawint"
    ASAN_OPTIONS=detect_leaks=0 "$build/unrar-rawint"
    xcrun --sdk macosx clang -target arm64-apple-macos14.0 "${flags[@]}" \
        -I"$root/packages/apple-shared/Sources/CComicArchive/include" \
        -c "$core/tests/comic-security.c" -o "$build/security.o"
    xcrun --sdk macosx clang++ -target arm64-apple-macos14.0 "${flags[@]}" \
        "$build/security.o" "$build/libXLibComic-macosx.a" -lz -liconv -o "$build/comic-security"
    ASAN_OPTIONS=detect_leaks=0 "$build/comic-security" "$root/contracts/fixtures/documents" "$build"
fi
