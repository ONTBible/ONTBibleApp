const { CompositionStage, useComposition, Easing, animate, interpolate, clamp } = window;

const MASK = 'url(./uploads/logomark.svg) center/contain no-repeat';
const MOTION = {
  enter: (start, end) => animate({ from: 0, to: 1, start, end, ease: Easing.easeOutCubic }),
  // f = horizontal position of the light front, 0 = left edge, 1 = right edge
  sweep: (start, end) => animate({ from: -0.22, to: 1.22, start, end, ease: Easing.easeInOutSine }),
  settle: (from, to, start, end) => animate({ from, to, start, end, ease: Easing.easeOutQuad }),
};

const BAND = 'linear-gradient(100deg, rgba(205,190,131,0) 32%, rgba(233,214,141,.95) 44%, #fffaf0 50%, rgba(233,214,141,.95) 56%, rgba(205,190,131,0) 68%)';

// background-size is 220%, so screen fraction f maps back to a background-position %
const posFor = (f) => ((1.1 - f) / 1.2) * 100;

function Piece() {
  const { T, CUES, authoredTotal } = useComposition();

  const start = CUES.Balayage;
  const end = CUES.Repos;
  const f = MOTION.sweep(start, end)(T);
  const bgPos = `${posFor(f)}% 0`;

  const on = clamp(interpolate(T, [start - 0.3, start + 0.25, end - 0.15, end + 0.5], [0, 1, 1, 0], Easing.easeInOutSine), 0, 1);
  const rise = T < start ? MOTION.enter(0, start)(T) : 1;
  const afterglow = T >= end ? MOTION.settle(0.8, 0, end, authoredTotal)(T) : 0;
  const inFrame = clamp(interpolate(f, [-0.12, 0.06, 0.94, 1.12], [0, 1, 1, 0], Easing.linear), 0, 1);
  const flare = on * inFrame;

  const layer = { position: 'absolute', inset: 0, WebkitMask: MASK, mask: MASK };
  const g = (px, a) => `drop-shadow(0 0 ${px}px rgba(255,240,200,${a}))`;
  const left = `${f * 100}%`;

  return (
    <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', background: 'radial-gradient(120% 100% at 50% 55%, #16150f 0%, #0b0b0b 70%)' }}>
      <div style={{ position: 'relative', width: 1180, aspectRatio: '502 / 249', isolation: 'isolate' }}>

        {/* the one mountain, dim */}
        <div style={{ ...layer, background: '#3a3527' }} />
        <div style={{ ...layer, background: '#cdbe83', mixBlendMode: 'screen', opacity: 0.2 + rise * 0.22 + afterglow * 0.3 }} />

        {/* anamorphic streak — sunlight thrown sideways out of the lit ridge */}
        <div style={{
          position: 'absolute', left, top: '46%', width: 1700, height: 26,
          transform: 'translate(-50%, -50%)',
          background: 'linear-gradient(90deg, rgba(233,214,141,0), rgba(255,246,216,.55) 45%, #fffdf5 50%, rgba(255,246,216,.55) 55%, rgba(233,214,141,0))',
          filter: 'blur(20px)', mixBlendMode: 'screen', opacity: flare * 0.22, pointerEvents: 'none',
        }} />

        {/* the lit part of that same mountain — the glow is its own drop-shadow,
            so light leaves the silhouette without ever duplicating it */}
        <div style={{
          position: 'absolute', inset: 0, mixBlendMode: 'screen', opacity: on, pointerEvents: 'none',
          filter: `${g(12, 1)} ${g(34, 0.95)} ${g(80, 0.8)} ${g(160, 0.6)} ${g(300, 0.42)}`,
        }}>
          <div style={{
            ...layer, backgroundImage: BAND, backgroundSize: '220% 100%',
            backgroundRepeat: 'no-repeat', backgroundPosition: bgPos,
          }} />
        </div>

      </div>
    </div>
  );
}

function LogomarkSweep() {
  return (
    <CompositionStage width={1920} height={1080} scenes={window.OM_SCENES} playback={window.OM_PLAYBACK} bg="#0b0b0b">
      <Piece />
    </CompositionStage>
  );
}

window.LogomarkSweep = LogomarkSweep;
