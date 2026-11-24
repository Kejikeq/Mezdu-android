// Sky and time of day (docs/tasks/render.md, «Освещение → IBL + солнце»).
// A preset describes the sky dome, the sun, the fog and the exposure of a time of day. The dome formula below
// (skyRad) has a twin in the shaders (skyDome in src/gfx/wgsl.js): the visible sky, the reflection cubemap and the
// diffuse environment light (SH9, computed here) all come from the same few parameters.
const dir = (x, y, z) => { const l = Math.hypot(x, y, z); return [x / l, y / l, z / l]; };

// zen / hor / away: sky radiance at the zenith, at the horizon towards the sun and at the horizon opposite to it
// (low sun: warm on one side, cool on the other); stars: 0..1; dark: 0 day .. 1 night (fireflies out, butterflies asleep);
// key: how bright the automatic exposure makes the frame (1 = day; dusk and night stay darker); gnd: light bounced by the ground (the lower half of the
// environment); glow: the aureole around the sun; sun: direct light (pi-less: diffuse = albedo * sun * n.l);
// fog: colour + density; exposure: nominal exposure; ev: scene EV limits (the automatic exposure may move
// half of that range away from the nominal value).
export const SKIES = {
  morning: { sunDir: dir(0.78, 0.30, 0.55), sun: [2.95, 2.40, 1.66], zen: [0.062, 0.23, 0.78], hor: [1.06, 0.82, 0.56], gnd: [0.095, 0.115, 0.082], glow: [1.48, 0.96, 0.46], fog: [0.38, 0.50, 0.67, 0.0045], exposure: 1.56, ev: [10, 13.5], away: [0.33, 0.56, 0.88], stars: 0, dark: 0, key: 1 },
  day: { sunDir: dir(0.45, 0.72, 0.52), sun: [2.85, 2.60, 2.24], zen: [0.052, 0.21, 0.80], hor: [0.68, 0.85, 1.06], gnd: [0.10, 0.12, 0.088], glow: [1.28, 1.04, 0.72], fog: [0.34, 0.50, 0.69, 0.0041], exposure: 1.50, ev: [10, 13.5], away: [0.42, 0.65, 0.94], stars: 0, dark: 0, key: 1 },
  overcast: { sunDir: dir(0.4, 0.7, 0.5), sun: [0.74, 0.76, 0.82], zen: [0.32, 0.40, 0.53], hor: [0.58, 0.64, 0.71], gnd: [0.10, 0.11, 0.10], glow: [0.25, 0.27, 0.29], fog: [0.36, 0.42, 0.49, 0.0115], exposure: 1.82, ev: [9, 12], away: [0.46, 0.53, 0.62], stars: 0, dark: 0.15, key: 0.92 },
  dusk: { sunDir: dir(-0.7, 0.12, 0.5), sun: [0.44, 0.33, 0.38], zen: [0.048, 0.080, 0.23], hor: [0.64, 0.35, 0.22], gnd: [0.036, 0.039, 0.048], glow: [0.58, 0.27, 0.15], fog: [0.14, 0.16, 0.25, 0.0135], exposure: 2.45, ev: [8, 11], away: [0.13, 0.18, 0.34], stars: 0.35, dark: 0.8, key: 0.54 },
  sunset: { sunDir: dir(-0.82, 0.13, 0.4), sun: [2.85, 1.32, 0.46], zen: [0.068, 0.15, 0.52], hor: [1.55, 0.65, 0.21], gnd: [0.10, 0.07, 0.05], glow: [1.68, 0.72, 0.19], fog: [0.49, 0.36, 0.34, 0.0082], exposure: 1.72, ev: [8, 11], away: [0.30, 0.34, 0.60], stars: 0.06, dark: 0.45, key: 0.88 },
  night: { sunDir: dir(-0.35, 0.62, -0.5), sun: [0.14, 0.18, 0.29], zen: [0.008, 0.015, 0.042], hor: [0.024, 0.037, 0.074], gnd: [0.005, 0.007, 0.010], glow: [0.07, 0.09, 0.14], fog: [0.018, 0.027, 0.048, 0.0135], exposure: 3.55, ev: [3, 6], away: [0.018, 0.029, 0.060], stars: 1, dark: 1, key: 0.62 },
  nightmare: { sunDir: dir(0.78, 0.30, 0.55), sun: [0.66, 0.115, 0.082], zen: [0.042, 0.026, 0.052], hor: [0.195, 0.033, 0.027], gnd: [0.032, 0.017, 0.019], glow: [0.68, 0.10, 0.048], fog: [0.082, 0.028, 0.026, 0.040], exposure: 1.38, ev: [8, 9], away: [0.085, 0.018, 0.022], stars: 0, dark: 1, key: 0.82 }, // a narrow EV range: the nightmare stays dark
  void: { sunDir: dir(0.78, 0.30, 0.55), sun: [0, 0, 0], zen: [0.004, 0.004, 0.005], hor: [0.006, 0.005, 0.006], gnd: [0.004, 0.003, 0.004], glow: [0, 0, 0], fog: [0.006, 0.004, 0.006, 0.05], exposure: 2.10, ev: [3, 6], away: [0.006, 0.005, 0.006], stars: 0, dark: 1, key: 0.6 },
};
// Monday morning ... Sunday 03:17, «Между»
export const CHAPTER_SKY = { 1: 'morning', 2: 'day', 3: 'day', 4: 'overcast', 5: 'dusk', 6: 'morning', 7: 'day', 8: 'sunset', 9: 'night', 10: 'dusk' };

// radiance of the dome in direction (x, y, z), without the sun disc; the shader twin is skyDome()
export function skyRad(P, x, y, z, out) {
  const up = Math.max(y, 0), k = 1 - (1 - up) * (1 - up);
  let g = Math.min(1, Math.max(0, (y + 0.25) / 0.25)); g = 1 - g * g * (3 - 2 * g);
  const s = Math.max(x * P.sunDir[0] + y * P.sunDir[1] + z * P.sunDir[2], 0), s2 = s * s, s4 = s2 * s2, s16 = s4 * s4 * s4 * s4;
  const gl = s4 * 0.38 + s16 * s16 * 0.95;
  const fl = Math.hypot(P.sunDir[0], P.sunDir[2]) || 1;
  let side = 0.5 + 0.5 * (x * P.sunDir[0] + z * P.sunDir[2]) / fl; side *= side;
  for (let i = 0; i < 3; i++) {
    const hor = P.away[i] + (P.hor[i] - P.away[i]) * side;
    const c = hor + (P.zen[i] - hor) * k + P.glow[i] * gl;
    out[i] = c + (P.gnd[i] - c) * g;
  }
  return out;
}

// Diffuse environment light: SH9 of the dome convolved with the cosine lobe, pi-less, with the basis constants
// folded in. The shader evaluates  c0 + c1*y + c2*z + c3*x + c4*xy + c5*yz + c6*(3zz-1) + c7*xz + c8*(xx-yy).
const SH_K = [0.282095, 0.488603, 0.488603, 0.488603, 1.092548, 1.092548, 0.315392, 1.092548, 0.546274];
const SH_A = [1, 2 / 3, 2 / 3, 2 / 3, 1 / 4, 1 / 4, 1 / 4, 1 / 4, 1 / 4];
export function skySH(P, out = new Float32Array(36)) {
  out.fill(0);
  const NT = 24, NP = 48, c = [0, 0, 0], b = new Float64Array(9);
  for (let i = 0; i < NT; i++) {
    const th = (i + 0.5) / NT * Math.PI, st = Math.sin(th), y = Math.cos(th);
    const dw = (Math.PI / NT) * (2 * Math.PI / NP) * st;
    for (let j = 0; j < NP; j++) {
      const ph = (j + 0.5) / NP * 2 * Math.PI, x = st * Math.cos(ph), z = st * Math.sin(ph);
      skyRad(P, x, y, z, c);
      b[0] = 1; b[1] = y; b[2] = z; b[3] = x; b[4] = x * y; b[5] = y * z; b[6] = 3 * z * z - 1; b[7] = x * z; b[8] = x * x - y * y;
      for (let k = 0; k < 9; k++) { const w = b[k] * SH_K[k] * dw; out[k * 4] += c[0] * w; out[k * 4 + 1] += c[1] * w; out[k * 4 + 2] += c[2] * w; }
    }
  }
  for (let k = 0; k < 9; k++) { const f = SH_K[k] * SH_A[k]; out[k * 4] *= f; out[k * 4 + 1] *= f; out[k * 4 + 2] *= f; }
  return out;
}
export function shEval(sh, x, y, z, out) {
  const b = [1, y, z, x, x * y, y * z, 3 * z * z - 1, x * z, x * x - y * y];
  for (let i = 0; i < 3; i++) { let v = 0; for (let k = 0; k < 9; k++) v += sh[k * 4 + i] * b[k]; out[i] = Math.max(v, 0); }
  return out;
}

// Per preset, computed once: SH9 and the light of the sky on an upward / a downward surface (for the shaders that
// still use the two-colour hemisphere: grass, particles, fog).
const cache = new Map();
function prep(name) {
  let e = cache.get(name);
  if (!e) {
    const P = SKIES[name], sh = skySH(P);
    e = { name, P, sh, up: shEval(sh, 0, 1, 0, [0, 0, 0, 0]), down: shEval(sh, 0, -1, 0, [0, 0, 0, 0]), sun: [P.sun[0], P.sun[1], P.sun[2], 0],
      sky: new Float32Array([P.zen[0], P.zen[1], P.zen[2], 0, P.hor[0], P.hor[1], P.hor[2], 0, P.gnd[0], P.gnd[1], P.gnd[2], 0, P.glow[0], P.glow[1], P.glow[2], 0]),
      skyX: new Float32Array([P.away[0], P.away[1], P.away[2], P.stars]) };
    cache.set(name, e);
  }
  return e;
}

// The lighting state of a frame (the object is reused: no allocations per frame).
// inside: the hero is in a room (less sky light, thinner fog); headache: 0..1 (story effect on the fog).
const L = { sunDir: null, sunD: null, sunN: null, skyD: [0, 0, 0, 0], skyN: [0, 0, 0, 0], gndD: [0, 0, 0, 0], gndN: [0, 0, 0, 0], fogD: [0, 0, 0, 0], fogN: [0, 0, 0, 0],
  fogP: [2.5, 0.18, 0.5, 120], exposure: 1, exposureN: 1, evRange: 2, evRangeN: 0.5, key: 1, keyN: 1, amb: 1, dark: 0, envD: null, envN: null };
export function lightFor(chapter, inside, headache, isVoid) {
  const d = prep(isVoid ? 'void' : (CHAPTER_SKY[chapter] || 'day')), n = prep(isVoid ? 'void' : 'nightmare');
  const amb = inside ? 0.24 : 1, fogScale = inside ? 0.28 : 1, h = headache || 0;
  L.sunDir = d.P.sunDir; L.sunD = d.sun; L.sunN = n.sun; L.envD = d; L.envN = n; L.amb = amb;
  for (let i = 0; i < 3; i++) { L.skyD[i] = d.up[i] * amb; L.skyN[i] = n.up[i] * amb; L.gndD[i] = d.down[i] * amb; L.gndN[i] = n.down[i] * amb; }
  const fd = d.P.fog, fn = n.P.fog;
  L.fogD[0] = fd[0] * (1 - h * 0.3); L.fogD[1] = fd[1] * (1 - h * 0.35); L.fogD[2] = fd[2] * (1 - h * 0.25); L.fogD[3] = fd[3] * fogScale * (1 + h * 3);
  L.fogN[0] = fn[0]; L.fogN[1] = fn[1]; L.fogN[2] = fn[2]; L.fogN[3] = fn[3] * (isVoid ? 1 : fogScale * (1 + h * 2));
  L.dark = d.P.dark; L.key = d.P.key; L.keyN = n.P.key;
  L.exposure = d.P.exposure; L.exposureN = n.P.exposure; L.evRangeN = (n.P.ev[1] - n.P.ev[0]) / 2;
  L.evRange = inside ? 0.58 : (d.P.ev[1] - d.P.ev[0]) / 2;
  return L;
}
