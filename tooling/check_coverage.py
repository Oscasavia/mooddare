"""Check executable Dart lines in Flutter's LCOV report (no exclusions)."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--minimum', type=float, default=75)
parser.add_argument('--file', default='coverage/lcov.info')
args = parser.parse_args()
lines = {}
source = None
for entry in Path(args.file).read_text().splitlines():
    if entry.startswith('SF:'):
        source = entry[3:]
    elif entry.startswith('DA:') and source is not None:
        number, hits, *_ = entry[3:].split(',')
        key = (source, int(number))
        lines[key] = lines.get(key, False) or int(hits) > 0
if not lines:
    raise SystemExit('Coverage report has no executable lines.')
covered = sum(lines.values())
percent = 100 * covered / len(lines)
print(f'Dart line coverage: {covered}/{len(lines)} ({percent:.2f}%)')
if percent < args.minimum:
    raise SystemExit(f'Coverage must be at least {args.minimum:g}%.')
