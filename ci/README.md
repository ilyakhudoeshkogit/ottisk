# CI: сборка релиза

`release.yml` — workflow GitHub Actions: по тегу `v*` собирает Mac-версию на `macos-15`
(`build-app.sh`, ad-hoc подпись, `.dmg` и `.zip`) и Windows-версию на `windows-latest`
(тесты, publish, установщик NSIS), потом создаёт релиз и прикладывает файлы.

Пока он лежит здесь и **не запускается**. Чтобы включить, перенеси его в `.github/workflows/`
(через сайт GitHub: Add file → Create new file → `.github/workflows/release.yml`, вставить содержимое)
или запушь токеном со scope `workflow`. Для публичного репозитория раннеры GitHub бесплатны.

Выпуск версии после этого:

```bash
# поднять версию в macos/VERSION и windows/VERSION (+ Version в windows/src/Ottisk.App/Ottisk.App.csproj), дописать CHANGELOG
git tag v0.6.1
git push origin v0.6.1
```
