#!/usr/bin/env bash
# Собирает сведения о принтерах CUPS в один текстовый файл (ничего не меняет).
# Пригодится, чтобы подогнать «Экономию тонера» и черновик под конкретный драйвер.
#   ./scripts/diagnose-printer.sh            → ottisk-diagnose.txt в текущей папке
set -uo pipefail
OUT="${1:-ottisk-diagnose.txt}"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
{
  echo "# Оттиск: диагностика CUPS — $(date)"
  echo "## macOS"; sw_vers 2>/dev/null
  echo; echo "## lpstat -v (устройства)"; lpstat -v 2>&1
  echo; echo "## lpstat -l -p (состояние)"; lpstat -l -p 2>&1
  echo; echo "## lpstat -d"; lpstat -d 2>&1
  echo; echo "## lpstat -o (очередь)"; lpstat -o 2>&1
  for p in $(lpstat -p 2>/dev/null | awk '/^printer /{print $2}'); do
    echo; echo "## lpoptions -p $p"; lpoptions -p "$p" 2>&1
    echo; echo "## lpoptions -p $p -l (опции драйвера)"; lpoptions -p "$p" -l 2>&1
  done
  echo; echo "## USB (Canon)"; system_profiler SPUSBDataType 2>/dev/null | grep -i -A6 canon || echo "Canon по USB не найден"
} > "$OUT"
# Серийные номера в URI не нужны для разбора — маскируем.
sed -i '' -E 's/(serial=)[A-Za-z0-9]+/\1XXXX/g' "$OUT" 2>/dev/null || true
echo "Готово: $OUT"
