"""Editorial guardrails. Automated checks assist, but never replace human review."""
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'content/dares.json'
DART=ROOT/'lib/features/dares/domain/curated_dares.dart'
EXPECTED=set('Happy|Relaxed|Calm|Energetic|Sad|Productive|Grateful|Creative|Curious|Bored|Silly|Goofy|Christmas|New Year|Brave|Adventurous|Spontaneous|Social|Rebellious|Confident|Romantic|Flirty|Spicy|Mysterious|Legendary|Unstoppable|Visionary|Main Character|Nostalgic'.split('|'))
# Boundary matching avoids rejecting innocent substrings. This is deliberately
# a small editorial regression guard, not a universal profanity detector.
PROFANITY=re.compile(r'\b(fuck\w*|shit\w*|bitch\w*|asshole\w*|bastard\w*)\b',re.I)
RISK=re.compile(r'hold (?:your |the )?breath|hyperventilat|high.intensity|spiciest|prolonged eye contact|without consent|while driving|film strangers',re.I)
CLAIM=re.compile(r'\b(cure|treat|heal|fix|guarantee)\b.{0,50}\b(anxiety|depression|trauma|mood|panic)\b',re.I)
NUMBERS={'one':1,'two':2,'three':3,'five':5,'ten':10,'fifteen':15,'twenty':20,'thirty':30,'sixty':60}
DURATION=re.compile(r'\b(\d+|one|two|three|five|ten|fifteen|twenty|thirty|sixty)[ -]+(second|minute|hour)s?\b',re.I)
def validate(data):
    errors=[]
    if data.get('version')!=1:errors.append('Unsupported catalog version')
    moods=data.get('moods',{})
    if set(moods)!=EXPECTED:errors.append('Mood names differ from the reviewed card list')
    for name,entry in moods.items():
        dares=entry.get('dares',[])
        if entry.get('pack') not in ['basic','daring','epic']:errors.append(f'{name}: invalid pack')
        if not isinstance(dares,list) or len(dares)<10:errors.append(f'{name}: needs at least ten dares');continue
        if len({str(x).strip().casefold() for x in dares})!=len(dares):errors.append(f'{name}: duplicate dares')
        for i,text in enumerate(dares):
            label=f'{name} #{i+1}'
            if not isinstance(text,str) or not text.strip():errors.append(f'{label}: empty/non-text');continue
            if text!=text.strip() or '\n' in text:errors.append(f'{label}: whitespace')
            if len(text)>260 or len(text.split())>45:errors.append(f'{label}: too long; split or simplify')
            if not re.search(r'\b(photo|photograph|video|record|show|capture)\b',text,re.I):errors.append(f'{label}: missing capture outcome')
            for check,reason in [(PROFANITY,'language'),(RISK,'unsafe instruction'),(CLAIM,'treatment promise')]:
                if check.search(text):errors.append(f'{label}: {reason}')
            # This collection uses counts, not timed long tasks. Longer activities
            # explicitly happen off-camera; do not silently approve new timings.
            for match in DURATION.finditer(text):
                number,unit=match.groups();value=int(number) if number.isdigit() else NUMBERS[number.lower()]
                seconds=value*{'second':1,'minute':60,'hour':3600}[unit.lower()]
                if seconds>30:errors.append(f'{label}: duration exceeds the capture limit')
    return errors

def generate(data):
    # Paid content stays out of the offline client; previews remain locked.
    entries={name.lower():entry['dares'] for name,entry in data['moods'].items() if entry['pack']=='basic'}
    entries['chill']=entries['relaxed'];entries['energized']=entries['energetic']
    lines=['// Generated from content/dares.json by tooling/dares/catalog.py.','// Edit the reviewed source, regenerate, then run dart format.','const curatedDares = <String, List<String>>{']
    for name,dares in entries.items():
        lines.append(f'  {json.dumps(name)}: [')
        lines.extend('    '+json.dumps(text,ensure_ascii=False).replace('$',r'\$')+',' for text in dares)
        lines.append('  ],')
    lines.append('};')
    DART.write_text('\n'.join(lines)+'\n')
if __name__=='__main__':
    data=json.loads(SOURCE.read_text());errors=validate(data)
    if errors:print('\n'.join(errors));sys.exit(1)
    if '--generate' in sys.argv:generate(data)
    print(f"Reviewed catalog checks passed: {len(data['moods'])} collections, {sum(len(x['dares']) for x in data['moods'].values())} dares.")
