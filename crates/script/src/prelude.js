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
    // home: where the native side finds this prop's instance, also after it moved
    this.home = [x, y, z];
    Object.assign(this, { model, x, y, z, yaw, pitch: o.pitch || 0, roll: o.roll || 0, s: o.scale || 1, mask: o.mask ?? 3, vis: o.visible !== false, hl: false });
    if (!this.vis) this._send();
  }
  _send() { emit({ t: 'prop', model: this.model, p: this.home, on: this.vis }); }
  show(v) { this.vis = !!v; this._send(); return this; }
  setModel(m) { if (m !== this.model) { emit({ t: 'prop', model: this.model, p: this.home, on: false }); this.model = m; this._send(); } return this; }
  highlight() { return this; }
  move(x, y, z, yaw) {
    Object.assign(this, { x, y, z, yaw: yaw ?? this.yaw });
    emit({ t: 'move', model: this.model, p: this.home, to: [x, y, z], yaw: this.yaw });
    return this;
  }
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

// G.world.addCollider (duality.js): story boxes the hero cannot walk through while their mask has the dream bit
let nextCollider = 1;
const colliders = [];
const world = quiet({
  addCollider(box) {
    const c = {
      id: nextCollider++,
      x0: Math.min(box.x0, box.x1), y0: Math.min(box.y0, box.y1), z0: Math.min(box.z0, box.z1),
      x1: Math.max(box.x0, box.x1), y1: Math.max(box.y0, box.y1), z1: Math.max(box.z0, box.z1),
      tag: box.tag || '', _mask: box.mask ?? 3,
    };
    const send = () => emit({ t: 'collider', id: c.id, box: [c.x0, c.y0, c.z0, c.x1, c.y1, c.z1], on: (c._mask & 1) !== 0 });
    Object.defineProperty(c, 'mask', { get: () => c._mask, set: (v) => { if (v !== c._mask) { c._mask = v; send(); } } });
    colliders.push([c, send]);
    send();
    return c;
  },
  clearColliders() { for (const [c] of colliders) c.mask = 0; },
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
  // G.duality: the web's Duality (script/game/duality.js), created in boot
  duality: null,
  nightSmooth: 0, peering: false, eyeCool: 0, lowWarned: false, stoneUntil: 0,
  deer: actor(), rabbit: actor(), mike: actor(), shadow: actor(),
  models: new Proxy({}, { get: (t, k) => (typeof k === 'string' && k !== 'then' ? k : undefined) }),
  ui, memoryBoard,
  audio: stub, emit: stub, world, figures: quiet({ list: [], add: () => stub, clear() {} }),
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
  worldAtPlayer() { return worldAtPlayer(); },
  // main.js toNight / toDream: the world turns around the hero's head
  toNight(dur, opts = {}) {
    const p = this.player.pos;
    this.duality.flip(1, [p[0], p[1] + 1, p[2]], opts);
    this.duality.nightTimer = this.duality.baseNight ? 0 : dur;
  },
  toDream(opts = {}) {
    const p = this.player.pos;
    this.duality.flip(0, [p[0], p[1] + 1, p[2]], opts);
    this.duality.nightTimer = 0;
  },
  stopPeer() {
    this.peering = false;
    if (this.duality.target === 1 && !this.duality.baseNight) this.toDream({ speed: 40 });
  },
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
  setEdit(name, on) {
    if (!!this.edits[name] !== !!on) { this.edits[name] = !!on; emit({ t: 'edit', name, on: !!on }); }
    return Promise.resolve();
  },
  checkpoint() { this.cp = { pos: this.player.pos.slice(), yaw: this.player.yaw }; },
  enterMenu() { emit({ t: 'menu' }); },
  resetRun() {
    this.flags = {}; this.inv = []; this.chapter = 1; this.cp = null; this.playtime = 0;
    this.edits = Object.assign({}, EDITS);
    memoryBoard.reset();
    this.waits.length = 0;
    for (const it of this.interactables) it.done = false;
    for (const t of this.triggers) { t.fired = false; t.inside = false; }
    // main.js resetRun, the duality part
    const D = this.duality;
    if (D) { D.base = 0; D.wave.active = false; D.bubbles.length = 0; D.stability = 100; D.nightTimer = 0; D.flicker = 0; D.baseNight = false; }
    this.peering = false; this.lowWarned = false; this.nightSmooth = 0; this.voidMode = false;
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
  G.duality = new mods.Duality();
  mods.setupStory(G);
  log(`story: ${G.interactables.length} interactables, ${G.triggers.length} triggers, ${Object.keys(ITEMS).length} items`);
};

/** a new game: chapter 1 from its start */
// every edit as the story has it now (after a new game or a load the native world may be in any state)
const syncEdits = () => {
  for (const [name, on] of Object.entries(G.edits)) emit({ t: 'edit', name, on: !!on });
  for (const [, send] of colliders) send();
};
globalThis.__newGame = async () => { G.resetRun(); await G.story.restore(); syncEdits(); };

/** every frame, first the camera (position, forward vector), then the hero (feet, facing) */
const camFwd = [0, 0, 1];
globalThis.__cam = (cx, cy, cz, fx, fy, fz) => {
  const c = G.player.camPos;
  c[0] = cx; c[1] = cy; c[2] = cz; camFwd[0] = fx; camFwd[1] = fy; camFwd[2] = fz;
};
// the world at the hero's head (main.js worldAtPlayer): the night share of the world around him
const worldAtPlayer = () => { const p = G.player.pos; return G.duality.worldAt(p[0], p[1] + 1, p[2]); };

// «Вглядеться» (main.js peer / stopPeer / updatePeer): a toggle, held → every 0.6 s
const peer = () => {
  if (G.chapter >= 9) { G.say('Тьма и так повсюду. Вглядываться не во что.', 3); return; }
  if (worldAtPlayer() > 0.5) { G.say('Я и так вижу… слишком много.', 2.5); return; }
  G.toNight(600, { speed: 40 });
  G.peering = true;
  G.stab(-3);
  G.flags.peered = (G.flags.peered || 0) + 1;
  if (G.flags.peered === 1) G.say('Если смотреть долго — сон расступается. Мне страшно, но под ним — правда.', 4.5);
  if (G.story.onPeer) G.story.onPeer();
};
const updatePeer = (dt, eye) => {
  const D = G.duality;
  const avail = !!G.flags.eye && G.chapter <= 8 && !G.cineLock;
  G.eyeCool = Math.max(0, G.eyeCool - dt);
  if (G.peering && (D.target !== 1 || !avail)) G.peering = false; // the world changed by itself
  if (!avail) return;
  if (eye && G.eyeCool <= 0) { G.eyeCool = 0.6; if (G.peering) G.stopPeer(); else peer(); }
  if (G.peering && D.stability < 12) { G.stopPeer(); G.say('Хватит… Глаза режет. Ещё немного — и я там останусь.', 3.5); }
};

// what the native side reads after each tick (Float64Array, see crates/script WorldState)
const ST = new Float64Array(21);
globalThis.__ST = ST;

globalThis.__tick = (dt, px, py, pz, yaw, eye) => {
  G.time += dt; G.playtime += dt;
  const p = G.player;
  p.pos[0] = px; p.pos[1] = py; p.pos[2] = pz; p.yaw = yaw;
  const D = G.duality;
  try {
    // anchors → dream bubbles (main.js: D.bubbles from the story's anchors)
    D.bubbles.length = 0;
    for (const a of G.anchors) if (!a.cond || a.cond()) D.bubbles.push([a.pos[0], a.pos[1], a.pos[2], a.r]);
    D.update(dt, p.pos, false);
    const w = worldAtPlayer() > 0.5 ? 1 : 0;
    G.nightSmooth += (w - G.nightSmooth) * Math.min(1, dt * 7);
    // stability: drained in the nightmare, restored in the dream (main.js)
    if (!G.cineLock) {
      if (w) { if (!(G.time < G.stoneUntil)) G.stab(-D.drain * (G.story.drainMul ? G.story.drainMul() : 1) * dt); }
      else G.stab(D.regen * (G.has('locket') ? 1.6 : 1) * dt);
      if (D.stability < 25 && !G.lowWarned && !D.baseNight) { G.lowWarned = true; D.flicker = 5; G.say('Я теряю себя… Нужно где-то сесть, у огня, у скамейки. Где угодно.', 4); }
      if (D.stability > 45) G.lowWarned = false;
      if (D.stability <= 0) emit({ t: 'collapse' }); // respawn («collapse», main.js): not ported yet
    }
    updatePeer(dt, !!eye);
  } catch (e) { log('world: ' + (e && e.stack || e)); }
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
  // the world state for the native renderer and the collisions
  const W = D.wave, night = worldAtPlayer() > 0.5;
  ST[0] = night ? 1 : 0; ST[1] = G.nightSmooth;
  ST[2] = W.c[0]; ST[3] = W.c[1]; ST[4] = W.c[2]; ST[5] = W.r;
  ST[6] = W.from; ST[7] = W.to; ST[8] = W.active ? 1 : 0; ST[9] = D.base;
  ST[10] = W.oc[0]; ST[11] = W.oc[1]; ST[12] = W.oc[2]; ST[13] = W.active ? W.ro : 0;
  ST[14] = D.stability; ST[15] = D.flicker; ST[16] = G.peering ? 1 : 0; ST[17] = D.baseNight ? 1 : 0;
  // main.js cullMask: which worlds the chunks show (1 dream, 2 nightmare, 3 both: per pixel)
  ST[18] = (!W.active && D.bubbles.length === 0 && D.flicker <= 0 && !G.voidMode) ? (D.base ? 2 : 1) : 3;
  ST[19] = D.bubbles.length;
  // «вглядеться» is offered (main.js updatePeer: the flag, the chapters up to 8, no cinematic)
  ST[20] = (!!G.flags.eye && G.chapter <= 8 && !G.cineLock) ? 1 : 0;
  if (G.busy || G.cineLock) { cur = null; prompt(null); return; }
  los.playerPos = p.pos; los.playerYaw = yaw; los.camPos = p.camPos; los.camForward = camFwd;
  let best = null, bs = Infinity;
  for (const it of G.interactables) {
    if (it.done) continue;
    if (it.world === 'd' && night) continue;
    if (it.world === 'n' && !night) continue;
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
  syncEdits();
  G.refreshTools();
};
