#!/bin/bash
set -euo pipefail
MACPOCKET_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$MACPOCKET_ROOT/scripts/env.sh"
build_decompiler() {
  local install_dir="$1"
  local arch os_dir native_dir
  case "$(uname -m)" in
    arm64) arch=arm64; os_dir=mac_arm_64 ;;
    x86_64) arch=x86_64; os_dir=mac_x86_64 ;;
    *) echo "Desteklenmeyen mimari: $(uname -m)" >&2; return 1 ;;
  esac
  native_dir="$install_dir/Ghidra/Features/Decompiler/os/$os_dir"
  if [[ ! -x "$native_dir/decompile" ]]; then
    make -C "$install_dir/Ghidra/Features/Decompiler/src/decompile/cpp" \
      -j4 ghidra_opt ARCH_TYPE="-arch $arch" OSDIR="$os_dir" ADDITIONAL_FLAGS=-w
    mkdir -p "$native_dir"
    install -m 755 \
      "$install_dir/Ghidra/Features/Decompiler/src/decompile/cpp/ghidra_opt" \
      "$native_dir/decompile"
  fi
}
if [[ -f "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" ]]; then
  if ! /usr/bin/grep -Eq '^application.version=12\.1\.4$' "$GHIDRA_INSTALL_DIR/Ghidra/application.properties"; then
    echo "Ghidra 12.1.4 bekleniyor: $GHIDRA_INSTALL_DIR" >&2
    exit 1
  fi
  build_decompiler "$GHIDRA_INSTALL_DIR"
  echo "Ghidra kurulumu mevcut: $GHIDRA_INSTALL_DIR"
  exit 0
fi
if [[ -e "$GHIDRA_INSTALL_DIR" ]]; then
  echo "Hedef dolu; mevcut dosyalar korunuyor: $GHIDRA_INSTALL_DIR" >&2
  exit 1
fi
MACPOCKET_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/macpocket-ghidra.XXXXXX")"
trap 'rm -rf "$MACPOCKET_STAGE"' EXIT
curl --fail --location --retry 3 \
  'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip' \
  --output "$MACPOCKET_STAGE/ghidra.zip"
printf '%s  %s\n' \
  'ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db' \
  "$MACPOCKET_STAGE/ghidra.zip" | shasum -a 256 --check
ditto -x -k "$MACPOCKET_STAGE/ghidra.zip" "$MACPOCKET_STAGE/unpacked"
build_decompiler "$MACPOCKET_STAGE/unpacked/ghidra_12.1.4_PUBLIC"
mkdir -p "$(dirname "$GHIDRA_INSTALL_DIR")"
mv "$MACPOCKET_STAGE/unpacked/ghidra_12.1.4_PUBLIC" "$GHIDRA_INSTALL_DIR"
echo "Ghidra 12.1.4 kuruldu: $GHIDRA_INSTALL_DIR"
