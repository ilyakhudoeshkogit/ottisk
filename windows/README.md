# Оттиск для Windows

Простая печать PDF и фото для не-технического пользователя: крупный русский интерфейс, пресеты,
живое превью «как напечатается», ручная двусторонняя печать. Версия для Windows по мотивам
Mac-приложения «Оттиск» (`../macos`); код написан отдельно.

## Состав
- `src/Ottisk.Core` — чистая логика (net8.0, без Windows): диапазоны страниц, N на листе, брошюра,
  порядок ручной двусторонней печати, чёт/нечёт, поле под дырокол (зеркальное на оборотах), DuplexGate,
  поля ГОСТ 7.32 (`PageMargins`), размеры бумаги (`Papers`), пробный лист (`DuplexCalibration`), файл настроек (`UserSettings`),
  номера страниц (`PageNumbering`, как на Mac: номер привязан к странице документа, титул без номера), обрезка белых полей
  (`ContentBounds`: bbox непустых пикселей, порог 235, общая рамка для страниц одного размера), водяной знак (`Watermark`).
- `tests/Ottisk.Core.Tests` — 131 xUnit-тест (идут на Linux).
- `src/Ottisk.App` — WPF (net8.0-windows10.0.19041.0; превью рисуется в отдельном STA-потоке `StaWorker`, растры страниц и листов кешируются): PDF через встроенный Windows.Data.Pdf, картинки через WPF,
  печать через System.Printing/PrintDialog (стороны рисуются в 300 dpi в момент печати; превью использует тот же код —
  `SideRenderer`, включая номера страниц, водяной знак и обрезку белых полей; поиск полей — `ContentScan`).
- `installer/Ottisk.nsi` — установщик NSIS (per-user, без админа, %LOCALAPPDATA%\Programs\Ottisk, ярлыки на рабочем столе и в «Пуск»,
  запись в «Приложения», «Открыть с помощью» для PDF/JPG/PNG).
- `docs/ИНСТРУКЦИЯ.md` — для пользователя, `CHANGELOG.md` — история версий, `VERSION` — текущая версия.

## Сборка (Linux/macOS/Windows)
```
./build.sh          # тесты → publish self-contained single-file win-x64 → makensis → dist/
```
Нужны .NET 8 SDK и NSIS (`makensis`; путь можно задать переменной `MAKENSIS`, а данные NSIS — `NSISDIR`).
Для кросс-сборки WPF на Linux/macOS включён `EnableWindowsTargeting`.
Результат: `dist/Ottisk-Setup-<версия>.exe`, `dist/Ottisk-Windows-portable-<версия>.exe`.

## Статус
Собирается, тесты зелёные. **Не проверено на реальной Windows и с реальным принтером** (нет Windows/wine в среде сборки).
Подписи кода нет — SmartScreen покажет предупреждение.
