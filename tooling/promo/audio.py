"""Free local narration plus a quiet, original synthesized soundtrack."""
import argparse, array, json, math, subprocess, wave
parser=argparse.ArgumentParser()
parser.add_argument("--narration",type=str)
args=parser.parse_args()
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
WORK=Path('/private/tmp/mooddare-promo/audio')
WORK.mkdir(parents=True,exist_ok=True)
plan=json.loads((ROOT/'design/promo/mooddare-first-look/storyboard.json').read_text())
RATE=48000
length=int(plan['duration']*RATE)
voice=array.array('f',[0])*length
segments=[]
if args.narration:
    config_path=Path(args.narration).resolve()
    config=json.loads(config_path.read_text())
    source=config_path.parent/config['source']
    import hashlib
    if hashlib.sha256(source.read_bytes()).hexdigest()!=config['sha256']:
        raise RuntimeError('Narration source changed; review the sentence cuts before exporting.')
    wav=WORK/'imported-source.wav'
    subprocess.run(['afconvert','-f','WAVE','-d',f'LEI16@{RATE}',str(source),str(wav)],check=True)
    with wave.open(str(wav),'rb') as f:
        channels=f.getnchannels(); raw=array.array('h',f.readframes(f.getnframes()))
    clips=config['segments']
else:
    clips=plan['narration']
for i,clip in enumerate(clips):
    if args.narration:
        lo=round(clip['sourceStart']*RATE)*channels
        hi=round(clip['sourceEnd']*RATE)*channels
        if not 0<=lo<hi<=len(raw): raise RuntimeError('Invalid source cut')
        samples=raw[lo:hi]
    else:
        aiff=WORK/f'voice-{i}.aiff';wav=WORK/f'voice-{i}.wav'
        subprocess.run(['say','-v',plan['voice'],'-r',str(plan['voiceRate']),'-o',str(aiff),clip['text']],check=True)
        subprocess.run(['afconvert','-f','WAVE','-d',f'LEI16@{RATE}',str(aiff),str(wav)],check=True)
        with wave.open(str(wav),'rb') as f:
            channels=f.getnchannels();samples=array.array('h',f.readframes(f.getnframes()))
    duration=len(samples)/channels/RATE
    next_start=clips[i+1]['start'] if i+1<len(clips) else plan['duration']
    if clip['start']+duration>next_start:raise RuntimeError(f'Narration overlaps next scene: {clip}')
    start=int(clip['start']*RATE)
    peak=max(abs(x) for x in samples) or 1
    gain=.70*32767/peak
    count=len(samples)//channels
    for j in range(count):
        # Four-millisecond edge fades remove clicks without slowing or pitching speech.
        fade=min(1,j/(RATE*.004),(count-1-j)/(RATE*.004))
        if start+j<length:voice[start+j]=sum(samples[j*channels:(j+1)*channels])/channels/32768*gain*fade
    segments.append((clip['start'],clip['start']+duration,clip['text']))
    print(f'Voice {i}: {duration:.2f}s at {clip["start"]}s',flush=True)
with wave.open(str(WORK/'voice-paced.wav'),'wb') as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
    f.writeframes(array.array('h',[round(max(-.98,min(.98,x))*32767) for x in voice]).tobytes())
# Soft original Cmaj7 / Am7 / Fmaj7 / G6 arpeggios. No stock music.
music=array.array('f',[0])*length
chords=[[48,55,59,64],[45,52,55,60],[41,48,52,57],[43,50,55,59]]
for beat in range(44):
    start=beat*.5;notes=chords[(beat//11)%4];note=notes[beat%4]+12
    freq=440*2**((note-69)/12)
    for j in range(int(1.8*RATE)):
        k=int(start*RATE)+j
        if k>=length:break
        t=j/RATE;env=min(1,t/.018)*math.exp(-t*3.3)
        music[k]+=.033*env*(math.sin(2*math.pi*freq*t)+.20*math.sin(2*math.pi*freq*2*t))
# A small two-note sonic wink at the opening and closing eye movement.
for start in [1.30,18.50]:
    for offset,note in [(0,76),(.12,81)]:
        freq=440*2**((note-69)/12)
        for j in range(int(.6*RATE)):
            k=int((start+offset)*RATE)+j
            if k>=length:break
            t=j/RATE;music[k]+=.05*min(1,t/.008)*math.exp(-8*t)*math.sin(2*math.pi*freq*t)
output=array.array('h')
peak=0
for i in range(length):
    t=i/RATE;fade=min(1,t/.35,(22-t)/.65)
    speaking=any(a-.1<=t<=b+.15 for a,b,_ in segments)
    value=voice[i]+music[i]*(.45 if speaking else 1)*max(0,fade)
    peak=max(peak,abs(value))
    sample=round(max(-.98,min(.98,value))*32767)
    output.extend([sample,sample])
with wave.open(str(WORK/'promo-mix.wav'),'wb') as f:
    f.setnchannels(2);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(output.tobytes())
def stamp(t):
    ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
srt='\n\n'.join(f'{i+1}\n{stamp(a)} --> {stamp(b)}\n{text.replace("Mood dare.","MoodDare.")}' for i,(a,b,text) in enumerate(segments))+'\n'
(ROOT/'design/promo/mooddare-first-look/captions.srt').write_text(srt)
(WORK/'timing.json').write_text(json.dumps(segments,indent=2))
print(f'Mixed 22 seconds, stereo 48 kHz, peak {peak:.3f}; no clipping',flush=True)
