#!/usr/bin/env python3
"""Пишет Resources/Localization/{en,ru}.lproj/*.strings из scripts/en_strings.py."""
import pathlib, sys
sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
from en_strings import EN

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

def write(path, pairs, header):
    lines = [f'/* {header} */']
    lines += [f'"{esc(k)}" = "{esc(v)}";' for k, v in pairs]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')

base = ROOT / 'Resources/Localization'
write(base / 'en.lproj/Localizable.strings', sorted(EN.items()), 'Оттиск — English. Сгенерировано scripts/build-strings.py')
write(base / 'ru.lproj/Localizable.strings', sorted((k, k) for k in EN), 'Оттиск — русский (основной язык, ключи = русский текст)')
write(base / 'en.lproj/ServicesMenu.strings', [('Печать через Оттиск', 'Print with Ottisk')], 'Меню «Службы»')
write(base / 'en.lproj/InfoPlist.strings', [('CFBundleDisplayName', 'Ottisk'), ('CFBundleName', 'Ottisk')], 'Info.plist')
write(base / 'ru.lproj/InfoPlist.strings', [('CFBundleDisplayName', 'Оттиск'), ('CFBundleName', 'Оттиск')], 'Info.plist')
print('ok', len(EN))
