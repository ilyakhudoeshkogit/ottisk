#!/usr/bin/env bash
# Собирает Оттиск.app без Xcode — нужны только Command Line Tools.
#   ./build-app.sh            собрать dist/Ottisk.app
#   ./build-app.sh --install  собрать и положить в ~/Applications
#   ./build-app.sh --open     собрать и сразу запустить
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0; OPEN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --open) OPEN=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Неизвестный параметр: $arg"; exit 2 ;;
  esac
done

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Собирать нужно на Mac (macOS 14+)."; exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Нет swift. Установи Command Line Tools: xcode-select --install"; exit 1
fi

VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/Ottisk.app"

echo "→ swift build -c release (версия $VERSION, сборка $BUILD)"
swift build -c release --product Ottisk
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "→ собираю $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Ottisk" "$APP/Contents/MacOS/Ottisk"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist.template > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Локализация: ru (основной) и en. SwiftUI ищет строки в Bundle.main.
for lproj in Resources/Localization/*.lproj; do
  [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"
done
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "→ иконка"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ ad-hoc подпись (без Apple ID)"
codesign --force --deep --sign - "$APP"

echo "✓ Готово: $(pwd)/$APP"

if [[ $INSTALL -eq 1 ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Ottisk.app"
  cp -R "$APP" "$HOME/Applications/"
  # Обновить Launch Services, чтобы Dock и «Открыть с помощью» увидели приложение.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Ottisk.app" || true
  echo "✓ Установлено: ~/Applications/Ottisk.app"
  # Обновить меню «Службы», чтобы появилось «Печать через Оттиск».
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  APP="$HOME/Applications/Ottisk.app"
fi

if [[ $OPEN -eq 1 ]]; then
  open "$APP"
fi
