import copy,hashlib,json,math
from pathlib import Path
from collections import Counter
R=Path(__file__).resolve().parent
source=Path('/Users/deanbowen/Development/StudyBible2/assets/audio/qwen_bible/catalog.json')
old=json.loads(source.read_text());new=json.loads((R/'catalog.quiet-gap-candidate.json').read_text());audit=json.loads((R/'audit.json').read_text())
assert audit['summary']['state']=='complete' and not audit['summary']['failed']
assert hashlib.sha256(source.read_bytes()).hexdigest()==audit['summary']['source_catalog_sha256']
assert len(old['chapters'])==len(new['chapters'])==1189
count=0;changes=0;priority=[];review=[];tails=[]
for before,after,result in zip(old['chapters'],new['chapters'],audit['chapters']):
 assert (before['book'],before['chapter'])==(after['book'],after['chapter'])==(result['book'],result['chapter'])
 assert before['audioSha256']==after['audioSha256']==result['audio_sha256']
 assert [r['verse'] for r in before['verseStarts']]==[r['verse'] for r in after['verseStarts']]
 starts=[r['seconds'] for r in after['verseStarts']]
 assert all(math.isfinite(s) and 0<=s<after['durationSeconds'] for s in starts)
 assert all(a<b for a,b in zip(starts,starts[1:]))
 original=copy.deepcopy(before);candidate=copy.deepcopy(after)
 for key in ['verseStarts','timingReview']:original.pop(key,None);candidate.pop(key,None)
 assert original==candidate
 for b,c,r in zip(before['verseStarts'],after['verseStarts'],result['verses']):
  count+=1;delta=round((c['seconds']-b['seconds'])*1000)
  assert abs(delta)<=250
  row={'book':before['book'],'chapter':before['chapter'],'verse':b['verse'],'old_seconds':b['seconds'],'candidate_seconds':c['seconds'],'shift_ms':delta,'edge_peak_rms_dbfs':r['edge_peak_rms_dbfs'],'flags':r['flags']}
  if delta:changes+=1
  if any(f!='cut_near_active_audio' for f in r['flags']):review.append(row)
  if r['edge_peak_rms_dbfs']>-35 and abs(delta)>=30:priority.append(row)
 if result['last_20ms_rms_dbfs']>-50:tails.append({'book':before['book'],'chapter':before['chapter'],'tail_rms_dbfs':result['last_20ms_rms_dbfs']})
assert count==31102 and changes==audit['summary']['candidate_changed_boundaries']
result={'valid':True,'chapters':1189,'verse_boundaries':count,'changed_candidates':changes,'uncertain_boundary_rows':len(review),'high_energy_shift_candidates':len(priority),'chapter_tails_to_review':len(tails),'source_catalog_unchanged':True,'audio_hashes_preserved':True,'chapter_metadata_preserved':True,'verse_identity_and_order_preserved':True,'strict_monotonicity':True,'maximum_shift_ms':250,'listening_approved':False,'installed':False}
(R/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
(R/'priority-review.json').write_text(json.dumps({'high_energy_candidates':priority,'uncertain_boundaries':review,'chapter_tails':tails},indent=2)+'\n')
print(json.dumps(result,indent=2))
