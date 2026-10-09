"""Render local Apple narration; run from this directory on macOS."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parent
lines = (root / 'narration.txt').read_text().strip().split('\n\n')
assert len(lines) == 8
args = ['ffmpeg', '-v', 'error']
for index, line in enumerate(lines):
    target = root / 'public' / f'voice-{index}.aiff'
    subprocess.run(['say', '-v', 'Samantha', '-r', '175', '-o', str(target), line], check=True)
    args += ['-i', str(target)]
filters = ';'.join(f'[{i}:a]atempo=1.15,apad,atrim=0:8,asetpts=PTS-STARTPTS[a{i}]' for i in range(8))
filters += ';' + ''.join(f'[a{i}]' for i in range(8)) + 'concat=n=8:v=0:a=1[out]'
subprocess.run(args + ['-filter_complex', filters, '-map', '[out]', '-ar', '48000', '-ac', '1', '-c:a', 'libmp3lame', '-q:a', '3', '-y', str(root / 'public' / 'narration.mp3')], check=True)
