"""Add source-attributed lexical articles to a copy of the bundled Bible DB.

The existing Bible text, token mappings and Strong's dictionary are never
updated. BDB paragraphs are indexed only when the source itself starts the
paragraph with one Strong's number and that number maps to a single article.
Ambiguous mappings are omitted rather than silently assigned.
"""
import argparse
import collections
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import sqlite3

ABBOTT_URL='https://github.com/translatable-exegetical-tools/Abbott-Smith'
BDB_URL='https://github.com/BibleAquifer/BDBHebrewLexicon'
BDB_COMMIT='09fbdf34f82c2e020f772cb578a2bcc0383f5a32'

class BdbParagraphs(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth=0
        self.parts=[]
        self.paragraphs=[]
    def handle_starttag(self, tag, attrs):
        if tag=='blockquote':
            self.depth += 1
            if self.depth==1:self.parts=[]
        elif self.depth and tag in ('br','p','li','div'):
            self.parts.append(' ')
    def handle_endtag(self, tag):
        if tag=='blockquote' and self.depth:
            if self.depth==1:
                self.paragraphs.append(re.sub(r'\s+',' ',''.join(self.parts)).strip())
            self.depth -= 1
        elif self.depth and tag in ('p','li','div'):
            self.parts.append(' ')
    def handle_data(self, data):
        if self.depth:self.parts.append(data)

def build(base:Path, abbott:Path, bdb:Path, output:Path):
    if output.exists():raise ValueError(f'output exists: {output}')
    output.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(base,output)
    try:
        with sqlite3.connect(output) as db:
            db.execute('PRAGMA foreign_keys=ON')
            strongs={row[0] for row in db.execute('SELECT strongs_canonical FROM strongs_dictionary')}
            core_counts={name:db.execute(f'SELECT COUNT(*) FROM {name}').fetchone()[0] for name in ('bible_blocks','bible_tokens','strongs_dictionary')}
            db.execute('DROP TABLE IF EXISTS lexicon_entries')
            db.execute('DROP TABLE IF EXISTS lexicon_sources')
            db.execute('CREATE TABLE lexicon_sources (source_code TEXT PRIMARY KEY,title TEXT NOT NULL,source_url TEXT NOT NULL,source_revision TEXT NOT NULL,rights TEXT NOT NULL,method_note TEXT NOT NULL)')
            db.execute('CREATE TABLE lexicon_entries (source_code TEXT NOT NULL,strongs_canonical TEXT NOT NULL,article_id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY (source_code,strongs_canonical),FOREIGN KEY(source_code) REFERENCES lexicon_sources(source_code))')
            db.execute('CREATE INDEX idx_lexicon_entries_strongs ON lexicon_entries(strongs_canonical)')
            with sqlite3.connect(f'file:{abbott}?immutable=1',uri=True) as src:
                provenance=dict(src.execute('SELECT key,value FROM provenance'))
                if src.execute('PRAGMA quick_check').fetchone()[0]!='ok':raise ValueError('Abbott-Smith input corrupt')
                db.execute('INSERT INTO lexicon_sources VALUES (?,?,?,?,?,?)',('abbott_smith','George Abbott-Smith, A Manual Greek Lexicon of the New Testament (1922)',ABBOTT_URL,provenance.get('source_commit',''),provenance.get('license','Public domain'),'Exact TEI Strong IDs; exact bundled-Bible citations; source SHA-256 '+provenance.get('source_sha256','')))
                greek=[]
                for strong,payload in src.execute('SELECT strongs,payload FROM entries'):
                    if strong not in strongs:continue
                    greek.append(('abbott_smith',strong,strong,payload))
                db.executemany('INSERT INTO lexicon_entries VALUES (?,?,?,?)',greek)
            candidates=collections.defaultdict(list)
            source_files=sorted(bdb.glob('*.content.json'))
            if not source_files:raise ValueError('no BDB JSON source files')
            source_digest=hashlib.sha256()
            for path in source_files:
                data=path.read_bytes()
                source_digest.update(path.name.encode()+b'\0'+hashlib.sha256(data).digest())
                for article in json.loads(data):
                    parser=BdbParagraphs();parser.feed(article.get('content',''))
                    for text in parser.paragraphs:
                        match=re.match(r'^\[Str\s*0*(\d+)\]',text)
                        if match:
                            strong=f'H{int(match.group(1)):04d}'
                            if strong in strongs:
                                candidates[strong].append((article['content_id'],text))
            hebrew=[]
            for strong,items in candidates.items():
                if len(items)!=1:continue
                article_id,text=items[0]
                hebrew.append(('bdb',strong,article_id,json.dumps({'text':text},ensure_ascii=False,separators=(',',':'))))
            db.execute('INSERT INTO lexicon_sources VALUES (?,?,?,?,?,?)',('bdb','Brown-Driver-Briggs Hebrew and Aramaic Lexicon',BDB_URL,BDB_COMMIT,'CC0 per BibleAquifer resource metadata','Only uniquely mapped paragraphs beginning with an explicit Strong number; 23 JSON file hash list SHA-256 '+source_digest.hexdigest()+'; ambiguous and absent IDs use the existing Strong gloss.'))
            db.executemany('INSERT INTO lexicon_entries VALUES (?,?,?,?)',hebrew)
            db.execute('PRAGMA user_version=20261005')
            for name,count in core_counts.items():
                if db.execute(f'SELECT COUNT(*) FROM {name}').fetchone()[0]!=count:
                    raise ValueError('core table changed: '+name)
            db.commit()
            db.execute('VACUUM')
            if db.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('output integrity failed')
            print('greek',len(greek),'hebrew',len(hebrew),'ambiguous_hebrew',sum(len(v)>1 for v in candidates.values()),'core',core_counts,'bytes',output.stat().st_size)
    except Exception:
        output.unlink(missing_ok=True)
        raise

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--base',type=Path,required=True)
    p.add_argument('--abbott',type=Path,required=True)
    p.add_argument('--bdb-json',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    build(a.base,a.abbott,a.bdb_json,a.output)
