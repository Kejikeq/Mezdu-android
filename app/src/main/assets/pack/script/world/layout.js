// World layout shared by the generator (workers) and the game (main thread).
// Coordinates are voxels (1 voxel = 0.5 m). x: west -> east, z: north -> south, y: up.
// The map is 256 x 256 m. Every story area keeps its own local design and is placed on the
// big map by an offset (AREA), so scenes stay hand-tuned while the paths between them are long.
import { fbm2, hash2i, smoothstep, clamp } from '../engine/noise.js';

export const VS = 0.125;
export const WX = 1536, WY = 128, WZ = 2560, CS = 32;
// all story areas sit far from the map border (the border is never reachable or visible)
export const SHIFT_Z = 256;
export const CX = WX / CS, CY = WY / CS, CZ = WZ / CS, NCH = CX * CY * CZ;
export const SEED = 20261105;
export const vidx = (x, y, z) => x + WX * (z + WZ * y);

// area offsets in voxels (local design coordinates + offset = map coordinates)
// Scaled by 4x from the 0.5m grid to the 0.125m grid
export const AREA = {
  start: [560, 1256],
  crossing: [560, 1176],
  meadow: [440, 1016],
  house: [600, 856],
  campfire: [480, 736],
  thicket: [360, 736],
  upstream: [160, 696],
  cliff: [120, 536],
  north: [600, 536],
};
const o = (a, x, z) => [x + AREA[a][0], z + AREA[a][1]];
const ox = (a, x) => x + AREA[a][0], oz = (a, z) => z + AREA[a][1];

export const P = {
  ch1House: { x0: 336, x1: 484, z0: 2194, z1: 2290, door: 408, y: 56, yardX0: 296, yardX1: 490, yardZ0: 2180, yardZ1: 2312, garageX0: 298, garageX1: 336, garageZ0: 2198, garageZ1: 2262 },
  ch1MillerHouse: { x0: 188, x1: 284, z0: 2196, z1: 2280, y: 56, yardX0: 184, yardX1: 290, yardZ0: 2180, yardZ1: 2284 },
  ch1WagnerHouse: { x0: 516, x1: 602, z0: 2196, z1: 2280, y: 56, yardX0: 514, yardX1: 606, yardZ0: 2180, yardZ1: 2284 },
  ch1Apothecary: { x0: 186, x1: 270, z0: 2012, z1: 2098, y: 56 },
  ch1UniHall: { x0: 448, x1: 512, z0: 2052, z1: 2094, y: 56 },
  ch1Bookshop: { x0: 526, x1: 610, z0: 2012, z1: 2098, y: 56 },
  ch1Arch: { x0: 376, x1: 424, z0: 2090, z1: 2102, y: 56 },
  ch2Lab: { x0: 368, x1: 432, z0: 1896, z1: 1944, door: 400, y: 56 },
  ch3Garage: { x0: 648, x1: 712, z0: 2184, z1: 2232, door: 680, y: 56 },
  ch3Platform: { x0: 656, x1: 704, z0: 2120, z1: 2144, y: 56 },
  ch4Motel: { x0: 648, x1: 712, z0: 1936, z1: 1984, door: 680, y: 56 },
  ch4Gas: { x0: 660, x1: 700, z0: 1884, z1: 1908, y: 56 },
  start: o('start', 512, 920),
  startCave: { x0: 1172, x1: 1216, z0: 2136, z1: 2160, y0: 56, y1: 72, blockX0: 1166, blockX1: 1172 },
  crossing: o('crossing', 512, 728),
  stones: { x: ox('crossing', 508), zs: [744, 732, 720, 708].map((z) => oz('crossing', z)) }, // red, blue, yellow, green (south -> north)
  bridge1: { x0: ox('crossing', 532), x1: ox('crossing', 556), z0: oz('crossing', 700), z1: oz('crossing', 756), y: 55 },
  plate: o('crossing', 564, 764),
  riddleTree: o('crossing', 444, 796),
  meadow: o('meadow', 400, 592),
  house: { x0: ox('house', 588), x1: ox('house', 660), z0: oz('house', 448), z1: oz('house', 504), door: ox('house', 620), y: 60 },
  bench: o('house', 548, 504),
  benchTree: o('house', 532, 484),
  hedge1: { z: oz('house', 416), gx0: ox('house', 544), gx1: ox('house', 584) },
  hedge2: { x0: ox('north', 512), x1: ox('north', 720), z0: oz('north', 280), z1: oz('north', 344), gz0: oz('north', 300), gz1: oz('north', 328) },
  campfire: o('campfire', 424, 352),
  thicket: o('thicket', 304, 336),
  upstream: o('upstream', 212, 372),
  cliff: o('cliff', 200, 296),
  bridge2: { x0: ox('north', 588), x1: ox('north', 612), z0: oz('north', 200), z1: oz('north', 284), y: 60, gap0: oz('north', 232), gap1: oz('north', 252) },
  tunnel: { x0: ox('north', 592), x1: ox('north', 612), y0: 64, y1: 84, z0: oz('north', 120), z1: oz('north', 188), wallZ: oz('north', 136), grateZ: oz('north', 188), deadZ: oz('north', 192) },
  alcove: { x0: ox('north', 572), x1: ox('north', 588), z0: oz('north', 152), z1: oz('north', 168) },
  cave: { x: ox('north', 604), z: ox('north', 64) - 540, r: 56, y0: 64 },
  pool: { x: ox('north', 604), z: oz('north', 56), r: 20 },
  exitE: { x0: ox('north', 664), x1: ox('north', 744), z0: oz('north', 56), z1: oz('north', 68) },
  exitW: { x0: ox('north', 468), x1: ox('north', 544), z0: oz('north', 56), z1: oz('north', 68) },
  waterfallX: [ox('cliff', 144), ox('cliff', 168)],
  ledgeX: [ox('north', 552), ox('north', 648)],
  gorge: { m: oz('north', 184), n: oz('north', 208), s: oz('north', 280) },
  // Dedicated spacious Testing Hub ("Полигон Пробоя"): 40 x 37.5 m open concrete & stone courtyard
  hubArena: { x0: 1080, x1: 1400, z0: 1540, z1: 1840, cx: 1240, cz: 1690, y: 56 },
};
P.cave.z = oz('north', 64);

export const CLEARINGS = [
  { x: 400, z: 2190, r: 240, h: 56 },
  { x: 400, z: 1920, r: 84, h: 56 },
  { x: 680, z: 2176, r: 88, h: 56 },
  { x: 680, z: 1936, r: 88, h: 56 },
  { x: P.start[0], z: P.start[1], r: 56, h: 56 },
  { ...xz(o('crossing', 512, 744)), r: 88, h: 56 },
  { x: P.meadow[0], z: P.meadow[1], r: 52, h: 60 },
  { ...xz(o('house', 608, 492)), r: 80, h: 60 },
  { x: P.campfire[0], z: P.campfire[1], r: 40, h: 60 },
  { x: P.thicket[0], z: P.thicket[1], r: 36, h: 60 },
  { ...xz(o('upstream', 220, 368)), r: 36, h: 60 },
  { ...xz(o('cliff', 200, 304)), r: 32, h: 64 },
  { ...xz(o('north', 608, 312)), r: 44, h: 64 },
  { x: 1240, z: 1690, r: 192, h: 56 },
];
function xz(p) { return { x: p[0], z: p[1] }; }

// the stream springs below the cliff and runs south, then east past crossing and loops around startCave to the south bank behind P.start
export const STREAM = [o('cliff', 164, 312), [304, 928], o('upstream', 164, 312), o('upstream', 176, 392), [400, 1256], [520, 1456], [700, 1656], [840, 1796],
  o('crossing', 376, 672), o('crossing', 512, 728), o('crossing', 672, 736), [1336, 1968], [1368, 2080], [1320, 2192], [1180, 2224], [1072, 2212], [900, 2224]];
export const RAVINE_Z = 1456; // south of this the nightmare stream is a dry ravine, north of it a narrow black channel
export const streamHW = (z) => (z > RAVINE_Z ? 24 : 20);

// paths; `ch` = first chapter in which the path is part of the story route
export const PATHS = [
  { ch: 1, w: 12.0, pts: [[400, 2236], [400, 2104]] },
  { ch: 1, w: 10.0, pts: [[400, 1960], [400, 1860]] },
  { ch: 1, w: 10.0, pts: [[680, 2236], [680, 2104]] },
  { ch: 1, w: 12.0, pts: [[680, 1996], [680, 1868]] },
  { ch: 1, w: 9.6, pts: [P.start, [1160, 2128], [1200, 2048], [1136, 1984], [1104, 1936]] },
  { ch: 1, w: 8.8, pts: [[1104, 1872], [1024, 1808], [944, 1720], [856, 1636], P.meadow, [904, 1544], [1008, 1480], [1112, 1432], [1200, 1400], [1220, 1368]] },
  { ch: 1, w: 6.4, pts: [o('house', 560, 536), o('house', 552, 512)] },
  { ch: 1, w: 8.0, pts: [o('house', 584, 536), o('house', 568, 480), o('house', 564, 432), o('house', 564, 408)] },
  { ch: 1, w: 8.0, pts: [o('house', 564, 408), [1136, 1208], [1072, 1160], [992, 1120], [924, 1096]] },
  { ch: 1, w: 8.0, pts: [[888, 1080], [784, 1064], [688, 1072]] },
  { ch: 1, w: 7.2, pts: [[640, 1064], [560, 1008], [480, 952], [416, 904]] },
  { ch: 1, w: 7.2, pts: [[416, 904], [368, 864], o('cliff', 200, 304)] },
  { ch: 1, w: 8.8, pts: [[920, 1072], [1000, 1016], [1048, 936], [1080, 864], [1128, 848], [1184, 840], o('north', 600, 288)] },
];

// route inside the mountain (bridge -> tunnel -> cave -> both exits); counts as "on the story path"
export const ROUTE_EXTRA = [
  // no trail goes to the place marked on the map: you follow the stream
  { ch: 1, w: 28, pts: [[288, 848], [304, 928], [324, 1008], [336, 1088], [360, 1104]] },
  { ch: 1, w: 24, pts: [o('north', 600, 288), o('north', 600, 184), o('north', 604, 64), o('north', 748, 60)] },
  { ch: 1, w: 24, pts: [o('north', 604, 64), o('north', 464, 60)] },
];

export function distSeg(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az;
  const l2 = dx * dx + dz * dz;
  let t = l2 > 0 ? ((px - ax) * dx + (pz - az) * dz) / l2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  const x = ax + dx * t - px, z = az + dz * t - pz;
  return Math.sqrt(x * x + z * z);
}
// Pre-combined route polylines so Game.routeDistance never spreads [...PATHS, ...ROUTE_EXTRA] per frame
export const ALL_ROUTE_POLYS = [...PATHS, ...ROUTE_EXTRA];

// nearest point on a polyline: [dist, x, z, segDirX, segDirZ] — zero heap allocation
const _nearestScratch = new Float32Array([1e9, 0, 0, 0, 1]);
export function nearestOnPoly(pts, px, pz, out = _nearestScratch) {
  let best = 1e9, bx = 0, bz = 0, bdx = 0, bdz = 1;
  for (let i = 0; i < pts.length - 1; i++) {
    const ax = pts[i][0], az = pts[i][1], bx1 = pts[i + 1][0], bz1 = pts[i + 1][1];
    const dx = bx1 - ax, dz = bz1 - az, l2 = dx * dx + dz * dz;
    let t = l2 > 0 ? ((px - ax) * dx + (pz - az) * dz) / l2 : 0;
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    const x = ax + dx * t, z = az + dz * t, d = Math.hypot(x - px, z - pz);
    if (d < best) {
      best = d;
      const invL = 1.0 / (Math.sqrt(l2) || 1.0);
      bx = x; bz = z; bdx = dx * invL; bdz = dz * invL;
    }
  }
  out[0] = best; out[1] = bx; out[2] = bz; out[3] = bdx; out[4] = bdz;
  return out;
}

export function distPoly(pts, x, z) {
  let d = 1e9;
  for (let i = 0; i < pts.length - 1; i++) {
    const v = distSeg(x, z, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
    if (v < d) d = v;
  }
  return d;
}

export const streamDist = (x, z) => distPoly(STREAM, x, z);

export function pathDist(x, z) {
  let d = 1e9;
  for (const p of PATHS) {
    const v = distPoly(p.pts, x, z) - p.w;
    if (v < d) d = v;
  }
  return d;
}

// Spatial grid (16x16 voxel cells) for O(1) pathDist & streamDist early-out in heightmaps/worldgen
const DG_STEP = 16;
const DG_W = Math.ceil(WX / DG_STEP), DG_H = Math.ceil(WZ / DG_STEP);
let _pathGrid = null, _streamGrid = null;
export function ensureSpatialDistGrid() {
  if (_pathGrid) return;
  _pathGrid = new Float32Array(DG_W * DG_H);
  _streamGrid = new Float32Array(DG_W * DG_H);
  for (let gz = 0; gz < DG_H; gz++) {
    const cz = gz * DG_STEP + (DG_STEP >> 1);
    const row = gz * DG_W;
    for (let gx = 0; gx < DG_W; gx++) {
      const cx = gx * DG_STEP + (DG_STEP >> 1);
      _pathGrid[row + gx] = pathDist(cx, cz);
      _streamGrid[row + gx] = streamDist(cx, cz);
    }
  }
}

export function fastPathDist(x, z) {
  if (!_pathGrid) ensureSpatialDistGrid();
  const gx = clamp(x >> 4, 0, DG_W - 1), gz = clamp(z >> 4, 0, DG_H - 1);
  const cd = _pathGrid[gx + gz * DG_W];
  if (cd > 48) return cd - 11.4;
  return pathDist(x, z);
}

export function fastStreamDist(x, z) {
  if (!_streamGrid) ensureSpatialDistGrid();
  const gx = clamp(x >> 4, 0, DG_W - 1), gz = clamp(z >> 4, 0, DG_H - 1);
  const cd = _streamGrid[gx + gz * DG_W];
  if (cd > 68) return cd - 11.4;
  return streamDist(x, z);
}

// Gorge band (mountain start / ledge / south rim) with rough walls
// river in the middle of the northern valley
export function riverAt(x, z) {
  const g = gorgeEdges(x);
  if (z < g.n || z >= g.s) return 0;
  const t = (z - g.n) / (g.s - g.n);
  const a = Math.abs(t - 0.5);
  return a < 0.13 ? 2 : a < 0.19 ? 1 : 0; // 2 = water, 1 = gravel bank
}
const _gorgeTable = new Array(WX + 4);
for (let x = 0; x < _gorgeTable.length; x++) {
  const n = (hash2i(x >> 1, 7, 3) - 0.5) * 2;
  const s = (hash2i(x >> 1, 9, 5) - 0.5) * 2;
  _gorgeTable[x] = { m: P.gorge.m + n * 0.8, n: P.gorge.n + n * 0.8, s: P.gorge.s + s * 0.9 };
}
export function gorgeEdges(x) {
  const ix = clamp(x | 0, 0, WX + 3);
  return _gorgeTable[ix];
}

const CLEARINGS_FAST = CLEARINGS.map((c) => ({
  x: c.x,
  z: c.z,
  maxD: c.r + Math.ceil(28.0 / VS),
  cmx: c.x * VS,
  cmz: c.z * VS,
  cr: c.r * VS,
  ch: c.h * VS,
}));

// Integer ground level: voxels with y < groundH are solid.
function groundBase(x, z, skipMicro = false) {
  const xm = x * VS, zm = z * VS; // meters
  const oct = 2;
  // Smooth rolling hills and mountain ridges outside story clearings (no micro-voxel staircase noise)
  let hm = 7.5 + (fbm2(xm / 28, zm / 28, 11, oct) - 0.45) * 2.8;

  // High scenic mountain peaks away from story paths, clearings, and the river channel
  const ridgeNoise = Math.max(0, fbm2(xm / 36, zm / 36, 19, 2) - 0.52) * 8.5;
  const pd = fastPathDist(x, z);
  const sd = fastStreamDist(x, z);
  const pathClear = smoothstep(6, 38, pd) * smoothstep(28, 72, sd);
  hm += ridgeNoise * pathClear;

  const em = Math.max(12 - xm, xm - (WX * VS - 12), 12 - zm, zm - (WZ * VS - 12), 0);
  hm += em * 0.85;
  for (let i = 0; i < CLEARINGS_FAST.length; i++) {
    const c = CLEARINGS_FAST[i];
    if (Math.abs(x - c.x) > c.maxD || Math.abs(z - c.z) > c.maxD) continue;
    const d = Math.hypot(xm - c.cmx, zm - c.cmz) + (fbm2(xm / 12, zm / 12, 41, 2) - 0.5) * 3.2;
    const t = smoothstep(c.cr + 26.0, c.cr - 2.0, d);
    if (t > 0) hm = hm + (c.ch - hm) * t;
  }
  const g = gorgeEdges(x);
  const nb = Math.max(hm, 8.0);
  if (z < g.m) {
    const k = (g.m - z) * VS;
    hm = Math.max(hm, 8.0 + k * 0.85 + (fbm2(xm / 12, zm / 12, 31, 2) - 0.45) * 1.6 * Math.min(1, k / 5));
  } else if (z < g.n) {
    hm = nb;
  } else if (z < g.s) {
    const t = (z - g.n) / (g.s - g.n);
    hm = nb + (hm - nb) * t - Math.sin(Math.PI * t) * 1.8;
    const a = Math.abs(t - 0.5);
    if (a < 0.19) hm = 6.0;
    else if (a < 0.32) hm = Math.max(hm, 6.0 + (a - 0.19) * 4.0);
  }
  const T = P.tunnel;
  if (z <= T.grateZ + 1 && z >= T.z0 - 6) {
    const dx = Math.abs(x - (T.x0 + T.x1) / 2) * VS;
    const top = (T.y1 + 5) * VS - Math.max(0, dx - 3.5) * 0.8;
    if (top > hm) hm = top;
  }
  const SC = P.startCave;
  if (SC && x >= SC.x0 - 2 && x <= SC.x1 + 16 && z >= SC.z0 - 14 && z <= SC.z1 + 14) {
    const cx = (SC.x0 + SC.x1) * 0.5 + 2;
    const cz = (SC.z0 + SC.z1) * 0.5;
    const dx = Math.max(0, (x < SC.x0 ? (SC.x0 - x) * 1.8 : Math.abs(x - cx) - 22)) * VS;
    const dz = Math.max(0, Math.abs(z - cz) - 12) * VS;
    const d = Math.hypot(dx, dz);
    const top = (SC.y1 + 5) * VS - d * 0.8;
    if (top > hm) hm = top;
  }
  if (x >= 180 && x <= 604 && z >= 2040 && z <= 2324) {
    return 56;
  }
  const H = P.hubArena;
  if (H && x >= H.x0 - 14 && x <= H.x1 + 14 && z >= H.z0 - 14 && z <= H.z1 + 14) {
    return H.y;
  }
  const voxY = Math.round(hm / VS);
  return clamp(voxY, 2, WY - 2);
}

export function inHouse(x, z, m = 0) {
  // When checking tree/vegetation clearance (m >= 6), keep the entire Chapter 1 suburban block,
  // road loop, yards, and houses free of random forest trees.
  if (m >= 6 && x >= 178 - m && x <= 616 + m && z >= 2008 - m && z <= 2316 + m) {
    return true;
  }
  const H = P.hubArena;
  if (H && m >= 4 && x >= H.x0 - m - 16 && x <= H.x1 + m + 16 && z >= H.z0 - m - 16 && z <= H.z1 + m + 16) {
    return true;
  }
  const boxes = [P.house, P.ch1House, P.ch1MillerHouse, P.ch1WagnerHouse, P.ch1Apothecary, P.ch1UniHall, P.ch1Bookshop, P.ch1Arch, P.ch2Lab, P.ch3Garage, P.ch3Platform, P.ch4Motel, P.ch4Gas];
  for (let i = 0; i < boxes.length; i++) {
    const B = boxes[i];
    if (!B) continue;
    const minX = (B.yardX0 !== undefined ? B.yardX0 : (B.garageX0 !== undefined ? B.garageX0 : B.x0)) - m;
    const maxX = (B.yardX1 !== undefined ? B.yardX1 : B.x1) + m;
    const minZ = (B.yardZ0 !== undefined ? B.yardZ0 : B.z0) - m;
    const maxZ = (B.yardZ1 !== undefined ? B.yardZ1 : B.z1) + m;
    if (x >= minX && x <= maxX && z >= minZ && z <= maxZ) return true;
  }
  return false;
}

export const toM = (v) => v * VS;
export const toV = (m) => Math.floor(m / VS);

// ---------------------------------------------------------------- stream water level
// Sampled along the stream (index 0 = the spring under the cliff). The water level is the ground
// two blocks below the centre line, smoothed, made monotone (never rising downstream) and pinned
// at the scenes that depend on it (upstream wreck: 13, stepping stones: 12).
let _sp = null, _spGrid = null;
const SP_GRID = 16;
function streamProfile() {
  if (_sp) return _sp;
  const pts = [];
  for (let i = 0; i + 1 < STREAM.length; i++) {
    const a = STREAM[i], b = STREAM[i + 1], L = Math.hypot(b[0] - a[0], b[1] - a[1]), n = Math.max(1, Math.ceil(L));
    for (let k = 0; k < n; k++) pts.push([a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n]);
  }
  pts.push(STREAM[STREAM.length - 1]);
  const raw = pts.map(([x, z]) => groundBase(Math.round(x), Math.round(z)) - 2);
  const sm = raw.map((_, i) => { let s = 0, c = 0; for (let k = -36; k <= 36; k++) { const j = i + k; if (j >= 0 && j < raw.length) { s += raw[j]; c++; } } return s / c; });
  const pins = [];
  const pin = (px, pz, lv, r) => { pts.forEach(([x, z], i) => { if (Math.hypot(x - px, z - pz) < r) pins.push([i, lv]); }); };
  // Align pins with 0.125m clearing heights (upstream: 56, crossing & start: 52) so crossing and start share a flat water surface
  pin(P.upstream[0] - 32, P.upstream[1] + 4, 56, 120);
  pin(700, 1656, 52, 260);
  pin(P.stones.x, P.stones.zs[1], 52, 260);
  pin(1072, 2212, 52, 280);
  const pinAt = new Map(pins);
  const nextPin = new Float32Array(pts.length).fill(52);
  let cur = 52;
  for (let i = pts.length - 1; i >= 0; i--) { if (pinAt.has(i)) cur = Math.max(cur, pinAt.get(i)); nextPin[i] = cur; }
  const lv = new Int16Array(pts.length);
  let prev = 56;
  for (let i = 0; i < pts.length; i++) {
    let v = Math.min(prev, Math.round(sm[i]));
    v = Math.max(v, nextPin[i]);
    if (pinAt.has(i)) v = pinAt.get(i);
    v = Math.min(v, prev);
    lv[i] = v; prev = v;
  }
  // Smooth floating-point profile for terrain bank blending so discrete water steps never affect dry ground
  const lvFloat = new Float32Array(pts.length);
  for (let i = 0; i < pts.length; i++) {
    let s = 0, c = 0;
    for (let k = -48; k <= 48; k++) {
      const j = i + k;
      if (j >= 0 && j < pts.length) { s += lv[j]; c++; }
    }
    lvFloat[i] = s / c;
  }
  _sp = { pts, lv, lvFloat };

  // Precompute exact nearest stream point index for every 16x16 cell so streamLevel has zero grid discontinuities
  const GW = Math.ceil(WX / SP_GRID), GH = Math.ceil(WZ / SP_GRID);
  _spGrid = new Int32Array(GW * GH);
  for (let gz = 0; gz < GH; gz++) {
    const cz = gz * SP_GRID + (SP_GRID >> 1);
    const row = gz * GW;
    for (let gx = 0; gx < GW; gx++) {
      const cx = gx * SP_GRID + (SP_GRID >> 1);
      let best = 0, bd = 1e18;
      for (let i = 0; i < pts.length; i += 4) {
        const d = (pts[i][0] - cx) ** 2 + (pts[i][1] - cz) ** 2;
        if (d < bd) { bd = d; best = i; }
      }
      const i0 = Math.max(0, best - 6), i1 = Math.min(pts.length, best + 7);
      for (let i = i0; i < i1; i++) {
        const d = (pts[i][0] - cx) ** 2 + (pts[i][1] - cz) ** 2;
        if (d < bd) { bd = d; best = i; }
      }
      _spGrid[row + gx] = best;
    }
  }
  return _sp;
}
function nearestStreamIdx(x, z) {
  const S = streamProfile();
  const GW = Math.ceil(WX / SP_GRID), GH = Math.ceil(WZ / SP_GRID);
  const gx = clamp(x >> 4, 0, GW - 1), gz = clamp(z >> 4, 0, GH - 1);
  const startIdx = _spGrid[gx + gz * GW];
  let best = startIdx, bd = 1e18;
  const range = 140;
  const i0 = Math.max(0, startIdx - range), i1 = Math.min(S.pts.length, startIdx + range);
  for (let i = i0; i < i1; i++) {
    const d = (S.pts[i][0] - x) ** 2 + (S.pts[i][1] - z) ** 2;
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}
export function streamLevel(x, z) {
  const S = streamProfile();
  return S.lv[nearestStreamIdx(x, z)];
}
export function streamLevelFloat(x, z) {
  const S = streamProfile();
  return S.lvFloat[nearestStreamIdx(x, z)];
}
// Integer ground level: voxels with y < groundH are solid. Near the stream the ground follows the
// smooth float water level (two above it in the channel), sloping back to the natural terrain without steps.
// The built landscape (roads, railway bed, field, gardens, gully) is applied last, so groundBase and the
// stream profile derived from it never change.
export function groundH(x, z, skipMicro = false) {
  let h = groundBase(x, z, skipMicro);
  let sd = fastStreamDist(x, z);
  const hw = streamHW(z);
  // floodplain of the middle reach: a low, almost level meadow on both banks
  if (z > FLOOD_Z0 && z < FLOOD_Z1 && sd < hw + 84) {
    sd = streamDist(x, z);
    if (sd < hw + 70) {
      const wf = 0.75 * smoothstep(hw + 70, hw + 26, sd) * smoothstep(FLOOD_Z0, FLOOD_Z0 + 60, z) * smoothstep(FLOOD_Z1, FLOOD_Z1 - 60, z);
      h += (streamLevelFloat(x, z) + 3 - h) * wf;
    }
  }
  if (sd <= hw + 22) {
    const w = smoothstep(hw + 22, hw + 1, sd);
    h += (streamLevelFloat(x, z) + 2 - h) * w;
  }
  return landEval(x, z, h, sd, hw);
}

// ====================================================================== landscape of the settlement
// Terrain-only features (not story routes), voxel coordinates:
//   HIGHWAY     asphalt road from the west edge, bending south at the roadside hotel «Поворот»
//   RAIL        single-track spur from the east edge to the buffer stop behind the platform
//   STREET      rutted dirt village street, joins the highway
//   FIELD_TRACK two-rut service track across the field and up the power-line clearing
//   POWERLINE   power-line corridor: village -> field -> forest clearing -> gorge crossing
//   GULLY       erosion gully cutting from the field down to the stream
//   FIELD       harvested grain field (stubble rows);  GARDENS  plots behind the houses;  PASTURE  treeless meadow
function arcPts(cx, cz, r, a0, a1, n) {
  const o = [];
  for (let i = 0; i <= n; i++) { const a = (a0 + (a1 - a0) * i / n) * Math.PI / 180; o.push([Math.round(cx + r * Math.cos(a)), Math.round(cz + r * Math.sin(a))]); }
  return o;
}
// polyline with per-segment lengths and reach-expanded boxes (R = how far the feature influences the ground)
function poly(pts, R, extra) {
  const n = pts.length - 1, len = new Float32Array(n), cum = new Float32Array(n + 1), box = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const a = pts[i], b = pts[i + 1];
    len[i] = Math.hypot(b[0] - a[0], b[1] - a[1]); cum[i + 1] = cum[i] + len[i];
    box[i * 4] = Math.min(a[0], b[0]) - R; box[i * 4 + 1] = Math.max(a[0], b[0]) + R;
    box[i * 4 + 2] = Math.min(a[1], b[1]) - R; box[i * 4 + 3] = Math.max(a[1], b[1]) + R;
  }
  return Object.assign({ pts, len, cum, box, total: cum[n], R }, extra);
}
export const HIGHWAY = poly([[-64, 1836], ...arcPts(700, 1906, 70, -90, 0, 6), [770, WZ + 64]], 70, { hw: 24, sh: 6, y: 56 });
export const RAIL = poly([[620, 2105], [860, 2105], [900, 2102], [940, 2092], [980, 2076], [1020, 2064], [1060, 2060], [WX + 64, 2060]], 44, { hw: 11, y: 56, bed: 2 });
export const STREET = poly([[-40, 2159], [744, 2159]], 28, { hw: 13, y: 56 });
export const FIELD_TRACK = poly([[250, 1806], [250, 1580], [232, 1420], [214, 1300]], 26, { hw: 9 });
export const POWERLINE = poly([[236, 2066], [236, 1576], [210, 1300], [196, 1000], [196, 560]], 34, { hw: 28 });
export const GULLY = poly([[448, 1716], [516, 1690], [580, 1660], [628, 1636], [645, 1627]], 40, { depth: 17 });
export const FIELD = { x0: 112, x1: 464, z0: 1576, z1: 1792, y: 56 };
// garden plots: 4 columns x 2 rows separated by grass balks; kind: 0 potato ridges N-S, 1 potato ridges E-W,
// 2 vegetable beds, 3 dug-over soil, 4 fallow (grass)
export const GARDENS = { x0: 196, x1: 588, z0: 2328, z1: 2440, cols: [196, 284, 392, 500, 588], rows: [2328, 2384, 2440], kinds: [2, 0, 2, 1, 1, 3, 0, 4], balk: 3 };
export const PASTURE = { x0: 104, x1: 330, z0: 1872, z1: 2062 };
const FLOOD_Z0 = 1470, FLOOD_Z1 = 1800;

// surface codes returned by landSurface(); worldgen maps them to materials
export const LS = { NONE: 0, ASPHALT: 1, MARK: 2, SHOULDER: 3, BALLAST: 4, RUT: 5, TRACK: 6, STUBBLE: 7, SOIL: 8, TILLED: 9, BEDPATH: 10,
  GULLY_WALL: 11, GULLY_BED: 12, CLEARCUT: 13, BEACH: 14, PEBBLE: 15, FLOOD: 16 };

// nearest point on a feature polyline -> distance; _ps = arc length there, _pside = -1 | 1 (left / right of travel)
let _pd = 1e9, _ps = 0, _pside = 1;
function polyNear(pl, x, z) {
  const p = pl.pts, b = pl.box;
  let best = 1e18, bs = 0, side = 1;
  for (let i = 0, n = p.length - 1; i < n; i++) {
    const k = i * 4;
    if (x < b[k] || x > b[k + 1] || z < b[k + 2] || z > b[k + 3]) continue;
    const ax = p[i][0], az = p[i][1], dx = p[i + 1][0] - ax, dz = p[i + 1][1] - az, L = pl.len[i];
    let t = L > 0 ? ((x - ax) * dx + (z - az) * dz) / (L * L) : 0;
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    const ex = ax + dx * t - x, ez = az + dz * t - z, d2 = ex * ex + ez * ez;
    if (d2 < best) { best = d2; bs = pl.cum[i] + t * L; side = dx * (z - az) - dz * (x - ax) < 0 ? -1 : 1; }
  }
  _pd = best < 1e17 ? Math.sqrt(best) : 1e9; _ps = bs; _pside = side;
  return _pd;
}
const rectSd = (r, x, z) => Math.max(r.x0 - x, x - r.x1, r.z0 - z, z - r.z1); // < 0 inside

// two wheel ruts with a grassy hump between them; d = distance from the centre line
let _rc = 0, _rdh = 0;
function rutProfile(d, hw, x, z) {
  _rc = 0; _rdh = 0;
  if (d >= 4.5 && d < 8.5) {
    _rc = LS.RUT;
    if (d >= 5.5 && d < 7.5 && fbm2(_ps / 44, _pside * 3.1, 51, 2) > 0.34) _rdh = -1; // worn deeper in places
  } else if (d < 4.5) {
    if (fbm2(x / 10, z / 10, 53, 2) < 0.5) _rc = LS.TRACK;
  } else if (d < hw - 2.5 + hash2i(x, z, 17) * 2.5) _rc = LS.TRACK;
}

// Applies the built landscape to the natural height h (voxels, float) and remembers the surface code of the column.
const _le = { x: -1, z: -1, code: 0 };
// coarse 16-voxel grid of cells any feature can reach: most columns of the map leave landEval at once
let _landGrid = null;
function landGrid() {
  const g = new Uint8Array(DG_W * DG_H);
  const mark = (x0, x1, z0, z1) => {
    for (let gz = clamp(Math.floor(z0) >> 4, 0, DG_H - 1); gz <= clamp(Math.ceil(z1) >> 4, 0, DG_H - 1); gz++)
      for (let gx = clamp(Math.floor(x0) >> 4, 0, DG_W - 1); gx <= clamp(Math.ceil(x1) >> 4, 0, DG_W - 1); gx++) g[gx + gz * DG_W] = 1;
  };
  for (const pl of [HIGHWAY, RAIL, STREET, FIELD_TRACK, POWERLINE, GULLY]) for (let i = 0; i < pl.len.length; i++) mark(pl.box[i * 4], pl.box[i * 4 + 1], pl.box[i * 4 + 2], pl.box[i * 4 + 3]);
  mark(FIELD.x0 - 24, FIELD.x1 + 24, FIELD.z0 - 24, FIELD.z1 + 24);
  mark(GARDENS.x0 - 16, GARDENS.x1 + 16, GARDENS.z0 - 16, GARDENS.z1 + 16);
  return g;
}
function landEval(x, z, h, sd, hw) {
  if (sd >= hw + 60 && !(_landGrid || (_landGrid = landGrid()))[clamp(x >> 4, 0, DG_W - 1) + clamp(z >> 4, 0, DG_H - 1) * DG_W]) {
    _le.x = x; _le.z = z; _le.code = 0;
    return clamp(Math.round(h), 2, WY - 2);
  }
  let code = 0, dh = 0, onStreet = false;

  if (x > FIELD.x0 - 24 && x < FIELD.x1 + 24 && z > FIELD.z0 - 24 && z < FIELD.z1 + 24) {
    // harvested field: level meadow-stubble plain with soft organic soil patches (no high-frequency stripe Moiré)
    const s = rectSd(FIELD, x, z);
    h += (FIELD.y - h) * smoothstep(24, -24, s);
    if (s < (hash2i(x >> 2, z >> 2, 13) - 0.5) * 8) {
      code = fbm2(x / 42, z / 42, 29, 2) > 0.68 ? LS.SOIL : LS.STUBBLE;
    }
  } else if (x >= GARDENS.x0 - 16 && x <= GARDENS.x1 + 16 && z >= GARDENS.z0 - 16 && z <= GARDENS.z1 + 16) {
    // garden plots behind the houses
    const s = rectSd(GARDENS, x, z);
    h += (56 - h) * smoothstep(16, -8, s);
    if (s <= 0) {
      const ci = x < GARDENS.cols[1] ? 0 : x < GARDENS.cols[2] ? 1 : x < GARDENS.cols[3] ? 2 : 3, ri = z < GARDENS.rows[1] ? 0 : 1;
      const u = x - GARDENS.cols[ci] - GARDENS.balk, v = z - GARDENS.rows[ri] - GARDENS.balk;
      const uw = GARDENS.cols[ci + 1] - GARDENS.cols[ci] - GARDENS.balk * 2, vw = GARDENS.rows[ri + 1] - GARDENS.rows[ri] - GARDENS.balk * 2;
      if (u >= 0 && v >= 0 && u <= uw && v <= vw) {
        const kind = GARDENS.kinds[ci + ri * 4];
        if (kind === 0 || kind === 1) {
          code = LS.TILLED;
        } else if (kind === 2) {
          if (Math.abs(u - (uw >> 1)) > 2) code = LS.TILLED; else code = LS.BEDPATH;
        } else if (kind === 3) code = LS.SOIL;
      }
    }
  }

  if (polyNear(GULLY, x, z) < 40) {
    // V-shaped erosion gully: narrow head in the field, wider and deeper towards the stream, never below the water
    const s = _ps / GULLY.total, d = _pd;
    const wg = (9 + 22 * Math.pow(s, 0.7)) * (0.82 + 0.36 * fbm2(x / 26, z / 26, 37, 2));
    if (d < wg) {
      const k = 1 - d / wg, hn = Math.max(h - GULLY.depth * smoothstep(0, 0.3, s) * Math.pow(k, 1.2), streamLevelFloat(x, z) + 1);
      if (hn < h - 0.6) { code = k > 0.78 ? LS.GULLY_BED : LS.GULLY_WALL; dh = 0; h = hn; }
    }
  }

  if (polyNear(STREET, x, z) < 24) {
    const d = _pd;
    h += (STREET.y - h) * smoothstep(24, STREET.hw, d);
    if (d <= STREET.hw + 0.5) {
      onStreet = true;
      if (x >= 184 && x <= 598 && z >= 2040 && z <= 2320) {
        code = LS.ASPHALT; dh = 0;
      } else {
        rutProfile(d, STREET.hw, x, z); code = _rc; dh = _rdh;
      }
    }
  }
  if (polyNear(FIELD_TRACK, x, z) <= FIELD_TRACK.hw + 0.5) {
    rutProfile(_pd, FIELD_TRACK.hw, x, z);
    if (_rc) { code = _rc; dh = _rdh; }
  }

  if (polyNear(HIGHWAY, x, z) < 68) {
    const d = _pd, e = HIGHWAY.hw + HIGHWAY.sh;
    if (d <= e) {
      h = HIGHWAY.y; dh = 0;
      code = d > HIGHWAY.hw ? LS.SHOULDER : (d < 0.9 && _ps % 48 < 24 ? LS.MARK : LS.ASPHALT);
    } else {
      h += (HIGHWAY.y - h) * (1 - smoothstep(e, e + 38, d));
      // roadside ditch, bridged where the street and the footpaths join the road
      if (d < e + 11 && !onStreet && fastPathDist(x, z) > 3) { h -= 2.2 * Math.sin(Math.PI * clamp((d - e - 1) / 10, 0, 1)); dh = 0; if (code === LS.STUBBLE || code === LS.SOIL) code = 0; }
    }
  }

  if (polyNear(RAIL, x, z) < 44) {
    const d = _pd, road = code === LS.ASPHALT || code === LS.MARK || code === LS.SHOULDER;
    h += (RAIL.y - h) * (1 - smoothstep(15, 43, d)); // subgrade: embankment over hollows, cutting through rises
    if (d <= 15.5) {
      dh = 0;
      if (road) { if (d <= 13) h = RAIL.y + 1; } // level crossing: the asphalt rises to the rails
      else {
        h = RAIL.y + (d <= RAIL.hw ? RAIL.bed : d <= 13 ? 1 : 0); // ballast prism
        if (d <= 13 || hash2i(x, z, 19) > 0.45) code = LS.BALLAST;
      }
    }
  }

  if (code === 0 && sd < hw + 60) {
    const cd = Math.hypot(x - P.crossing[0], z - P.crossing[1]);
    if (cd < 170 && sd < hw + 6 + 16 * fbm2(x / 30, z / 30, 43, 2) * smoothstep(170, 110, cd)) code = fbm2(x / 5, z / 5, 47, 2) > 0.66 ? LS.PEBBLE : LS.BEACH; // sandy shore at the crossing
    else if (z > FLOOD_Z0 + 20 && z < FLOOD_Z1 - 20 && sd < hw + 56) code = LS.FLOOD;
  } else if (code === 0 && polyNear(POWERLINE, x, z) < 23 + hash2i(x >> 2, z >> 2, 23) * 6) code = LS.CLEARCUT;

  _le.x = x; _le.z = z; _le.code = code;
  return clamp(Math.round(h) + dh, 2, WY - 2);
}

// surface code of the column (LS.*); 0 = natural ground
export function landSurface(x, z) {
  if (_le.x !== x || _le.z !== z) groundH(x, z);
  return _le.code;
}

// distance in voxels to the edge of the nearest road surface (highway shoulder, street, field track, rail bed)
export function roadEdgeDist(x, z) {
  return Math.min(polyNear(HIGHWAY, x, z) - HIGHWAY.hw - HIGHWAY.sh, polyNear(STREET, x, z) - STREET.hw, polyNear(FIELD_TRACK, x, z) - FIELD_TRACK.hw, polyNear(RAIL, x, z) - 15);
}

// open land and transport corridors: no trees, bushes or boulders here
export function landOpen(x, z) {
  const H = P.hubArena;
  if (H && x >= H.x0 - 20 && x <= H.x1 + 20 && z >= H.z0 - 20 && z <= H.z1 + 20) return true;
  if (rectSd(FIELD, x, z) < 10 || rectSd(GARDENS, x, z) < 10 || rectSd(PASTURE, x, z) < 0) return true;
  return polyNear(HIGHWAY, x, z) < 60 || polyNear(RAIL, x, z) < 42 || polyNear(STREET, x, z) < 27 || polyNear(FIELD_TRACK, x, z) < 24
    || polyNear(POWERLINE, x, z) < 30 || polyNear(GULLY, x, z) < 30;
}
