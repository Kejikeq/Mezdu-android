// The web game's Game object (src/main.js) as the story scripts of the pack use it (script/game/story.js and
// story/*): flags, inventory, interactables, triggers, timers and props live here in JS; what the player must see
// or answer goes out as events (__drain) to the native interface, which answers the waiting ones (__answer).
// The host gives: __host.solid(vx, vy, vz) (dream world voxels), __host.ground(x, z) and __host.log(text).
// Parts of the game not ported yet (light, sound, particles, cinema, the nightmare, puzzles) are quiet stubs.
const H = globalThis.__host;
const out = [];
const emit = (e) => { out.push(e); };
const log = (t) => H.log(String(t));

// any member, any call, never a promise (`await stub` goes on at once)
const stub = new Proxy(function () {}, {
  get: (t, k) => (k === 'then' || typeof k === 'symbol' ? undefined : stub),
  apply: () => stub,
});
const quiet = (real) => new Proxy(real, { get: (t, k) => (k in t ? t[k] : k === 'then' || typeof k === 'symbol' ? undefined : stub) });

// questions to the player: the interface answers with __answer(id, value)
const pending = new Map();
let nextId = 1;
const ask = (e) => new Promise((res) => { const id = nextId++; pending.set(id, res); emit(Object.assign({ id }, e)); });

const actor = () => ({ visible: false, pos: [0, 0, 0], yaw: 0, speed: 0, target: null, fade: 1 });
let ITEMS = {};
let scoreInteractable = null;

class Prop {
  constructor(model, x, y, z, yaw, o) {
    Object.assign(this, { model, x, y, z, yaw, pitch: o.pitch || 0, roll: o.roll || 0, s: o.scale || 1, mask: o.mask ?? 3, vis: o.visible !== false, hl: false });
    if (!this.vis) this._send();
  }
  _send() { emit({ t: 'prop', model: this.model, p: [this.x, this.y, this.z], on: this.vis }); }
  show(v) { this.vis = !!v; this._send(); return this; }
  setModel(m) { if (m !== this.model) { emit({ t: 'prop', model: this.model, p: [this.x, this.y, this.z], on: false }); this.model = m; this._send(); } return this; }
  highlight() { return this; }
  move(x, y, z, yaw) { Object.assign(this, { x, y, z, yaw: yaw ?? this.yaw }); return this; }
}

const say = (text, dur = 4, who) => { if (text) emit({ t: 'say', text: String(text), dur, who: who || '' }); };

const ui = quiet({
  read: (paras, night, sig) => ask({ t: 'read', paras: [].concat(paras).map(String), night: !!night, title: sig || '' }),
  inspect: (o) => ask({ t: 'inspect', title: o.title || '', desc: o.desc || '', kicker: o.kicker || '', item: o.item || '', buttons: (o.buttons || [{ label: 'Закрыть', value: true }]).map((b) => [b.label, b.value]) }),
  toast: (text) => emit({ t: 'toast', text: String(text) }),
  cineLine: (text, dur, who) => say(text, dur || 4, who),
  chapterCard: (n, title) => say(title ? `Глава ${n}. ${title}` : `Глава ${n}`, 4),
  say: (text, dur, night, who) => say(text, dur, who),
  setObjective: (t) => emit({ t: 'objective', text: t ? String(t) : '' }),
  prompt: () => {},
  domFade: () => Promise.resolve(),
  cinema: () => {},
});

const memoryBoard = quiet({
  clues: new Set(), testimony: new Set(),
  addClue(id) { this.clues.add(id); },
  addTestimony(id) { this.testimony.add(id); },
  hasClue(id) { return this.clues.has(id); },
  hasTestimony(id) { return this.testimony.has(id); },
  adapt: (v) => v.default || v.TRUTH || '',
  getProfile: () => 'default',
  getConclusion: () => null,
  getChapterClues: () => [],
  serialize() { return { clues: [...this.clues], testimony: [...this.testimony] }; },
  deserialize(d) { this.clues = new Set((d && d.clues) || []); this.testimony = new Set((d && d.testimony) || []); },
  reset() { this.clues.clear(); this.testimony.clear(); },
  refreshBadge() {},
});

const EDITS = { ch1Door: false, ch2Door: false, ch3Door: false, ch4Door: false, startCave: false, bridge1: false, door: false, hedge1: false, hedge2: false, grate: false, tunnelWall: false, hearth: false };

const G = quiet({
  chapter: 1, state: 'game', time: 0, playtime: 0, flags: {}, inv: [], edits: Object.assign({}, EDITS), cp: null,
  interactables: [], triggers: [], updaters: [], waits: [], lights: [], anchors: [],
  sceneName: '', headache: 0, voidMode: false, glitch: 0, fadeV: 0, fadeTo: 0, fadeCol: [0, 0, 0], camOverride: null,
  cineLock: false, busy: false, flashOn: false, heartOverride: null, fearExtra: 0, TransitioningChapter: false, peering: false,
  settings: { sens: 1, invertY: false, vibrate: true },
  player: quiet({
    pos: [0, 0, 0], yaw: 0, camYaw: 0, pose: 'idle', lockPose: false, seat: null, holdingTool: null, speed: 0, speedMul: 1,
    visY: 0, vel: [0, 0, 0], phase: 0, camPos: [0, 0, 0], camTarget: [0, 0, 1], camDist: 3.2, camDistCur: 3.2,
    place(x, y, z, yaw) { this.pos = [x, y, z]; if (yaw !== undefined) this.yaw = yaw; emit({ t: 'teleport', p: [x, y, z], yaw: this.yaw }); },
    updateCamera() {},
  }),
  duality: quiet({ stability: 100, base: 0, baseNight: false, nightTimer: 0, flicker: 0, drain: 1, regen: 1, wave: { active: false }, bubbles: [], worldAt: () => 0, flip: () => false }),
  deer: actor(), rabbit: actor(), mike: actor(), shadow: actor(),
  models: new Proxy({}, { get: (t, k) => (typeof k === 'string' && k !== 'then' ? k : undefined) }),
  ui, memoryBoard,
  audio: stub, emit: stub, world: stub, figures: quiet({ list: [], add: () => stub, clear() {} }),
  streamer: quiet({ loadChapter: () => Promise.resolve(), burst() {} }),

  interact(o) { const it = Object.assign({ r: 2.2, world: 'any', icon: 'hand', label: 'Осмотреть' }, o); this.interactables.push(it); return it; },
  trigger(o) { const t = Object.assign({ once: true, r: 3 }, o); this.triggers.push(t); return t; },
  light(o) { const l = Object.assign({ mask: 1, r: 7, col: [1, 0.7, 0.4], k: 1 }, o); this.lights.push(l); return l; },
  anchor(o) { const a = Object.assign({ r: 5 }, o); this.anchors.push(a); return a; },
  onUpdate(fn) { this.updaters.push(fn); },
  flag(k) { return this.flags[k]; },
  set(k, v = true) { this.flags[k] = v; },
  has(id) { return this.inv.some((i) => i.id === id); },
  give(id, silent) {
    if (this.has(id) || !ITEMS[id]) return;
    this.inv.push({ id, seen: false });
    if (!silent) emit({ t: 'toast', text: 'В вещах: ' + ITEMS[id].name });
    this.refreshTools();
  },
  take(id) { this.inv = this.inv.filter((i) => i.id !== id); this.refreshTools(); },
  refreshTools() { emit({ t: 'inv' }); },
  wait(s) { return new Promise((res) => this.waits.push({ t: this.time + s, res })); },
  flushWaits() { while (this.waits.length) this.waits.shift().res(); },
  say(text, dur = 4, who) { say(text, dur, who); },
  objective(t) { ui.setObjective(t); },
  fade(to, dur = 1) { this.fadeV = to; return this.wait(Math.min(dur, 2)); },
  vibrate() {},
  worldAtPlayer() { return 0; },
  toNight() {}, toDream() {}, stopPeer() {},
  stab(d) { this.duality.stability = Math.max(0, Math.min(100, this.duality.stability + d)); },
  lock(v) { this.cineLock = !!v; },
  async pickup(id, opts = {}) {
    const def = ITEMS[id];
    if (!def) return false;
    const ok = await ask({ t: 'inspect', item: id, kicker: opts.kicker || 'находка', title: def.name, desc: opts.desc || def.desc, buttons: [['Взять', true], ['Оставить', false]] });
    if (ok) this.give(id);
    return ok;
  },
  inspect(model, title, desc, kicker = 'осмотр') { return ask({ t: 'inspect', item: '', kicker, title: title || '', desc: desc || '', buttons: [['Закрыть', true]] }); },
  read(paras, night, sig) { return ui.read(paras, night, sig); },
  place(model, x, y, z, yaw = 0, o = {}) {
    if (y === null || y === undefined) y = this.groundAt(x, z, o.mask === 2 ? 1 : 0);
    return new Prop(model, x, y, z, yaw, o);
  },
  placeSafe(x, y, z, yaw) { this.player.place(x, y ?? this.groundAt(x, z), z, yaw); },
  groundAt(x, z) { return H.ground(x, z); },
  groundBelow(x, y, z) { return H.ground(x, z); },
  setEdit(name, on) { this.edits[name] = !!on; return Promise.resolve(); },
  checkpoint() { this.cp = { pos: this.player.pos.slice(), yaw: this.player.yaw }; },
  enterMenu() { emit({ t: 'menu' }); },
  resetRun() {
    this.flags = {}; this.inv = []; this.chapter = 1; this.cp = null; this.playtime = 0;
    this.edits = Object.assign({}, EDITS);
    memoryBoard.reset();
    this.waits.length = 0;
    for (const it of this.interactables) it.done = false;
    for (const t of this.triggers) { t.fired = false; t.inside = false; }
  },
});
globalThis.G = G;

// ------------------------------------------------------------------ calls from the native side
let cur = null, curLabel = null;
const run = async (it) => {
  G.busy = true;
  try { await it.run(it); } catch (e) { log('script: ' + (e && e.stack || e)); }
  if (it.once) it.done = true;
  G.busy = false;
};
const prompt = (it) => {
  const label = it ? String(typeof it.label === 'function' ? it.label() : it.label) : null;
  if (label !== curLabel) {
    curLabel = label;
    emit({ t: 'prompt', label: label || '', icon: it ? String(typeof it.icon === 'function' ? it.icon() : it.icon) : '' });
  }
};
const los = { playerPos: null, playerYaw: 0, camPos: [0, 0, 0], camForward: [0, 0, 1], solidVoxelFn: (x, y, z) => H.solid(x, y, z), vs: 0.125 };

globalThis.__boot = async (mods) => {
  ITEMS = mods.ITEMS;
  scoreInteractable = mods.scoreInteractable;
  mods.setupStory(G);
  log(`story: ${G.interactables.length} interactables, ${G.triggers.length} triggers, ${Object.keys(ITEMS).length} items`);
};

/** a new game: chapter 1 from its start */
globalThis.__newGame = async () => { G.resetRun(); await G.story.restore(); };

/** every frame, first the camera (position, forward vector), then the hero (feet, facing) */
const camFwd = [0, 0, 1];
globalThis.__cam = (cx, cy, cz, fx, fy, fz) => {
  const c = G.player.camPos;
  c[0] = cx; c[1] = cy; c[2] = cz; camFwd[0] = fx; camFwd[1] = fy; camFwd[2] = fz;
};
globalThis.__tick = (dt, px, py, pz, yaw) => {
  G.time += dt; G.playtime += dt;
  const p = G.player;
  p.pos[0] = px; p.pos[1] = py; p.pos[2] = pz; p.yaw = yaw;
  for (let i = G.waits.length - 1; i >= 0; i--) {
    if (G.time >= G.waits[i].t) { const w = G.waits[i]; G.waits.splice(i, 1); w.res(); }
  }
  try {
    for (const t of G.triggers) {
      if (t.fired && t.once) continue;
      if (t.cond && !t.cond()) continue;
      const inside = t.test ? t.test(p.pos) : Math.hypot(p.pos[0] - t.pos[0], p.pos[2] - t.pos[2]) < t.r;
      if (inside && !t.inside) { t.inside = true; if (!(t.once && t.fired)) { t.fired = true; Promise.resolve(t.run()).catch((e) => log('trigger: ' + e)); } }
      else if (!inside) t.inside = false;
    }
    for (const f of G.updaters) f(dt);
  } catch (e) { log('update: ' + (e && e.stack || e)); }
  if (G.busy || G.cineLock) { cur = null; prompt(null); return; }
  los.playerPos = p.pos; los.playerYaw = yaw; los.camPos = p.camPos; los.camForward = camFwd;
  let best = null, bs = Infinity;
  for (const it of G.interactables) {
    if (it.done || it.world === 'n') continue;
    try {
      if (it.cond && !it.cond()) continue;
      const s = scoreInteractable(it, los);
      if (s < bs) { bs = s; best = it; }
    } catch (e) { /* a broken condition hides its thing */ }
  }
  cur = best;
  prompt(best);
};

/** the action button */
globalThis.__act = () => { if (cur && !G.busy) run(cur); };
globalThis.__answer = (id, v) => { const r = pending.get(id); if (r) { pending.delete(id); r(v); } };
globalThis.__drain = () => (out.length ? JSON.stringify(out.splice(0)) : '');
/** the backpack: [{id, name, desc, hint, seen}] */
globalThis.__inventory = () => JSON.stringify(G.inv.map((i) => Object.assign({ id: i.id, seen: i.seen }, (({ name, desc, hint }) => ({ name, desc, hint: hint || '' }))(ITEMS[i.id] || { name: i.id, desc: '' }))));
globalThis.__seen = (id) => { for (const i of G.inv) if (i.id === id) i.seen = true; };
globalThis.__serialize = () => JSON.stringify({ chapter: G.chapter, flags: G.flags, inv: G.inv, edits: G.edits, cp: G.cp, memoryBoard: memoryBoard.serialize() });
globalThis.__restore = async (json) => {
  const d = JSON.parse(json);
  G.resetRun();
  G.flags = Object.assign({}, d.flags || {});
  G.chapter = d.chapter || 1;
  G.inv = (d.inv || []).filter((i) => ITEMS[i.id]).map((i) => ({ id: i.id, seen: !!i.seen }));
  memoryBoard.deserialize(d.memoryBoard);
  await G.story.restore();
  G.refreshTools();
};
