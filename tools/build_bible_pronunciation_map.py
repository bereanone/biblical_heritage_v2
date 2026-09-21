#!/usr/bin/env python3
"""Read-only Bible/lexicon inputs; reproducible pronunciation candidates, never source edits."""
import argparse, collections, csv, gzip, hashlib, json, re, sqlite3
from html.parser import HTMLParser
from pathlib import Path

WORDS = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*", re.UNICODE)
# These require sentence context even when the lexicon supplies a single reading.
AMBIGUOUS = set('live lives lived read lead leads led bow bows bowed wind winds wound wounds tear tears sow sows close does dove bass row rows use used refuse record present subject object content desert minute entrance separate perfect learned blessed aged beloved'.split())

class Scripture(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.parts=[]; self.notes=0
    def handle_starttag(self, tag, attrs):
        if tag.lower() == 'note': self.notes += 1
    def handle_endtag(self, tag):
        if tag.lower() == 'note': self.notes=max(0,self.notes-1)
    def handle_data(self, data):
        if not self.notes: self.parts.append(data)

def html_text(s):
    p=Scripture(); p.feed(s); p.close(); return ''.join(p.parts)
def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def normalized(s): return ' '.join(s.split())
def lexicon(path):
    out=collections.defaultdict(list)
    for line in path.read_text().splitlines():
        a=line.split()
        if len(a)>1:
            phones=' '.join(a[1:])
            if phones not in out[a[0].lower()]: out[a[0].lower()].append(phones)
    return dict(out)
def matches(text, rules):
    if not rules: return []
    normalized_rules={k.lower():v for k,v in rules.items()}
    pat=re.compile(r'(?<![\w])(?:'+ '|'.join(re.escape(k) for k in sorted(normalized_rules,key=len,reverse=True))+r')(?![\w])',re.I)
    return [{'start':m.start(),'end':m.end(),'text':m[0], 'say_as':normalized_rules[m[0].lower()],'status':'existing_user_rule_unmodified'} for m in pat.finditer(text)]

def build(database, dictionary, output, settings=None):
    output.mkdir(parents=True,exist_ok=True)
    lx=lexicon(dictionary); source_hash=sha(database); dict_hash=sha(dictionary)
    rules={}
    if settings:
        with sqlite3.connect(settings.resolve().as_uri()+'?mode=ro',uri=True) as user:
            row=user.execute("select value from app_settings where key='narration_pronunciations_v1'").fetchone()
            if row: rules=json.loads(row[0])
    conn=sqlite3.connect(database.resolve().as_uri()+'?mode=ro',uri=True)
    books=dict(conn.execute('select book_number,book_name from books'))
    counts=collections.Counter(); unknown=collections.Counter(); issues=collections.Counter(); word_examples=collections.defaultdict(list)
    seen=set(); context_samples=[]
    with gzip.open(output/'verses.jsonl.gz','wt',encoding='utf8') as records, open(output/'review.csv','w',newline='') as rf:
        review=csv.writer(rf); review.writerow(['reference','block_id','word','start','end','reason','text'])
        for block,book,chapter,verse,html,plain in conn.execute('select id,book_number,chapter,block_index,html,plain_text from bible_blocks order by id'):
            assert block not in seen; seen.add(block)
            ref=f'{books[book]} {chapter}:{verse}'; text=html_text(html)
            # Both representations preserved. HTML extraction excludes study notes only.
            mismatch=normalized(text)!=normalized(plain)
            if mismatch:
                issues['source_text_mismatch']+=1
                review.writerow([ref,block,'','','','source_text_mismatch',text])
            tokens=[]
            for m in WORDS.finditer(text):
                word=m[0]; key=word.lower(); candidates=lx.get(key,[]); reason=[]
                if not candidates: reason.append('missing_dictionary'); unknown[key]+=1
                if key in AMBIGUOUS: reason.append('context_review')
                if len(candidates)>1: reason.append('multiple_dictionary_readings')
                counts['words']+=1
                if candidates: counts['dictionary_matches']+=1
                if not reason: counts['unambiguous_dictionary_candidates']+=1
                token={'text':word,'start':m.start(),'end':m.end(),'lexicon_candidates':candidates,'review':reason}
                tokens.append(token)
                for r in reason:
                    issues[r]+=1; review.writerow([ref,block,word,m.start(),m.end(),r,text])
                if reason and len(word_examples[key])<3: word_examples[key].append(ref)
                if key in AMBIGUOUS and len(context_samples)<32:
                    context_samples.append({'reference':ref,'word':word,'start':m.start(),'text':text})
            record={'block_id':block,'book_number':book,'chapter':chapter,'verse':verse,'reference':ref,
                    'source_html':html,'source_plain_text':plain,'speech_source_text':text,
                    'text_sha256':hashlib.sha256(text.encode()).hexdigest(),'source_review':['source_text_mismatch'] if mismatch else [],
                    'tokens':tokens,'user_corrections':matches(text,rules),'status':'first_pass_not_audio_verified'}
            records.write(json.dumps(record,ensure_ascii=False,separators=(',',':'))+'\n'); counts['verses']+=1
    conn.close()
    assert sha(database)==source_hash, 'Source changed during generation'
    with open(output/'unknown_words.csv','w',newline='') as f:
        w=csv.writer(f); w.writerow(['word','occurrences','example_references'])
        for k,n in unknown.most_common(): w.writerow([k,n,'; '.join(word_examples[k])])
    manifest={'schema_version':1,'status':'first_pass_not_audio_verified','source_database':str(database.resolve()),'source_sha256':source_hash,
              'lexicon':str(dictionary.resolve()),'lexicon_sha256':dict_hash,'phoneme_format':'Kokoro model symbols, not portable IPA or spelling replacements',
              'counts':dict(counts),'review_counts':dict(issues),'unknown_unique_words':len(unknown),'saved_user_corrections':rules,
              'source_policy':'Preserve raw HTML and plain text. Extract HTML text excluding notes; flag disagreements, never silently repair source.',
              'application_policy':'Candidates only. Context review and source disagreements block automatic approval. Existing user rules remain separate. No runtime or user database edits.'}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
    (output/'context_samples.json').write_text(json.dumps(context_samples,indent=2,ensure_ascii=False)+'\n')
    (output/'README.md').write_text(f'''# Bible pronunciation first pass\n\nMapped {counts['verses']:,} verses and {counts['words']:,} word occurrences. The bundled dictionary supplies candidates for {counts['dictionary_matches']:,} occurrences.\n\nThis is a reviewable map, not a claim that narration is corrected or every pronunciation has been listened to. Scripture files and saved corrections were not changed.\n\n- `verses.jsonl.gz`: every verse, original source fields, extracted reading text, character offsets, dictionary sound candidates, flags, and separately preserved user overrides.\n- `review.csv`: uncertain occurrences and source disagreements with context.\n- `unknown_words.csv`: missing vocabulary ranked by frequency.\n- `manifest.json`: input hashes, counts, saved correction snapshot, and policies.\n- `context_samples.json`: a bounded sample for local contextual review.\n\nDictionary symbols are specific to this Kokoro model. Do not feed them as ordinary spelling replacements. Runtime connection and listening checks remain separate steps.\n''')
    print(json.dumps({'counts':dict(counts),'review_counts':dict(issues),'unknown_unique':len(unknown)},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--database',type=Path,required=True); p.add_argument('--lexicon',type=Path,required=True); p.add_argument('--output',type=Path,required=True); p.add_argument('--settings',type=Path)
    a=p.parse_args(); build(a.database,a.lexicon,a.output,a.settings)
