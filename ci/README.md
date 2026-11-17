# CI и релизы

Workflow лежат в [`.github/workflows/`](../.github/workflows). Для публичного репозитория раннеры GitHub бесплатны.

- **`ci.yml`** — на каждый push в `main` (кроме правок только в `.md`/`docs`) и на pull request:
  - macOS (`macos-26`): `swift test` для `OttiskCore`, затем сборка `Ottisk.app` через `build-app.sh`
    **только Command Line Tools** (как на Mac без Xcode — поэтому в коде нельзя `@State`/`#Preview`,
    вместо `@State` есть `@LocalState`);
  - Windows (`windows-latest`): `dotnet test`.
- **`release.yml`** — по тегу `v*` (или вручную: Actions → Release → Run workflow, тогда только артефакты):
  - macOS: `build-app.sh` (ad-hoc подпись) → `Ottisk-macOS-<версия>.dmg` и `.zip`;
  - Windows: тесты, publish, NSIS → `Ottisk-Setup-<версия>.exe` и `Ottisk-Windows-portable-<версия>.exe`;
  - затем создаёт релиз (текст — раздел версии из `CHANGELOG.md`) и прикладывает четыре файла.

## Выпуск версии

```bash
# 1. поднять версию: macos/VERSION, windows/VERSION, Version в windows/src/Ottisk.App/Ottisk.App.csproj,
#    !define VERSION в windows/installer/Ottisk.nsi
# 2. дописать CHANGELOG.md (раздел "## 0.6.1 — дата")
git commit -am "Оттиск 0.6.1"
git push
git tag v0.6.1
git push origin v0.6.1   # дальше всё делает Actions
```
