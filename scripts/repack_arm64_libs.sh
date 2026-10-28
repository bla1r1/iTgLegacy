#!/bin/bash
# Repack the fat GNU-style TDLib archives and the misaligned WebP archive
# into thin arm64 Apple archives Apple ld64 accepts.
#
# The TDLib build produces members that carry two architectures and an
# odd GNU archive layout; the homebrew ld64 driver rejects them ("archive
# member '//' not a mach-o file"). WebP.framework's arm64 slice has the
# same trouble ("not 8-byte aligned"). The cure for both is the same:
# extract the members, thin them to arm64, and libtool them back.
#
# Usage: scripts/repack_arm64_libs.sh
#   Needs build/tdlib/lib/lib*.a (from scripts/build_tdlib.sh) plus
#   tdlib/native-build/tdtl/libtdtl.a, and libs/WebP.framework.
#   Writes build/arm64/tdlib64/lib*.a and build/arm64/libs/libwebp.a.
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AR="${AR:-/opt/homebrew/opt/llvm/bin/llvm-ar}"
LIPO="${LIPO:-/opt/homebrew/opt/llvm/bin/llvm-lipo}"
OUT="${ROOT_DIR}/build/arm64/tdlib64"
WOUT="${ROOT_DIR}/build/arm64/libs"

cd "$(mktemp -d "${TMPDIR:-/tmp}/repack.XXXXXX")"
echo "[+] repacking TDLib archives into thin arm64"

# Two sources can share a basename (tde2e's hand-written and its
# generated e2e_api.cpp did): plain `ar x` would overwrite one with
# the other, dismissing half the code silently, and a duplicate ar
# member name later breaks the symbol index. So every .o occurrence
# is pulled out on its own with `xN`; occurrences after the first
# keep a numbered member name. `xN n archive member` extracts the
# n-th occurrence of member.
extract_occurrences() {
  case "$1" in /*) lib="$1";; *) lib="$PWD/$1";; esac
  dest="$2"
  mkdir -p "$dest"
  seen="$(mktemp)"
  for memb in $("$AR" t "$lib"); do
    case "$memb" in *.o) ;; *) continue;; esac
    count=$(grep -xc "$memb" "$seen" || true)
    n=$(( count + 1 ))
    echo "$memb" >> "$seen"
    if [ "$n" -eq 1 ]; then
      dest_name="$memb"
    else
      # every occurrence after the first keeps a numbered member name
      dest_name="${memb%.o}_$((n - 1)).o"
      echo "    duplicate member: $memb -> $dest_name"
    fi
    # a scratch dir per occurrence: xN writes the member's own name and
    # would otherwise overwrite the previous occurrence's file
    tmp="$(mktemp -d)"
    (cd "$tmp" && "$AR" xN "$n" "$lib" "$memb")
    mv "$tmp/$memb" "$dest/$dest_name"
    rm -rf "$tmp"
  done
  rm -f "$seen"
}

for lib in "${ROOT_DIR}/build/tdlib/lib/"lib*.a; do
  name="$(basename "$lib" .a)"; name="${name#lib}"
  rm -rf "$name"
  extract_occurrences "$lib" "$name"
  mkdir "$name/arm64"
  for obj in "$name"/*.o; do
    case "$("$LIPO" -info "$obj" 2>/dev/null)" in
      *arm64*) "$LIPO" -thin arm64 "$obj" -output "$name/arm64/$(basename "$obj")" 2>/dev/null || cp "$obj" "$name/arm64/";;
      *) cp "$obj" "$name/arm64/";;
    esac
  done
  (cd "$name/arm64" && libtool -static -o "${TMPDIR:-/tmp}/repack_out_$name.a" *.o)
  mv "${TMPDIR:-/tmp}/repack_out_$name.a" "$OUT/lib$name.a"
done

# libtdtl is built by the pregenerate phase and never installed next to the rest.
if [ -f "${ROOT_DIR}/tdlib/native-build/tdtl/libtdtl.a" ]; then
  name=libtdtl
  rm -rf "$name"
  extract_occurrences "${ROOT_DIR}/tdlib/native-build/tdtl/libtdtl.a" "$name"
  mkdir "$name/arm64"
  for obj in "$name"/*.o; do
    case "$("$LIPO" -info "$obj" 2>/dev/null)" in
      *arm64*) "$LIPO" -thin arm64 "$obj" -output "$name/arm64/$(basename "$obj")" 2>/dev/null || cp "$obj" "$name/arm64/";;
      *) cp "$obj" "$name/arm64/";;
    esac
  done
  (cd "$name/arm64" && libtool -static -o "${TMPDIR:-/tmp}/repack_out_$name.a" *.o)
  mv "${TMPDIR:-/tmp}/repack_out_$name.a" "$OUT/libtdtl.a"
fi

echo "[+] repacking WebP's arm64 slice"
if [ -f "${ROOT_DIR}/libs/WebP.framework/WebP" ]; then
  rm -rf webp && mkdir webp
  "$LIPO" -thin arm64 "${ROOT_DIR}/libs/WebP.framework/WebP" -output webp/thin.a
  extract_occurrences webp/thin.a webp/objs
  (cd webp/objs && libtool -static -o "$WOUT/libwebp.a" *.o)
fi

echo "[+] done: ${OUT} ${WOUT}"
