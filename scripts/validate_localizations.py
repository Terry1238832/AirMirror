#!/usr/bin/env python3
"""Check offline localization coverage, format safety, and permission copy."""
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {'zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'fr', 'de', 'es', 'pt-BR', 'it', 'ru', 'ar', 'hi', 'id'}
catalog = json.loads((ROOT / 'AirMirror/Localizable.xcstrings').read_text())
source = {item['key'] for item in json.loads((ROOT / 'Localization/Source.json').read_text())}
assert catalog['sourceLanguage'] == 'zh-Hans'
assert set(catalog['strings']) == source, 'Catalog and source inventory differ'
token = re.compile(r'%\d+\$@')
for key, entry in catalog['strings'].items():
    assert set(entry['localizations']) == LANGUAGES, f'Incomplete languages: {key}'
    expected = sorted(token.findall(key))
    for lang, translation in entry['localizations'].items():
        unit = translation['stringUnit']
        value = unit['value']
        assert unit['state'] == 'translated' and value.strip(), (key, lang)
        assert sorted(token.findall(value)) == expected, f'Invalid placeholders: {lang}: {key}'
        assert '%' not in token.sub('', value), f'Unexpected format sequence: {lang}: {key}'
        assert not re.search(r'\[AM[A-Z]+\d{4}\]|⟦\d+⟧', value), f'Translation marker: {lang}: {key}'

info = plistlib.loads((ROOT / 'AirMirror/Info.plist').read_bytes())
permission_keys = [key for key in info if key.endswith('UsageDescription')]
for lang in LANGUAGES:
    text = (ROOT / f'AirMirror/{lang}.lproj/InfoPlist.strings').read_text()
    pairs = dict((json.loads(a), json.loads(b)) for a,b in re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");', text))
    for name in permission_keys:
        assert pairs[name] == catalog['strings'][info[name]]['localizations'][lang]['stringUnit']['value'], (lang,name)
    assert pairs['CFBundleName'] == {'zh-Hans':'镜投','zh-Hant':'鏡投'}.get(lang, 'AirMirror')
print(f'PASS: {len(source)} strings × {len(LANGUAGES)} languages, placeholders and localized permissions')
