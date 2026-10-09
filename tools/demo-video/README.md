# Explanatory motion demo

64 seconds, 1920×1080, eight scenes. Manrope type (OFL license included), frame-driven spring reveals, moving message/receipt markers, timed state changes, explanatory captions and local Apple voice narration. Scenes 1–7 are explicitly labeled workflow illustrations, not footage of actual transfers. Scene 8 uses actual native simulator screenshots. Timing is editorial, never a latency measurement.

## Reproduce

```sh
cd tools/demo-video
npm ci
npm run typecheck
npm run studio
npm run render
npm run poster
```

The renderer may download Chrome Headless Shell on first use. To use an installed Chrome, append `-- --browser-executable='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'` to render/poster. The committed narration MP3 is used during rendering; `python3 make-narration.py` regenerates it on macOS with installed Samantha voice and ffmpeg. Raw AIFF segments are local generated intermediates. App captures in public/ are copied from docs/media/. No video dependency is used by the native app.

Sources consulted: [Remotion API](https://www.remotion.dev/docs/api), [fonts](https://www.remotion.dev/docs/fonts-api/), [CLI](https://www.remotion.dev/docs/cli/render). Alternatives: [Motion Canvas](https://motioncanvas.io/docs/) for procedural diagrams; [Screen Studio](https://screen.studio/guide/exporting-the-video) for editing actual interactions. Remotion was selected for source-controlled scenes and repeatable type/motion rendering; package licensing is separate from the bundled font license, consult Remotion's terms before wider/team commercial use.

The former static saved-history clip remains historical material, not the accepted explanatory-demo design.

README preview reproduction (from repository root, requires ffmpeg):

```sh
ffmpeg -v error -ss 16 -t 16 -i docs/media/rescue-story.mp4 \
  -filter_complex "fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 -y docs/media/workflow-preview.gif
```


## Live native revision (in progress)

The user rejected the illustrated film as the desired demo medium. The next cut must show actual native interaction footage. `src/live.tsx` is a provisional dark-console framing composition, separate from the historical illustrated film. Its camera timing must be retuned against observed actions in the real take, not treated as evidence of events.

Record a continuous fresh **training** workflow in a separate simulator: review/send while simulated link is off → show queued/waiting → turn link on → show device receipt → acknowledge in responder → send reply → show public result. On wide iPad, both native audiences can remain visible. Preserve existing secure paired samples. Record at least 40 seconds, trim operator dead time without reversing causal order, retain readable state holds, and put the reviewed actual recording at `public/live-take.mp4`. Label training throughout; this is not a secure radio benchmark.

`npm run render:live` refuses to render without a real input video. Once recording works, retune camera beats, inspect every meaningful state and mid-transition, then decode the complete export. No replacement demo is claimed until that happens. Computer-use connection startup currently blocks interaction capture; simulator CLI build/capture of static screens is still available.
