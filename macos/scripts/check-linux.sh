#!/usr/bin/env bash
# Всё, что можно проверить без Mac: тесты OttiskCore, синтаксис кода приложения,
# Info.plist, переводы и shell-скрипты. На Mac вместо этого: swift test && ./build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ swift test (OttiskCore)"
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1

echo "→ синтаксис Sources/Ottisk (swiftc -parse, без проверки типов — AppKit/SwiftUI на Linux нет)"
fail=0
while IFS= read -r f; do
  if ! out=$(swiftc -parse "$f" 2>&1) || grep -q "error:" <<<"$out"; then echo "$out"; fail=1; fi
done < <(find Sources/Ottisk -name '*.swift')
[[ $fail -eq 0 ]] && echo "  ok"

echo "→ Info.plist"
python3 -c "import plistlib,sys; d=plistlib.load(open('Resources/Info.plist.template','rb')); assert d['NSServices'][0]['NSMessage']=='printWithOttisk'; assert 'ottisk' in d['CFBundleURLTypes'][0]['CFBundleURLSchemes']; print('  ok')"

echo "→ переводы"
python3 scripts/build-strings.py >/dev/null
python3 scripts/extract-strings.py --check Resources/Localization/en.lproj/Localizable.strings

echo "→ shell-скрипты"
bash -n build-app.sh && bash -n scripts/diagnose-printer.sh && echo "  ok"
exit $fail
