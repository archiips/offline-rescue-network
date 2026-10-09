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


## Live native motion edit

`src/live.tsx` renders the actual 44-second native training take to `docs/media/rescue-live.mp4` at 1920×1080 / 30fps. Real footage stays visible throughout. Smooth eased camera holds follow reported-floor selection, review, queued state and responder actions; an animated caption rail explains the sequence. No app pixels, tap events or delivery facts are reconstructed. The cut is silent and captioned.

The original raw capture is `experiments/rescue-demo/evidence/2026-10-09-live-training-raw.mp4`; normalized clockwise/30fps source is `public/live-take.mp4`. First 36 seconds preserve the original causal sequence; the last eight seconds use a later actual conversation-view pickup (`public/live-reply.mp4`, seconds 2–10). Pickup raw file: `experiments/rescue-demo/evidence/2026-10-09-live-reply-raw.mp4`. No new message or pairing occurred. The clock jump is an editorial cut. The source reports 44.30 seconds after normalization. Capture/limits: [LIVE_CAPTURE.md](LIVE_CAPTURE.md).

```sh
npm run typecheck
npm run render:live -- --browser-executable='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

The guard checks input existence/duration (44 seconds minimum), not authenticity or story quality. Final render and full FFmpeg decode passed; chapter and transition frames inspected. Full final-export playback could not be verified through Computer Use: QuickTime timed out and Safari returned ScreenCaptureKit -3811. Human playback review remains open. The earlier illustrated film remains historical and separate.
