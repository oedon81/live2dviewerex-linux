#!/bin/bash
# Builds progman_shim.exe against Proton's wine-mono (no Windows SDK needed). Needs the .NET SDK in ~/.dotnet (Roslyn).
# OpenSSL 4 systems: .NET's start-up wants libssl.so.3, so a private symlink dir is put on LD_LIBRARY_PATH.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STEAM="${STEAM_DIR:-$HOME/.local/share/Steam}"
MONO="$(ls -d "$STEAM/steamapps/common/Proton - Experimental/files/share/wine/mono"/wine-mono-*/lib/mono/4.5 | sort -V | tail -1)"
CSC="$(ls "$HOME"/.dotnet/sdk/*/Roslyn/bincore/csc.dll | sort -V | tail -1)"
SSL="$(mktemp -d)"; trap 'rm -rf "$SSL"' EXIT
[ -e /usr/lib64/libssl.so.3 ] || { ln -s /usr/lib64/libssl.so.4 "$SSL/libssl.so.3"; ln -s /usr/lib64/libcrypto.so.4 "$SSL/libcrypto.so.3"; }
LD_LIBRARY_PATH="$SSL" "$HOME/.dotnet/dotnet" exec "$CSC" -nologo -nostdlib -noconfig \
  -r:"$MONO/mscorlib.dll" -r:"$MONO/System.dll" -platform:x64 -target:winexe -optimize+ \
  -out:"$HERE/progman_shim.exe" "$HERE/progman_shim.cs"
echo "built $HERE/progman_shim.exe"
