#!/bin/bash
# build_openssl.sh - OpenSSL 1.1.1w for armv7 with its ARM assembly.
#
# The libcrypto we carried was the iphoneos-cross target, which has no assembly:
# AES and SHA-256 in plain C, on every packet and every file part. ios-xcrun is
# the same version line with aes-armv4, bsaes and the NEON SHA and GHASH.
#
# Output: build/armv7/openssl/{libcrypto,libssl}.a and include/, which
# build_tdlib_dylib.sh prefers when they exist.
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=1.1.1w
SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
WORK="${ROOT_DIR}/build/openssl-src"
OUT="${ROOT_DIR}/build/armv7/openssl"
SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS12.4.sdk"

mkdir -p "${WORK}" "${OUT}"
TARBALL="${WORK}/openssl-${VERSION}.tar.gz"
[ -f "${TARBALL}" ] || curl -fsSL -o "${TARBALL}" "https://www.openssl.org/source/openssl-${VERSION}.tar.gz"
echo "${SHA256}  ${TARBALL}" | shasum -a 256 -c -

rm -rf "${WORK}/openssl-${VERSION}"
tar -xzf "${TARBALL}" -C "${WORK}"
cd "${WORK}/openssl-${VERSION}"

# no-async: makecontext is not on iOS. no-comp, no-dso, no-engine: nothing here
# uses them, and each is code the 16 MB branch limit has to carry.
CC="xcrun clang -mthumb -isysroot ${SDK_PATH}" ./Configure ios-xcrun \
	no-shared no-tests no-dso no-engine no-comp no-async no-hw \
	--prefix="${OUT}"
make -j"$(sysctl -n hw.logicalcpu)" build_all_generated
# The assembly reaches its CPU flags through a slot in __nl_symbol_ptr under a
# plain label. The linker wants those slots anonymous and asserts in
# setGotCoalescable; an L prefix makes the label one the assembler drops.
perl -pi -e 's/\bOPENSSL_armcap_P\b/LOPENSSL_armcap_P/g' crypto/*.S crypto/*/*.S
# And it picks ARM mode on Apple only because its old assembler could not do
# unified syntax. machofix sets the Thumb bit on every pointer into __text, so a
# table holding AES_encrypt in ARM mode jumped into it as Thumb and crashed.
perl -pi -e 's/defined\(__thumb2__\) && !defined\(__APPLE__\)/defined(__thumb2__)/g' crypto/*.S crypto/*/*.S
# The same Apple-only branch spells movw as mov, which only ARM mode accepts.
perl -pi -e 's/\bmov(\s+r\d+,\s*#:lower16:)/movw$1/' crypto/*.S crypto/*/*.S
make -j"$(sysctl -n hw.logicalcpu)" build_libs
cp -f libcrypto.a libssl.a "${OUT}/"
rm -rf "${OUT}/include"
cp -R include "${OUT}/include"

echo "[+] ${OUT}"
ls -lh "${OUT}"/*.a
nm -arch armv7 "${OUT}/libcrypto.a" 2>/dev/null | grep -E ' T _(bsaes_cbc_encrypt|sha256_block_data_order|gcm_ghash_neon)$' || true
