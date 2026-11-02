"""Rebuild a staged book with one narrator and the reader's prepared speech text.

Never installs or edits the source package. A plan preserves every source cue.
Generation is serialized with the existing local voice engine lock.
"""
from pathlib import Path
import argparse, fcntl, functools, hashlib, importlib, json, math, os, subprocess, sys, time


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path, value):
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2))
    temporary.replace(path)


def synthesize(backend, reference, transcript, text):
    # One complete paragraph, including its references, uses the book narrator.
    engine = backend.load_model(backend.BASE)
    previous = engine.generate_voice_clone
    pacing = backend.pace_bracketed_annotations
    def bounded(**kwargs):
        kwargs['max_new_tokens'] = min(8192, max(512, math.ceil((len(kwargs['text'].split()) / 1.5 + 12) * 12.5)))
        return previous(**kwargs)
    try:
        engine.generate_voice_clone = bounded
        backend.pace_bracketed_annotations = lambda units: units
        return backend.clone(reference, transcript, text, 0.0, False)
    finally:
        engine.generate_voice_clone = previous
        backend.pace_bracketed_annotations = pacing


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--plan', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--backend', type=Path, required=True)
    ap.add_argument('--engine-lock', type=Path, required=True)
    ap.add_argument('--wait-status', type=Path)
    ap.add_argument('--minimum-prior-jobs', type=int, default=0)
    args = ap.parse_args()
    plan = json.loads(args.plan.read_text())
    assert {'SC': 'SC3', 'WOR': 'Baritone1'}[plan['book_code']] == plan['voice']
    ref = Path(plan['reference'])
    assert sha(ref) == plan['reference_sha256']
    assert sha(ref.with_suffix('.txt')) == plan['transcript_sha256']
    args.output.mkdir(parents=True, exist_ok=True)
    status = args.output / 'status.json'
    state = {'state': 'waiting_for_existing_narration', 'pid': os.getpid(), 'completed_cues': 0,
             'total_cues': sum(len(t['cues']) for t in plan['tracks']), 'voice': plan['voice'],
             'plan_sha256': sha(args.plan), 'installed': False, 'human_listening': False}
    save(status, state)
    with (args.output / 'worker.lock').open('w') as own:
        fcntl.flock(own, fcntl.LOCK_EX | fcntl.LOCK_NB)
        while args.wait_status:
            prior = json.loads(args.wait_status.read_text())
            if prior.get('state') == 'complete_pending_audio_quality' and prior.get('jobs', 0) >= args.minimum_prior_jobs:
                break
            time.sleep(15)
        with args.engine_lock.open('r') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            import numpy as np
            import soundfile as sf
            sys.path.insert(0, str(args.backend))
            backend = importlib.import_module('backend')
            backend.load_model = functools.lru_cache(maxsize=1)(backend.load_model)
            cache = args.output / 'cues';cache.mkdir(exist_ok=True)
            backend.OUTPUTS = args.output / 'raw-generation'
            reference, transcript = backend.profile_by_name(plan['voice'])
            assert sha(reference) == plan['reference_sha256']
            manifest = {k: plan[k] for k in ['title','book_code','voice','reference_sha256','transcript_sha256','source_manifest_sha256','speech_rules_sha256']}
            manifest.update(total_chapters=len(plan['tracks']), complete=False, voice_policy={'all_text': plan['voice']},
                            narration_policy='single-narrator-v1', human_listening='pending', tracks=[])
            # Chapter three contains the reported [24] example; produce it first for review.
            tracks = sorted(plan['tracks'], key=lambda t: (t['chapter'] != 3, t['chapter']))
            for t in tracks:
                assert sha(t['source_file']) == t['source_sha256']
                original, source_rate = sf.read(t['source_file'], dtype='float32')
                if original.ndim == 2: original = original.mean(axis=1)
                arrays = []; cues = []; samples = 0
                for ci, c in enumerate(t['cues']):
                    source = c['source']; speech = c['spoken_text']
                    state.update(state='building', chapter=t['chapter'], cue=ci+1, updated=time.time())
                    save(status, state)
                    dest = cache / (c['id']+'.flac'); receipt = dest.with_suffix('.json')
                    old = json.loads(receipt.read_text()) if receipt.exists() else {}
                    if dest.exists() and old.get('sha256') == sha(dest) and old.get('spoken_text') == speech and old.get('plan_sha256') == sha(args.plan):
                        audio, rate = sf.read(dest, dtype='float32')
                    else:
                        if c['reuse']:
                            start=round(source['start_ms']*source_rate/1000);end=round(source['end_ms']*source_rate/1000)
                            audio=original[start:end];rate=source_rate
                        elif not speech:
                            audio=np.zeros(240,dtype='float32');rate=24000
                        else:
                            generated=synthesize(backend,reference,transcript,speech)
                            audio,rate=sf.read(generated,dtype='float32')
                        if rate != 24000:
                            from scipy.signal import resample_poly
                            from fractions import Fraction
                            ratio=Fraction(24000,rate);audio=resample_poly(audio,ratio.numerator,ratio.denominator);rate=24000
                        assert audio.ndim==1 and len(audio)>0 and np.isfinite(audio).all()
                        peak=float(np.max(np.abs(audio)))
                        assert peak > .001 or not speech
                        audio=audio*min(1.,.97/peak) if peak else audio
                        sf.write(dest,audio,rate,subtype='PCM_24')
                        save(receipt,{'sha256':sha(dest),'voice':plan['voice'],'reference_sha256':plan['reference_sha256'],
                                      'spoken_text':speech,'source_text':source['text'],'reused':c['reuse'],
                                      'duration_seconds':len(audio)/rate,'plan_sha256':sha(args.plan),'human_listening':False})
                    assert rate==24000
                    if arrays:
                        gap=np.zeros(18000,dtype='float32');arrays.append(gap);samples+=len(gap)
                    start=round(samples/24);samples+=len(audio);end=round(samples/24)
                    arrays.append(audio)
                    cue={k:v for k,v in source.items() if k not in ['start_ms','end_ms','voice_segments','phrases','routed_egw_spans']}
                    cue.update(start_ms=start,end_ms=end,spoken_text=speech,voice_segments=[{'voice':plan['voice'],'text':speech,'start_ms':start,'end_ms':end,'reference_sha256':plan['reference_sha256']}])
                    cues.append(cue);state['completed_cues']+=1;save(status,state)
                master=args.output/f"chapter-{t['chapter']:02d}.wav";sf.write(master,np.concatenate(arrays),24000,subtype='PCM_24')
                mp3=args.output/f"track-{t['chapter']:02d}.mp3"
                subprocess.run(['/opt/homebrew/bin/ffmpeg','-nostdin','-y','-v','error','-i',str(master),'-af','loudnorm=I=-22:TP=-2:LRA=7','-ar','24000','-c:a','libmp3lame','-b:a','64k',str(mp3)],check=True)
                subprocess.run(['/opt/homebrew/bin/ffmpeg','-nostdin','-v','error','-xerror','-i',str(mp3),'-f','null','-'],check=True)
                track={'chapter':t['chapter'],'title':t['title'],'voice':plan['voice'],'file':mp3.name,'sha256':sha(mp3),'cues':cues,'duration_seconds':samples/24000}
                assert [c['text'] for c in cues]==[c['source']['text'] for c in t['cues']]
                manifest['tracks'].append(track);manifest['tracks'].sort(key=lambda t:t['chapter'])
                save(args.output/'audio-manifest.json',manifest)
            manifest['complete']=True;save(args.output/'audio-manifest.json',manifest)
            state.update(state='complete_pending_quality_review',updated=time.time());save(status,state)

if __name__=='__main__':
    main()
