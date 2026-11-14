#!/usr/bin/env python3
"""Route UI literals through L10n and emit the source-key manifest for static catalogs."""
import json,re,plistlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# Files containing persisted identifiers, paths or language endonyms rather than UI copy.
skip={'AppBrand.swift','ReceiverNamePreference.swift','EngineLocator.swift','AppLanguage.swift','L10n.swift'}
keys=set()
pattern=re.compile(r'"((?:[^"\\]|\\.)*)"')
def convert(raw):
 out='';args=[];i=0
 while i<len(raw):
  if raw.startswith('\\(',i):
   j=i+2;depth=1;start=j
   while j<len(raw) and depth:
    if raw[j]=='(':depth+=1
    elif raw[j]==')':depth-=1
    j+=1
   if depth:raise ValueError('Unbalanced interpolation: '+raw)
   args.append(raw[start:j-1]);out+=f'%{len(args)}$@';i=j
  else:
   out+=raw[i];i+=1
 return json.loads('"'+out+'"'),args
for p in (ROOT/'AirMirror').rglob('*.swift'):
 text=p.read_text()
 if p.name in skip:
  if p.name=='AppLanguage.swift':keys.add('跟随系统')
  continue
 def replace(m):
  raw=m[1]
  if not re.search('[\u4e00-\u9fff]',raw):return m[0]
  if p.name=='NativeMenuLocalization.swift' and raw in {'拷贝','拷貝'}:return m[0]
  if raw.startswith('# 镜投'):return m[0]
  if p.name=='WindowPasteTargetApp.swift' and 'static let mirror' in text[text.rfind('\n',0,m.start())+1:m.start()]:return m[0]
  key,args=convert(raw);keys.add(key)
  if p.name=='NativeMenuLocalization.swift' or re.search(r'L10n\.tr\(\s*$',text[max(0,m.start()-20):m.start()]):return m[0]
  encoded=json.dumps(key,ensure_ascii=False)
  return 'L10n.tr('+encoded+''.join(', String(describing: '+arg+')' for arg in args)+')'
 text=pattern.sub(replace,text)
 p.write_text(text)
# Privacy copy is translated paragraph by paragraph; license originals stay verbatim.
keys.update((ROOT/'AirMirror/PrivacyPolicy.txt').read_text().strip().split('\n\n'))
info=plistlib.loads((ROOT/'AirMirror/Info.plist').read_bytes())
keys.update(v for k,v in info.items() if k.endswith('UsageDescription'))
rows=[{'id':i+1,'key':key} for i,key in enumerate(sorted(keys))]
(ROOT/'Localization/Source.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print('Localization source keys:',len(rows))
