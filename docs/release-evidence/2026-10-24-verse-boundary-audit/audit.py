"""Resumable waveform triage of every shipped verse boundary. Never promotes.
Quiet gaps are acoustic evidence, not semantic proof of a correct verse split.
"""
import argparse, concurrent.futures, copy, fcntl, hashlib, json, os, subprocess, time
from pathlib import Path
from collections import Counter
import numpy as np

ROOT=Path(__file__).resolve().parent
REPO=Path('/Users/deanbowen/Development/StudyBible2')
CATALOG=REPO/'assets/audio/qwen_bible/catalog.json'
RATE=24000
BIN=120 # 5 ms
VERSION=1

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):
    t=p.with_suffix(p.suffix+'.tmp');t.write_text(json.dumps(v,indent=2));t.replace(p)
def db(x): return round(float(20*np.log10(max(float(x),1/32768))),2)
def quiet_runs(quiet):
    edges=np.diff(np.r_[False,quiet,False].astype(np.int8))
    return [(a,b) for a,b in zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)) if b-a>=8]

def boundary(rms,seconds,previous,next_seconds):
    center=int(seconds/.005)
    lo=max(0,int((seconds-.35)/.005));hi=min(len(rms),int((seconds+.15)/.005)+1)
    local=rms[lo:hi]
    if not len(local): raise ValueError('Boundary beyond decoded audio')
    threshold=min(10**(-50/20),max(10**(-66/20),float(np.percentile(local,15))*2))
    edge=rms[max(0,center-2):min(len(rms),center+3)]
    active=float(np.max(edge))>threshold
    gaps=[]
    for a,b in quiet_runs(local<=threshold):
        start=(lo+a)*.005;end=(lo+b)*.005
        # Do not invent a silence at the search window edge or cross neighbors.
        target=min(max(seconds,start+.015),end-.020)
        if previous+.03 < target < next_seconds-.03 and abs(target-seconds)<=.25:
            gaps.append((abs(target-seconds),target,start,end))
    gaps.sort()
    flags=[]
    if active: flags.append('cut_near_active_audio')
    result={'old_seconds':seconds,'candidate_seconds':seconds,'edge_peak_rms_dbfs':db(np.max(edge)),
            'quiet_threshold_dbfs':db(threshold),'flags':flags,'status':'unchanged_needs_listening'}
    if not gaps:
        flags.append('no_suitable_nearby_quiet_gap');return result
    distance,target,start,end=gaps[0]
    if len(gaps)>1 and gaps[1][0]-distance<.060:
        flags.append('ambiguous_quiet_gaps');return result
    # Do not move a cut forward into the verse merely because a later word gap is quiet.
    if target-seconds>.030:
        flags.append('only_later_gap_needs_word_review');return result
    result.update(candidate_seconds=round(target,3),quiet_gap=[round(start,3),round(end,3)],
                  shift_ms=round((target-seconds)*1000),status='quiet_gap_candidate_needs_listening')
    return result

def process(ch,identity):
    key=f'{ch["book"]:02d}-{ch["chapter"]:03d}'
    out=ROOT/'chapters'/f'{key}.json'
    if out.exists():
        old=json.loads(out.read_text())
        if old.get('identity')==identity and old.get('audio_sha256')==ch['audioSha256']:
            return old
    source=REPO/ch['asset']
    if sha(source)!=ch['audioSha256']:raise ValueError(f'Source checksum mismatch {key}')
    run=subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-threads','1','-i',str(source),'-f','s16le','-acodec','pcm_s16le','-ar','24000','-ac','1','pipe:1'],capture_output=True,timeout=180)
    if run.returncode:raise ValueError(run.stderr.decode()[-1000:])
    samples=np.frombuffer(run.stdout,dtype='<i2')
    if abs(len(samples)/RATE-ch['durationSeconds'])>.1:raise ValueError(f'Duration mismatch {key}')
    x=samples[:len(samples)//BIN*BIN].reshape(-1,BIN).astype(np.float32)/32768
    rms=np.sqrt(np.mean(x*x,axis=1));del x
    verses=ch['verseStarts'];rows=[]
    for i,v in enumerate(verses):
        record=boundary(rms,v['seconds'],verses[i-1]['seconds'] if i else -.1,
                        verses[i+1]['seconds'] if i+1<len(verses) else ch['durationSeconds'])
        record.update(verse=v['verse'])
        if ch.get('timingSimilarity',1)<.90:
            record['flags'].append('low_alignment_similarity')
            record['candidate_seconds']=record['old_seconds']
            record['shift_ms']=0
            record['status']='unchanged_needs_word_review'
        rows.append(record)
    starts=[v['candidate_seconds'] for v in rows]
    if any(a>=b for a,b in zip(starts,starts[1:])):raise ValueError(f'Nonmonotonic candidate {key}')
    record={'identity':identity,'chapter_key':key,'audio_sha256':ch['audioSha256'],
            'book':ch['book'],'chapter':ch['chapter'],'decoded_seconds':len(samples)/RATE,
            'last_20ms_rms_dbfs':db(np.sqrt(np.mean((samples[-480:].astype(float)/32768)**2))),
            'verses':rows}
    save(out,record);return record

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--pilot',action='store_true');args=ap.parse_args()
    ROOT.mkdir(exist_ok=True);(ROOT/'chapters').mkdir(exist_ok=True)
    lock=open(ROOT/'writer.lock','w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    before=sha(CATALOG);catalog=json.loads(CATALOG.read_text())
    identity=hashlib.sha256((before+sha(Path(__file__))).encode()).hexdigest()
    chapters=[c for c in catalog['chapters'] if not args.pilot or (c['book']==2 and c['chapter']==20)]
    completed=[];failed={};started=time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        pending={pool.submit(process,c,identity):c for c in chapters}
        for future in concurrent.futures.as_completed(pending):
            ch=pending[future];key=f'{ch["book"]:02d}-{ch["chapter"]:03d}'
            try: completed.append(future.result())
            except Exception as e:failed[key]=str(e)
            state={'state':'running','pid':os.getpid(),'total':len(chapters),'completed':len(completed),'failed':failed,'elapsed_seconds':round(time.time()-started),'last_chapter':key}
            save(ROOT/'status.json',state)
            if len(completed)%100==0 or args.pilot:print(json.dumps(state),flush=True)
    completed.sort(key=lambda r:(r['book'],r['chapter']))
    counts=Counter(f for c in completed for v in c['verses'] for f in v['flags'])
    changed=sum(int(v['candidate_seconds']!=v['old_seconds']) for c in completed for v in c['verses'])
    state.update(state='complete' if not failed else 'incomplete',verses=sum(len(c['verses']) for c in completed),candidate_changed_boundaries=changed,flags=dict(counts),source_catalog_sha256=before,source_catalog_unchanged=sha(CATALOG)==before,limitation='Acoustic triage only. No words or boundaries are listening-approved. No app files changed.')
    save(ROOT/'status.json',state)
    save(ROOT/'audit.json',{'summary':state,'chapters':completed})
    if not args.pilot and not failed:
        if len(completed)!=1189 or state['verses']!=31102:raise ValueError('Incomplete Bible coverage')
        bykey={(r['book'],r['chapter']):r for r in completed}
        candidate=copy.deepcopy(catalog)
        candidate['status']='ISOLATED_CANDIDATE_NOT_LISTENING_REVIEWED_NOT_FOR_RELEASE'
        for c in candidate['chapters']:
            result=bykey[c['book'],c['chapter']]
            c['verseStarts']=[{'verse':v['verse'],'seconds':v['candidate_seconds']} for v in result['verses']]
            c['timingReview']='waveform_gap_candidate_requires_word_and_listening_review'
        save(ROOT/'catalog.quiet-gap-candidate.json',candidate)
    print(json.dumps(state),flush=True)
if __name__=='__main__':main()
