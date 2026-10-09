# Actual native take: capture and editorial checklist

Status: actual native take recorded and motion edit rendered on 2026-10-09. Full final-export playback review remains pending. The historical 64-second diagram film does not satisfy this task.

## Capture

Use a separate fresh simulator so the existing paired secure iPhone/iPad histories remain untouched. Install the signed build; leave it in Training. Rotate the fresh iPad to landscape before recording; both audiences remain present with legible pane widths. Keep the synthetic / simulated-link disclosure visible.

1. Start with simulated link off, public screen empty. Choose reported floor and open Review sample SOS. Let the sheet transition settle; hold the reviewed data.
2. Confirm Send sample SOS. Hold Waiting and the queued count long enough to read. No device receipt yet.
3. In Setup, turn the simulated link on, then close Setup. Observe the actual device-received state and responder request; do not edit this state into the video before the action.
4. Tap Acknowledge SOS in responder. Hold separate human acknowledgment / handling facts.
5. Send sample reply. Show the public conversation and actual reply arrival. Scroll deliberately if needed.
6. Optional correction only if it improves the short story; a launch demo need not cover every diagnostic feature.

Run `xcrun simctl io DEVICE_UUID recordVideo --codec=h264 /ABSOLUTE/PATH/take.mp4` before the interactions; stop with SIGINT to finalize. Perform UI actions through the connected computer-use tool or an attended human session. `simctl launch` returning a PID is not readiness evidence: inspect the actual loaded UI before recording. Do not reset/re-pair existing secure peers for this take.

## Edit

Target 30–40 seconds; favor a single coherent workflow. Native UI footage should dominate (at least 70% of runtime); the provisional 40-second LiveTake composition uses actual video throughout. Remove operator pauses, not causality. Keep the original take as inspectable evidence before editorial cuts. Retune `src/live.tsx` duration and camera holds against actual observed actions; its initial zoom times are provisional. Avoid constant pumping or floating screenshot choreography.

Use precise source footage trims; never manufacture app states, typing, tap targets or receipts in a web reconstruction. Small chapter captions, genuine interaction highlights and a restrained camera push may focus attention. Native animations belong to the app. Typography should match the dark graphite/amber console; no long explanatory slides. Add narration only if it improves understanding and is checked for sync/readability.

## Acceptance

- A new viewer can identify who sends, who responds, what was saved, what arrived and what a human acknowledged.
- Actual review sheet, send, waiting, receipt, acknowledgment and reply transitions are visibly present.
- Label Training / simulated link throughout. This recording establishes no physical radio or fresh signed-network evidence.
- Inspect settled and mid-transition frames; watch the real export for motion/pacing, not just a contact sheet.
- Fully decode export with ffmpeg; inspect duration/resolution/audio with ffprobe. Replace README hero and current captures only after verified media exists.

## Recorded checkpoint — 2026-10-09

Computer Use opened Simulator successfully. Created isolated `Rescue Live Training` iPad Pro 11-inch (M5), iOS 26.4, UUID `B3A7FEEA-2F53-4974-8A69-CD124ADA2EBE`; installed the existing signed build from `/private/tmp/rescue-live-derived`. Existing paired secure peers were not reset or re-paired.

Actual UI actions: simulated link off → reported Floor 3 → review sheet → send → saved/queued with device and human facts Not yet → Setup link on → device Received/human Not yet → Acknowledge SOS → human Recorded → Send sample reply → received public reply. Both audiences and synthetic/simulated disclosure remain visible. Final screenshot independently showed both conversations, reply and clear queue. The training simulator remains open with this history.

Raw capture: `../../experiments/rescue-demo/evidence/2026-10-09-live-training-raw.mp4` (H.264, 1668×2420, sideways encoded; container duration 51.973s). Corrected input: `public/live-take.mp4` (clockwise transpose, 30fps, 1920×1324, 44.300s). Simulator emitted sparse variable-rate frames; normalization follows encoded timestamps, with no fabricated states. `ffmpeg -v error -i tools/demo-video/public/live-take.mp4 -fps_mode passthrough -f null -` passed with no diagnostics. Four-second sampled frames inspected: floor menu, review, queued, link toggle, receipt, acknowledgment and reply.

Computer Use scroll returned `noWindowsAvailable`, but rebinding showed the scrolled conversations and actual reply. QuickTime playback attempt failed with ScreenCaptureKit error -3811 after opening its file dialog; full motion playback is **not verified**. Retain original footage, inspect playback, and retune the provisional 40-second composition before rendering/publication. No README hero replacement or final live-demo completion claim yet.

## Motion edit verification — 2026-10-09

`docs/media/rescue-live.mp4`: H.264, 1920×1080, 30fps, 44.000s, silent/captioned, 7,715,059 bytes. Actual native footage throughout; first 36 seconds preserve the original causal sequence, followed by an eight-second later conversation-view pickup from the same unchanged session. No causal reorder or fabricated pointer/state. Manrope + graphite/amber framing, eased camera moves and seven caption chapters. Initial review corrected an early queued caption and clipped receipt facts. Cut extended from 40 to 44 seconds for a readable reply ending. Frame inspection found the initial normalized take did not include the public reply scroll; a later actual pickup fixes this. Existing native code/secure samples unchanged.

Fresh checks: `npm run typecheck --prefix tools/demo-video` passed; input guard passed; installed-Chrome `npm run render:live` completed 1320/1320 frames; `ffmpeg -v error -i docs/media/rescue-live.mp4 -f null -` exited 0 with no diagnostics; ffprobe confirmed format. Poster at 23s and final four-second sampled frames inspected. QuickTime source playback advanced through receipt; final-export open/rebind repeatedly timed out. Safari alternate playback returned ScreenCaptureKit -3811. **Full exported motion playback remains unverified**; do not mark that acceptance criterion complete. README links the rendered cut for review.

Official API references checked: https://www.remotion.dev/docs/offthreadvideo and https://www.remotion.dev/docs/interpolate (2026-10-09). Existing pinned dependencies retained.

Reply pickup correction: the first normalized take retained the reply event/count but its public bubble was below the viewport. Recorded the same training session again after scrolling, with no new message/reset/pairing. `2026-10-09-live-reply-raw.mp4` retains the original pickup; `public/live-reply.mp4` is orientation/30fps normalized. Final edit uses pickup seconds 2–10 at output seconds 36–44, so the public “Reply · Received locally” bubble is readable. The device clock changes visibly at the cut; this is a later view of the same saved conversation, not real-time delivery evidence.

Final pickup render completed 1320/1320 frames; full FFmpeg decode exited 0 without diagnostics. Frame 38s inspected: both sent and received reply bodies are legible, public receipt/acknowledgment recorded, queue clear. Full exported playback remains unverified due the documented player errors.
