import React from 'react';
import {AbsoluteFill, Composition, Easing, OffthreadVideo, interpolate, staticFile, useCurrentFrame} from 'remotion';

// Capture a continuous real native training workflow before rendering this composition.
// The source must show review/send, queued state, receipt, human acknowledgment and reply.
// Reframing and captions are editorial; the source's application pixels remain untouched.
const LiveTake: React.FC = () => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, 75, 120, 300, 345, 600, 645, 840, 885, 1080, 1125, 1199],
    [1, 1, 1.08, 1.08, 1, 1, 1.08, 1.08, 1, 1, 1, 1],
    {easing: Easing.inOut(Easing.cubic), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const opening = frame < 90;
  const ending = frame >= 1110;
  return <AbsoluteFill style={{background: '#090d12', color: '#f5f6f8', fontFamily: 'Arial, sans-serif', padding: '42px 72px'}}>
    <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 20, letterSpacing: 1}}>
      <span>OFFLINE RESCUE</span><span style={{color: '#e8b56a'}}>Native app · training / simulated link</span>
    </div>
    <div style={{position: 'absolute', top: 105, bottom: 105, left: 72, right: 72, overflow: 'hidden', borderRadius: 24, border: '1px solid #29313b', background: '#11161c'}}>
      <OffthreadVideo src={staticFile('live-take.mp4')} muted style={{width: '100%', height: '100%', objectFit: 'contain', transform: `scale(${zoom})`, transformOrigin: 'center'}} />
    </div>
    {opening && <div style={{position: 'absolute', left: 108, top: 135, padding: '18px 26px', background: '#090d12ee', borderRadius: 12, fontSize: 32, fontWeight: 700}}>One request. A response back.</div>}
    {ending && <div style={{position: 'absolute', left: 108, right: 108, bottom: 145, padding: '20px 26px', background: '#090d12ee', borderRadius: 12, fontSize: 28}}>Explore the native workflow · github.com/archiips/offline-rescue-network</div>}
    <div style={{position: 'absolute', bottom: 42, left: 72, right: 72, display: 'flex', justifyContent: 'space-between', fontSize: 20, color: '#aab4c0'}}>
      <span>Synthetic exercise · no emergency service contacted</span><span>Actual app interaction recording</span>
    </div>
  </AbsoluteFill>;
};

export const LiveComposition = () => <Composition id="LiveTake" component={LiveTake} durationInFrames={1200} fps={30} width={1920} height={1080} />;
