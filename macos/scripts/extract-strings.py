#!/usr/bin/env python3
"""Собирает русские строки интерфейса из Sources/Ottisk для Localizable.strings.

Ключ — сама русская строка (как её видит SwiftUI). Интерполяции \\(…) превращаются
в %@ или %lld — так SwiftUI строит ключ LocalizedStringKey.
Запуск: python3 scripts/extract-strings.py [--check Resources/Localization/en.lproj/Localizable.strings]
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALLS = r'(?:Text|Button|Label|Toggle|Picker|Section|TextField|LabeledContent|Menu|Window|CommandMenu|DisclosureGroup|Slider|Stepper|\.help|\.navigationTitle|\.navigationSubtitle|\.alert|\.confirmationDialog|String\(localized:|NSLocalizedString\(|LocalizedStringKey\(|Hint\(|(?:GroupLabel|MMField)\(title:|step\(\d+,|return)'
LIT = re.compile(CALLS + r'\s*\(?\s*"((?:[^"\\]|\\.)*)"')
INT_HINTS = ('count', 'Count', 'number', 'index', 'dpi', 'width', 'height', 'pages', 'copies', 'pageCount', 'Index', 'n)', 'sheets')
CYR = re.compile('[А-Яа-яЁё]')

def key_for(literal):
    out, i = [], 0
    while i < len(literal):
        if literal.startswith('\\(', i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                depth += {'(': 1, ')': -1}.get(literal[j], 0)
                j += 1
            expr = literal[i + 2:j - 1]
            is_int = (re.fullmatch(r'[\w.]+(\s*[+-]\s*\d+)?', expr) and any((expr == 'n') if h == 'n)' else (h in expr) for h in INT_HINTS)
                      and 'format' not in expr and 'title' not in expr and 'name' not in expr)
            out.append('%lld' if is_int else '%@')
            i = j
        else:
            out.append(literal[i])
            i += 1
    return ''.join(out).replace('\\"', '"')

def extract():
    keys = {}
    for path in sorted((ROOT / 'Sources/Ottisk').rglob('*.swift')):
        for m in LIT.finditer(path.read_text()):
            lit = m.group(1)
            # return "…" берём только для LocalizedStringKey-функций без интерполяции
            if m.group(0).startswith('return') and '\\(' in lit:
                continue
            if CYR.search(lit):
                keys.setdefault(key_for(lit), path.name)
    # Строки из OttiskCore, которые приложение показывает через .loc
    core = ROOT / 'Sources/OttiskCore'
    for path in sorted(core.rglob('*.swift')):
        for m in re.finditer(r'return "((?:[^"\\]|\\.)*)"', path.read_text()):
            lit = m.group(1)
            if CYR.search(lit) and '\\(' not in lit:
                keys.setdefault(lit, path.name)
    return keys

def parse_strings(path):
    text = pathlib.Path(path).read_text()
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$', text, re.M)
    body = [l for l in text.splitlines() if l.strip() and not l.strip().startswith('/*') and not l.strip().startswith('//')]
    if len(body) != len(pairs):
        bad = [l for l in body if not re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$', l)]
        raise SystemExit(f'Синтаксис .strings: {len(bad)} плохих строк, например: {bad[:3]}')
    return dict(pairs)

if __name__ == '__main__':
    keys = extract()
    if len(sys.argv) > 2 and sys.argv[1] == '--check':
        tr = parse_strings(sys.argv[2])
        missing = [k for k in keys if k.replace('"', '\\"') not in tr]
        for k, v in tr.items():
            if sorted(re.findall(r'%(?:lld|@)', k)) != sorted(re.findall(r'%(?:lld|@)', v)):
                raise SystemExit(f'Плейсхолдеры не совпадают: {k!r} -> {v!r}')
        print(f'ключей в коде: {len(keys)}, переведено: {len(keys) - len(missing)}, без перевода: {len(missing)}')
        for k in missing:
            print('  -', k)
    else:
        for k, f in keys.items():
            print(f'{f}\t{k}')
