#!/bin/bash
# build_tdlib_dylib.sh - build TDLib as libtdjson.dylib for armv7.
#
# Why a dylib and not the static libs we already have: linking TDLib into the
# app statically pushes __TEXT past 19MB, and an armv7 Thumb BL only reaches
# +/-16MB. A working linker inserts branch islands; ld-27036.1 does not - it
# just fails with
#   "22-bit thumb branch out of range (displacement=19198446, max is +/-16MB)"
# Splitting TDLib into its own image keeps each __TEXT under the limit. This is
# also how TDLib normally ships.
#
# Output: build/armv7/tdlib/lib/libtdjson.dylib, install_name set so the app
# can carry it inside the bundle.
#
# armv7 needs our patches on top of the submodule: scripts/tdlib_patches/*.patch.
# They go on for the build and come off at exit, so the submodule stays clean.
#
#   scripts/build_tdlib_dylib.sh            build the candidate, leave the app alone
#   scripts/build_tdlib_dylib.sh --install  also make it the dylib the app ships,
#                                           keeping the previous one as .prev
#
# The candidate is not installed by default because a TDLib that loads on the
# host proves nothing: only the device can say whether it runs.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TDLIB_SRC="${ROOT_DIR}/tdlib/td"
BUILD_DIR="${ROOT_DIR}/build/tdlib-dylib-armv7"
SHIP_DIR="${ROOT_DIR}/build/armv7/tdlib/lib"
OUT_DIR="${ROOT_DIR}/build/armv7/tdlib/candidate"
PATCH_DIR="${SCRIPT_DIR}/tdlib_patches"

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

XCODE_DEV="/Applications/Xcode-beta.app/Contents/Developer"
[ -d "${XCODE_DEV}" ] || XCODE_DEV="$(xcode-select -p)"
SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS12.4.sdk"
[ -d "${SDK_PATH}" ] || SDK_PATH="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
TOOLCHAIN="${XCODE_DEV}/Toolchains/XcodeDefault.xctoolchain/usr/bin"

# The theos SDK carries no C++ standard library headers, so point clang at
# Xcode's libc++ the same way the Makefile does.
XCODE_SDK="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
CXX_STDLIB_INC="-isystem ${XCODE_SDK}/usr/include/c++/v1"

for tool in cmake gperf; do
	command -v "$tool" >/dev/null || { echo "[-] $tool not found (brew install $tool)"; exit 1; }
done

echo "[+] TDLib -> libtdjson.dylib (armv7)"
echo "    src : ${TDLIB_SRC}"
echo "    sdk : ${SDK_PATH}"

# Never leave the submodule patched, however the build ends.
APPLIED=()
unpatch() {
	local i
	for ((i = ${#APPLIED[@]} - 1; i >= 0; i--)); do
		git -C "${TDLIB_SRC}" apply -R "${APPLIED[$i]}" || echo "[-] could not take off ${APPLIED[$i]}"
	done
}
trap unpatch EXIT
for patch in "${PATCH_DIR}"/*.patch; do
	git -C "${TDLIB_SRC}" apply "${patch}" || { echo "[-] ${patch} does not apply to this TDLib"; exit 1; }
	APPLIED+=("${patch}")
	echo "[+] patch: $(basename "${patch}")"
done

# TDLib needs host-side code generation before it can cross-compile
if [ ! -d "${ROOT_DIR}/tdlib/native-build" ]; then
	echo "[+] pregenerating sources"
	mkdir -p "${ROOT_DIR}/tdlib/native-build"
	cd "${ROOT_DIR}/tdlib/native-build"
	cmake -DTD_GENERATE_SOURCE_FILES=ON "${TDLIB_SRC}"
	cmake --build . --target prepare_cross_compiling
fi

mkdir -p "${BUILD_DIR}" "${OUT_DIR}"

# clock_gettime and fdopendir are iOS 10 APIs. Against a modern SDK they link
# as weak imports and dyld resolves them to NULL on iOS 7 - TDLib then calls
# address 0 from one of its own threads. Provide strong definitions so the
# linker binds them here instead.
COMPAT_O="${BUILD_DIR}/ios7_compat.o"
"${TOOLCHAIN}/clang" -arch armv7 -mthumb -Os -isysroot "${SDK_PATH}" \
	-miphoneos-version-min=6.0 -c "${ROOT_DIR}/compat/ios7_compat.c" -o "${COMPAT_O}"
echo "[+] ios7 compat shims: ${COMPAT_O}"

# scripts/build_openssl.sh gives AES and SHA-256 their assembly: on the iPod touch
# 4 AES-IGE goes from 11 to 19 MB/s and SHA-256 from 17 to 49 MB/s.
OPENSSL_LIBS="${ROOT_DIR}/build/armv7/openssl"
OPENSSL_INC="${OPENSSL_LIBS}/include"
if [ ! -f "${OPENSSL_LIBS}/libcrypto.a" ]; then
	OPENSSL_LIBS="${ROOT_DIR}/build/armv7/libs"
	OPENSSL_INC="${ROOT_DIR}/include"
	echo "[!] no assembly OpenSSL, using ${OPENSSL_LIBS}"
fi
echo "[+] OpenSSL: ${OPENSSL_LIBS}"

cd "${BUILD_DIR}"
rm -f CMakeCache.txt

cmake "${TDLIB_SRC}" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_COMPILER_LAUNCHER=ccache \
	-DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
	-DCMAKE_C_COMPILER="${TOOLCHAIN}/clang" \
	-DCMAKE_CXX_COMPILER="${TOOLCHAIN}/clang++" \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
	-DCMAKE_OSX_ARCHITECTURES="armv7" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=6.0 \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DATOMICS_FOUND=TRUE \
	-DATOMICS_LIBRARIES="" \
	-DCMAKE_C_FLAGS="-Wno-error -mthumb -Os" \
	-DCMAKE_CXX_FLAGS="-Wno-error -mthumb -Os ${CXX_STDLIB_INC}" \
	-DCMAKE_SHARED_LINKER_FLAGS="-install_name @executable_path/libtdjson.dylib ${COMPAT_O}" \
	-DOPENSSL_INCLUDE_DIR="${OPENSSL_INC}" \
	-DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_LIBS}/libcrypto.a" \
	-DOPENSSL_SSL_LIBRARY="${OPENSSL_LIBS}/libssl.a" \
	-DBUILD_SHARED_LIBS=ON \
	-DTD_ENABLE_LTO=OFF \
	-DCMAKE_POLICY_DEFAULT_CMP0074=NEW

cmake --build . --target tdjson -- -j"$(sysctl -n hw.logicalcpu)"

DYLIB="$(find "${BUILD_DIR}" -name 'libtdjson*.dylib' | head -1)"
[ -n "${DYLIB}" ] || { echo "[-] no dylib produced"; exit 1; }

cp -f "${DYLIB}" "${OUT_DIR}/libtdjson.dylib"
"${TOOLCHAIN}/strip" -x "${OUT_DIR}/libtdjson.dylib" 2>/dev/null || true

# CMake overrides -install_name with its own @rpath value; the app carries the
# dylib next to its binary, and iOS 7 has no @rpath support worth relying on.
install_name_tool -id "@executable_path/libtdjson.dylib" "${OUT_DIR}/libtdjson.dylib"

# Same broken armv7 linker, same lost Thumb bits - a dylib full of C++ vtables
# needs the fixup at least as much as the app does.
MACHOFIX="${ROOT_DIR}/build/tools/machofix"
[ -x "${MACHOFIX}" ] || cc -O2 -o "${MACHOFIX}" "${ROOT_DIR}/tools/machofix.c"
"${MACHOFIX}" "${OUT_DIR}/libtdjson.dylib"
ldid -S "${OUT_DIR}/libtdjson.dylib" 2>/dev/null || true

echo ""
echo "[+] ${OUT_DIR}/libtdjson.dylib"
ls -lh "${OUT_DIR}/libtdjson.dylib"
otool -l "${OUT_DIR}/libtdjson.dylib" | grep -A2 LC_ID_DYLIB | head -3
TEXT_SIZE="$(otool -l "${OUT_DIR}/libtdjson.dylib" | awk '/segname __TEXT/{f=1} f&&/vmsize/{print $2; exit}')"
echo "    __TEXT ${TEXT_SIZE} (armv7 thumb branches reach 16MB, 0x1000000)"
if [ "$((TEXT_SIZE))" -ge "$((0x1000000))" ]; then
	echo "[-] __TEXT is past what a thumb branch reaches"
	exit 1
fi

if [ "${INSTALL}" -eq 1 ]; then
	mkdir -p "${SHIP_DIR}"
	[ -f "${SHIP_DIR}/libtdjson.dylib" ] && cp -f "${SHIP_DIR}/libtdjson.dylib" "${SHIP_DIR}/libtdjson.prev.dylib"
	cp -f "${OUT_DIR}/libtdjson.dylib" "${SHIP_DIR}/libtdjson.dylib"
	echo "[+] installed; the previous one is libtdjson.prev.dylib"
fi
