"""Fail closed until an actual native capture has been supplied and reviewed."""
from pathlib import Path
import json
import subprocess

source = Path(__file__).parent / 'public' / 'live-take.mp4'
if not source.is_file():
    raise SystemExit('Missing actual footage: public/live-take.mp4. Record the native workflow; do not substitute screenshots or diagrams.')
result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(source)], check=True, capture_output=True, text=True)
duration = float(json.loads(result.stdout)['format']['duration'])
if duration < 44:
    raise SystemExit(f'Actual take is {duration:.2f}s; this composition requires at least 44s. Retune the source/composition together after reviewing the real recording.')
print(f'Actual footage present, {duration:.2f}s. This validates media length only; review its native actions and labels before publishing.')

pickup = Path(__file__).parent / 'public' / 'live-reply.mp4'
if not pickup.is_file():
    raise SystemExit('Missing actual reply-view pickup: public/live-reply.mp4')
probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(pickup)], check=True, capture_output=True, text=True)
if float(json.loads(probe.stdout)['format']['duration']) < 10:
    raise SystemExit('Reply pickup needs 10 seconds for the two-second trim and eight-second ending.')
