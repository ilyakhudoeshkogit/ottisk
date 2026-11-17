#!/usr/bin/env bash
# Сборка Оттиска для Windows на Linux/macOS: тесты → publish (self-contained, single-file) → установщик NSIS.
# Нужны: .NET 8 SDK (в PATH) и makensis (apt install nsis или NSISDIR=... makensis).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-$(tr -d "[:space:]" < VERSION)}"
dotnet test tests/Ottisk.Core.Tests
rm -rf dist; mkdir -p dist
dotnet publish src/Ottisk.App -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableCompressionInSingleFile=true -p:DebugType=none -p:Version="$VERSION" -o dist/publish
MAKENSIS="${MAKENSIS:-makensis}"
"$MAKENSIS" -V2 -DVERSION="$VERSION" installer/Ottisk.nsi
cp dist/publish/Ottisk.exe "dist/Ottisk-Windows-portable-$VERSION.exe"
ls -la dist
