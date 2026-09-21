import json,sqlite3,re
from pathlib import Path
import argparse
p=argparse.ArgumentParser()
p.add_argument('--database',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
root=a.output
root.mkdir(parents=True,exist_ok=True)
c=sqlite3.connect(a.database.resolve().as_uri()+'?mode=ro',uri=True)
entries={}; counts={}
for i,b,ch,v,text in c.execute('select id,book_number,chapter,block_index,plain_text from bible_blocks order by id'):
 patches=[]
 for m in re.finditer(r'\b(live|lived)\b',text,re.I):
  word=m[0].lower();after=text[m.end():]
  adjective=word=='live' and re.match(r'\s+(?:coal|goat|ox)\b',after,re.I)
  alias='sbpronlived' if word=='lived' else 'sbpronliveadjective' if adjective else 'sbpronliveverb'
  patches.append({'start':m.start(),'end':m.end(),'word':m[0],'alias':alias,'basis':'past-tense lived' if word=='lived' else 'live modifies coal/goat/ox' if adjective else 'KJV live verbal occurrence; contextual first pass'})
  counts[alias]=counts.get(alias,0)+1
 entries[str(i)]={'book':b,'chapter':ch,'verse':v,'text':text,'patches':patches}
(root/'runtime-map.json').write_text(json.dumps({'version':1,'verses':entries},separators=(',',':')))
(root/'context-lexicon.txt').write_text('sbpronliveverb l ˈ ɪ v\nsbpronlived l ˈ ɪ v d\nsbpronliveadjective l ˈ I v\n')
print(counts)
