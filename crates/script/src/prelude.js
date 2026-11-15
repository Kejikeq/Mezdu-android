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
  // duality.js VoxelWorld: voxels of a world (0 dream, 1 nightmare), hazards (deep water...)
  solid: (x, y, z, w) => H.solid(x, y, z, w ? 1 : 0),
  hazardM: (x, y, z, w) => H.hazard(x, y, z, w ? 1 : 0),
});

const EDITS = { ch1Door: false, ch2Door: false, ch3Door: false, ch4Door: false, startCave: false, bridge1: false, door: false, hedge1: false, hedge2: false, grate: false, tunnelWall: false, hearth: false };

const G = quiet({
  chapter: 1, state: 'game', time: 0, playtime: 0, flags: {}, inv: [], edits: Object.assign({}, EDITS), cp: null,
  interactables: [], triggers: [], updaters: [], waits: [], lights: [], anchors: [],
  sceneName: '', voidMode: false, glitch: 0, fadeV: 0, fadeTo: 0, fadeCol: [0, 0, 0], camOverride: null,
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
  // play_rules.js: the headache of leaving the path, the last safe spot
  headache: 0, headSaid: 0, headT: 0, headToward: false, routeDir: null, lastSafe: null, safeT: 0, noHeadache: false,
  // scratch the shared rules keep on G (main.js makes them in its constructor): real members, not the quiet stub
  _routeDirBuf: null, _bestRoute: null, fallN: 0,
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
  // the screen goes dark (1) or clears (0) over `dur` seconds: the native side draws it
  fade(to, dur = 1) { this.fadeV = to; emit({ t: 'fade', to, dur }); return this.wait(dur); },
  vibrate() {},
  // the rules of the two worlds: the web's game/world_rules.js from the pack (WR, set in boot)
  worldAtPlayer() { return WR.worldAtPlayer(this); },
  toNight(dur, opts = {}) { WR.toNight(this, dur, opts); },
  toDream(opts = {}) { WR.toDream(this, opts); },
  peer() { WR.peer(this); },
  stopPeer() { WR.stopPeer(this); },
  // falls, a collapse: play_rules.js (the screen fades, the hero is put back on safe ground)
  respawn(why) { return PR.respawn(this, why); },
  collapseToRoute() { return PR.collapseToRoute(this); },
  respawning: false,
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
  // main.js placeSafe: the native side finds the ground near (x, z) where the whole body fits
  placeSafe(x, y, z, yaw) {
    const hy = y ?? this.groundAt(x, z);
    this.player.pos = [x, hy, z]; if (yaw !== undefined) this.player.yaw = yaw;
    emit({ t: 'teleport', p: [x, hy, z], yaw: this.player.yaw, safe: true });
    return hy;
  },
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
    // main.js resetRun: the headache, a cinematic, the last safe spot
    this.headache = 0; this.headSaid = 0; this.headT = 0; this.respawning = false; this.cineLock = false; this.lastSafe = null; this.eyeCool = 0;
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
// the line of sight to a thing is tested in the hero's world (main.js _solidD / _solidN)
const solidD = (x, y, z) => H.solid(x, y, z, 0), solidN = (x, y, z) => H.solid(x, y, z, 1);
const los = { playerPos: null, playerYaw: 0, camPos: [0, 0, 0], camForward: [0, 0, 1], solidVoxelFn: solidD, vs: 0.125 };

globalThis.__boot = async (mods) => {
  ITEMS = mods.ITEMS;
  scoreInteractable = mods.scoreInteractable;
  G.duality = new mods.Duality();
  WR = mods.WR;
  PR = mods.PR;
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
// the rules of the two worlds (script/game/world_rules.js) and of play (script/game/play_rules.js), given by boot
let WR = null, PR = null;

// what the native side reads after each tick (Float64Array, see crates/script WorldState)
const ST = new Float64Array(23);
globalThis.__ST = ST;

const moveDir = [0, 0];
globalThis.__tick = (dt, px, py, pz, yaw, eye, onGround) => {
  G.time += dt; G.playtime += dt;
  const p = G.player;
  // the hero's move direction on the ground (player.js moveDir), from where he was a frame ago
  const mx = px - p.pos[0], mz = pz - p.pos[2], ml = Math.hypot(mx, mz);
  if (ml > 1e-4 && ml < 2) { moveDir[0] = mx / ml; moveDir[1] = mz / ml; p.moveDir = moveDir; } else p.moveDir = null;
  p.pos[0] = px; p.pos[1] = py; p.pos[2] = pz; p.yaw = yaw; p.onGround = !!onGround;
  const D = G.duality;
  let w = 0;
  // main.js update order, the shared rules from the pack (world_rules.js, play_rules.js): the waits, the world,
  // the way back to the path, falls, the thing to interact with, triggers, the story's updaters, «вглядеться»,
  // the headache, the stability
  try {
    PR.resolveWaits(G);
    w = WR.updateWorld(G, dt, false, false);
    PR.updateHeadToward(G);
    PR.checkFall(G, dt, w);
  } catch (e) { log('world: ' + (e && e.stack || e)); }
  const night = w > 0.5;
  if (G.busy || G.cineLock) { cur = null; prompt(null); } else {
    los.playerPos = p.pos; los.playerYaw = yaw; los.camPos = p.camPos; los.camForward = camFwd; los.solidVoxelFn = night ? solidN : solidD;
    try { cur = PR.chooseInteractable(G, los, w); } catch (e) { cur = null; log('interact: ' + (e && e.stack || e)); }
    prompt(cur);
  }
  try {
    PR.updateTriggers(G);
    for (const f of G.updaters) f(dt);
    WR.updatePeer(G, dt, !!eye);
    PR.updateHeadache(G, dt);
    WR.updateStability(G, dt, w);
  } catch (e) { log('update: ' + (e && e.stack || e)); }
  // the world state for the native renderer and the collisions
  const W = D.wave;
  ST[0] = night ? 1 : 0; ST[1] = G.nightSmooth;
  ST[2] = W.c[0]; ST[3] = W.c[1]; ST[4] = W.c[2]; ST[5] = W.r;
  ST[6] = W.from; ST[7] = W.to; ST[8] = W.active ? 1 : 0; ST[9] = D.base;
  ST[10] = W.oc[0]; ST[11] = W.oc[1]; ST[12] = W.oc[2]; ST[13] = W.active ? W.ro : 0;
  ST[14] = D.stability; ST[15] = D.flicker; ST[16] = G.peering ? 1 : 0; ST[17] = D.baseNight ? 1 : 0;
  // main.js cullMask: which worlds the chunks show (1 dream, 2 nightmare, 3 both: per pixel)
  ST[18] = WR.cullMask(G);
  ST[19] = D.bubbles.length;
  // «вглядеться» is offered (the flag, the chapters up to 8, no cinematic)
  ST[20] = WR.eyeAvailable(G) ? 1 : 0;
  // the headache blurs the frame (main.js S.blur); a cinematic or a collapse holds the hero (player.js locked)
  ST[21] = G.headache; ST[22] = G.cineLock ? 1 : 0;
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
