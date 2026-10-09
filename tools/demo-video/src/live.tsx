import React from 'react';
import {AbsoluteFill, Composition, Easing, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';

const fps = 30;
const duration = 44 * fps;
// First 36 seconds retain causal order. Final eight seconds are a later actual reply-view pickup.
// Camera/captions are editorial; no app state is reconstructed.
const chapters = [
  {at: 0, title: 'Help starts with a request.', detail: 'Choose a reported floor. Review the SOS before sending.', fact: 'Public → review', color: '#f6b653'},
  {at: 13, title: 'Saved. Still waiting.', detail: 'The connection is off. The SOS stays queued on the public device.', fact: 'No device receipt yet', color: '#f6b653'},
  {at: 17, title: 'Bring the link back.', detail: 'This training switch restores the simulated connection between both views.', fact: 'Training / simulated link', color: '#f6b653'},
  {at: 22, title: 'A device received it.', detail: 'The responder device saved the request. A person has not acknowledged it yet.', fact: 'Device receipt ≠ human acknowledgment', color: '#b7cee0'},
  {at: 26, title: 'Now a person responds.', detail: 'The responder explicitly acknowledges the SOS. Handling remains open.', fact: 'Human acknowledgment recorded', color: '#f6b653'},
  {at: 30, title: 'A reply comes back.', detail: 'The public conversation receives the responder’s message.', fact: 'Two audiences. One conversation.', color: '#b7cee0'},
  {at: 40, title: 'Follow every step.', detail: 'Saved locally. Received by a device. Acknowledged by a person.', fact: 'Explore the prototype on GitHub', color: '#f6b653'},
];

const LiveTake: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / fps;
  const chapterIndex = chapters.reduce((found, chapter, index) => t >= chapter.at ? index : found, 0);
  const chapter = chapters[chapterIndex];
  const local = f - chapter.at * fps;
  const reveal = interpolate(local, [0, 18], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic)});
  // Smooth camera holds follow the actual floor menu, review, queued facts, setup and response.
  const points = [0, 65, 105, 190, 230, 310, 350, 440, 480, 650, 690, 755, 795, 865, 905, 955, 995, 1060, 1100, 1199];
  const opts = {easing: Easing.inOut(Easing.cubic), extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
  const scale = interpolate(f, points, [1,1,1.16,1.16,1,1,1.13,1.13,1,1,1,1,1.10,1.10,1,1,1.1,1.1,1,1], opts);
  const x = interpolate(f, points, [0,0,110,110,0,0,89,89,0,0,0,0,-69,-69,0,0,69,69,0,0], opts);
  return <AbsoluteFill style={{background: '#090d12', color: '#f5f6f8', fontFamily: 'Manrope, sans-serif'}}>
    <style>{`@font-face {font-family: Manrope; src: url('${staticFile('Manrope.ttf')}'); font-weight: 200 800;}`}</style>
    <div style={{position: 'absolute', left: 44, right: 44, top: 28, display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
      <span style={{fontSize: 27, fontWeight: 750}}>Offline Rescue</span>
      <span style={{fontSize: 19, color: '#b0b9c4'}}>Actual native footage <span style={{color: '#f6b653', marginLeft: 26}}>Training / simulated link</span></span>
    </div>
    <div style={{position: 'absolute', top: 86, left: 34, width: 1370, height: 945, overflow: 'hidden', borderRadius: 18, border: '1px solid #303740', boxShadow: '0 18px 70px #0008'}}>
      <Sequence durationInFrames={1080}><OffthreadVideo src={staticFile('live-take.mp4')} muted style={{width: '100%', height: '100%', objectFit: 'contain', transform: `translateX(${x}px) scale(${scale})`, transformOrigin: 'center'}} /></Sequence>
      <Sequence from={1080} durationInFrames={240}><OffthreadVideo src={staticFile('live-reply.mp4')} trimBefore={60} muted style={{width: '100%', height: '100%', objectFit: 'contain'}} /></Sequence>
    </div>
    <div style={{position: 'absolute', left: 1450, right: 45, top: 104, bottom: 90}}>
      <div style={{display: 'flex', gap: 8, marginBottom: 80}}>{chapters.map((c, i) => <div key={c.at} style={{height: 3, flex: 1, background: i <= chapterIndex ? '#f6b653' : '#343b44'}} />)}</div>
      <div key={chapterIndex} style={{opacity: reveal, transform: `translateY(${(1-reveal)*14}px)`}}>
        <div style={{fontSize: 53, fontWeight: 750, lineHeight: 1.12, letterSpacing: -2, marginBottom: 30}}>{chapter.title}</div>
        <div style={{fontSize: 25, lineHeight: 1.55, color: '#b0b9c4'}}>{chapter.detail}</div>
        <div style={{height: 1, background: '#343b44', margin: '40px 0 24px'}} />
        <div style={{fontSize: 20, lineHeight: 1.5, color: chapter.color}}>{chapter.fact}</div>
      </div>
      <div style={{position: 'absolute', bottom: 0, fontSize: 18, color: '#84909e', lineHeight: 1.6}}>Public request + responder workspace<br/>C++ engine · native SwiftUI<br/><span style={{color: '#d3dae2'}}>github.com/archiips/<br/>offline-rescue-network</span></div>
    </div>
    <div style={{position: 'absolute', bottom: 18, left: 44, fontSize: 16, color: '#8f9ba9'}}>Synthetic exercise · does not contact emergency services · camera motion and timing are editorial</div>
  </AbsoluteFill>;
};

export const LiveComposition = () => <Composition id="LiveTake" component={LiveTake} durationInFrames={duration} fps={fps} width={1920} height={1080} />;
