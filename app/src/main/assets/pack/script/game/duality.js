// Dream / nightmare state: transition waves, anchor bubbles, perception stability.
// worldAt() mirrors the WGSL function exactly so collisions match what the player sees.
import { vnoise3 } from '../engine/noise.js';
import { WX, WY, WZ, VS } from '../world/layout.js';
import { matFlags, F_SOLID, F_HAZARD, F_WATER, notGround } from '../world/materials.js';

const _FLICKER_OPTS = { speed: 60, quiet: true };

export class Duality {
  constructor() {
    this.base = 0;
    // oc/ro: outer front of a reversed wave (ro = 0: none) - beyond it the target world is shown
    this.wave = { active: false, from: 0, to: 0, c: [0, 0, 0], r: 0, speed: 34, oc: [0, 0, 0], ro: 0 };
    this.bubbles = [];      // [x,y,z,r]
    this.stability = 100;
    this.nightTimer = 0;    // >0 : auto-return to dream when it expires
    this.flicker = 0;       // seconds of chaotic flicker remaining
    this.flickerNext = 0;
    this.baseNight = false; // chapter 3: nightmare is the default world
    this.onFlip = null;
    this.drain = 2.2;       // stability loss per second in nightmare
    this.regen = 1.5;
  }
  worldAt(x, y, z) {
    let w = this.base;
    const W = this.wave;
    if (W.active) {
      let d = Math.hypot(x - W.c[0], y - W.c[1], z - W.c[2]);
      if (Math.abs(d - W.r) < 1.6) d += (vnoise3(x * 0.35, y * 0.35, z * 0.35) - 0.5) * 3;
      let inside = d < W.r;
      if (W.ro > 0) {
        let d2 = Math.hypot(x - W.oc[0], y - W.oc[1], z - W.oc[2]);
        if (Math.abs(d2 - W.ro) < 1.6) d2 += (vnoise3(x * 0.35, y * 0.35, z * 0.35) - 0.5) * 3;
        inside = inside || d2 > W.ro;
      }
      w = inside ? W.to : W.from;
    }
    for (const b of this.bubbles) {
      let d = Math.hypot(x - b[0], y - b[1], z - b[2]);
      if (Math.abs(d - b[3]) < 0.7) d += (vnoise3(x * 0.6 + 7, y * 0.6 + 7, z * 0.6 + 7) - 0.5) * 1.2;
      if (d < b[3]) w = 0;
    }
    return w;
  }
  get target() { return this.wave.active ? this.wave.to : this.base; }
  flip(to, center, opts = {}) {
    const W = this.wave;
    if (W.active && W.to === to && !opts.force) return false; // already turning into that world
    if (W.active && W.to !== to && W.ro === 0 && W.r < 95) {
      // reverse a running wave without a jump: inside its front the world turns back from the new
      // centre outward, the part it never reached keeps showing the old (= new target) world
      W.oc[0] = W.c[0]; W.oc[1] = W.c[1]; W.oc[2] = W.c[2]; W.ro = W.r;
      W.from = W.to; W.to = to;
      W.c[0] = center[0]; W.c[1] = center[1]; W.c[2] = center[2];
      W.r = opts.r0 || 0; W.speed = opts.speed || 34;
      if (this.onFlip) this.onFlip(to, opts);
      return true;
    }
    if (W.active) { this.base = W.to; W.active = false; }
    if (this.base === to && !opts.force) return false;
    W.ro = 0;
    W.active = true; W.from = this.base; W.to = to;
    W.c[0] = center[0]; W.c[1] = center[1]; W.c[2] = center[2];
    W.r = opts.r0 || 0; W.speed = opts.speed || 34;
    if (this.onFlip) this.onFlip(to, opts);
    return true;
  }
  // nightmare for `dur` seconds then back to dream (unless nightmare is the base world)
  toNight(center, dur, opts) { this.flip(1, center, opts); this.nightTimer = dur; }
  toDream(center, opts) { this.flip(0, center, opts); this.nightTimer = 0; }
  update(dt, playerPos, paused) {
    const W = this.wave;
    if (W.active) {
      W.r += W.speed * dt;
      // done when it is past the fog, or when it has swallowed the outer front of a reversed wave
      const covered = W.ro > 0 && W.r > W.ro + Math.hypot(W.c[0] - W.oc[0], W.c[1] - W.oc[1], W.c[2] - W.oc[2]) + 2;
      if (W.r > 95 || covered) { this.base = W.to; W.active = false; W.ro = 0; }
    }
    if (paused) return;
    if (this.nightTimer > 0) {
      this.nightTimer -= dt;
      if (this.nightTimer <= 0 && !this.baseNight) this.toDream(playerPos);
    }
    if (this.flicker > 0) {
      this.flicker -= dt;
      this.flickerNext -= dt;
      if (this.flickerNext <= 0) {
        this.flickerNext = 0.6 + Math.random() * 2.6;
        this.flip(this.target ? 0 : 1, playerPos, _FLICKER_OPTS);
      }
      if (this.flicker <= 0) { if (this.baseNight) this.flip(1, playerPos); else this.toDream(playerPos); }
    }
  }
}

// CPU-side voxel world (main thread copy, backed by 32³ Empty/Solid/Palette/Dense ChunkedVoxelStorage)
import { ChunkedVoxelStorage } from '../world/chunkStore.js';

export class VoxelWorld {
  constructor(data) {
    if (data instanceof ChunkedVoxelStorage) {
      this.chunkStore = data;
    } else {
      this.chunkStore = new ChunkedVoxelStorage(data);
    }
    this.propColliders = [];
  }
  addCollider(box) {
    const c = {
      x0: Math.min(box.x0, box.x1),
      y0: Math.min(box.y0, box.y1),
      z0: Math.min(box.z0, box.z1),
      x1: Math.max(box.x0, box.x1),
      y1: Math.max(box.y0, box.y1),
      z1: Math.max(box.z0, box.z1),
      mask: box.mask ?? 3,
      tag: box.tag || '',
    };
    this.propColliders.push(c);
    return c;
  }
  clearColliders() {
    this.propColliders.length = 0;
  }
  hitsPropCollider(x0, y0, z0, x1, y1, z1, w, ignoreTag = null) {
    const bit = w ? 2 : 1;
    const list = this.propColliders;
    for (let i = 0; i < list.length; i++) {
      const c = list[i];
      if (!(c.mask & bit)) continue;
      if (ignoreTag && c.tag === ignoreTag) continue;
      if (x1 > c.x0 && x0 < c.x1 && y1 > c.y0 && y0 < c.y1 && z1 > c.z0 && z0 < c.z1) return true;
    }
    return false;
  }
  vox(x, y, z) {
    if (x < 0 || x >= WX || z < 0 || z >= WZ || y < 0 || y >= WY) return 0;
    const v = this.chunkStore.getVoxel(x, y, z);
    if (v !== 0) return v;
    if (this.streamer && this.hm) {
      const mi = (x >> 6) + (WX >> 6) * (z >> 6);
      if (this.streamer.states[mi] !== 2) {
        const idx = x + z * WX;
        const hD = Math.round(this.hm.hd[idx] / VS);
        const hN = Math.round(this.hm.hn[idx] / VS);
        const d = y < hD ? 1 : 0;
        const n = y < hN ? 20 : 0;
        return d | (n << 8);
      }
    }
    return 0;
  }
  setVox(x, y, z, val) {
    return this.chunkStore.setVoxel(x, y, z, val);
  }
  mat(x, y, z, w) { const v = this.vox(x, y, z); return w ? v >> 8 : v & 255; }
  solid(x, y, z, w) {
    if (y < 0) return true;
    if (x < 0 || x >= WX || z < 0 || z >= WZ) return true;
    return (matFlags[this.mat(x, y, z, w)] & F_SOLID) !== 0;
  }
  solidM(x, y, z, w) { return this.solid(Math.floor(x / VS), Math.floor(y / VS), Math.floor(z / VS), w); }
  hazardM(x, y, z, w) { const m = this.mat(Math.floor(x / VS), Math.floor(y / VS), Math.floor(z / VS), w); return (matFlags[m] & F_HAZARD) !== 0; }
  waterM(x, y, z) { return (matFlags[this.mat(Math.floor(x / VS), Math.floor(y / VS), Math.floor(z / VS), 0)] & F_WATER) !== 0; }
  _hasHeadroom(vx, y, vz, w, hV) {
    for (let dy = 0; dy < hV; dy++) {
      if (this.solid(vx, y + dy, vz, w)) return false;
    }
    return true;
  }
  // every height (meters) where a person can stand on real ground: solid, non-foliage,
  // non-roof support below and ~2 m of free air above
  standLevels(x, z, w) {
    const vx = Math.floor(x / VS), vz = Math.floor(z / VS), out = [];
    const hV = Math.ceil(2.0 / VS); // clearance for ~2.0m character height
    for (let y = 1; y < WY - hV; y++) {
      if (!this.solid(vx, y - 1, vz, w) || notGround[this.mat(vx, y - 1, vz, w)]) continue;
      if (!this._hasHeadroom(vx, y, vz, w, hV)) continue;
      if (matFlags[this.mat(vx, y, vz, w)] & F_HAZARD) continue;
      out.push(y * VS);
    }
    return out;
  }
  // safe standing height nearest to a hint (or the lowest one); null if the column has none (zero allocation)
  safeY(x, z, w, hint) {
    const vx = Math.floor(x / VS), vz = Math.floor(z / VS);
    const hV = Math.ceil(2.0 / VS);
    let best = null;
    let bestDist = 1e9;
    for (let y = 1; y < WY - hV; y++) {
      if (!this.solid(vx, y - 1, vz, w) || notGround[this.mat(vx, y - 1, vz, w)]) continue;
      if (!this._hasHeadroom(vx, y, vz, w, hV)) continue;
      if (matFlags[this.mat(vx, y, vz, w)] & F_HAZARD) continue;
      const yM = y * VS;
      if (hint === undefined || hint === null) return yM;
      const dist = Math.abs(yM - hint);
      if (dist < bestDist) {
        bestDist = dist;
        best = yM;
      }
    }
    return best;
  }
  // lowest spot (meters) where a person can stand: solid below, ~2 m of air above
  standM(x, z, w) {
    const vx = Math.floor(x / VS), vz = Math.floor(z / VS);
    const hV = Math.ceil(2.0 / VS);
    for (let y = 1; y < WY - hV; y++) {
      if (this.solid(vx, y - 1, vz, w) && this._hasHeadroom(vx, y, vz, w, hV)) return y * VS;
    }
    return this.groundM(x, z, w);
  }
  // highest solid top (meters) at column for world w, scanning down from yStart
  groundM(x, z, w, yStart = WY * VS) {
    const vx = Math.floor(x / VS), vz = Math.floor(z / VS);
    for (let y = Math.min(WY - 1, Math.floor(yStart / VS)); y >= 0; y--) if (this.solid(vx, y, vz, w)) return (y + 1) * VS;
    return 0;
  }
}
