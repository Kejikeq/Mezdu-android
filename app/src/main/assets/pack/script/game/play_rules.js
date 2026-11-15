// Rules of play shared by the web game (main.js) and the native client (Mezdu-android runs this module from the
// pack): the story's waits and triggers, the choice of the thing to interact with, the hero's safety (falls, the
// last safe spot, respawn), the headache of leaving the story path and the collapse back to it.
// G is the game object (main.js Game, or the native client's G with the same members). Edit the rules here: both
// clients follow.
import { VS, WX, WZ, P, CLEARINGS, ALL_ROUTE_POLYS, nearestOnPoly } from '../world/layout.js';
import { smoothstep } from '../engine/noise.js';
import { scoreInteractable } from './interaction_los.js';

/** the story's `G.wait` promises whose time has come */
export function resolveWaits(G) {
  if (!G.waits.length) return;
  let writeIdx = 0;
  for (let i = 0; i < G.waits.length; i++) {
    const w = G.waits[i];
    if (w.t <= G.time) w.res();
    else G.waits[writeIdx++] = w;
  }
  G.waits.length = writeIdx;
}

/** the story's triggers: run once when the hero walks in (or every time for `once: false`) */
export function updateTriggers(G) {
  const p = G.player.pos;
  for (const t of G.triggers) {
    if (t.fired && t.once) continue;
    if (t.cond && !t.cond()) continue;
    const inside = t.test ? t.test(p) : Math.hypot(p[0] - t.pos[0], p[2] - t.pos[2]) < t.r;
    if (inside && !t.inside) { t.inside = true; if (!(t.once && t.fired)) { t.fired = true; t.run(); } }
    else if (!inside) t.inside = false;
  }
}

/** the thing the action button works on: in the hero's world, its condition met, the best score (close, looked
 *  at, in sight: interaction_los.js). `ctx` as scoreInteractable takes it, `w` the night share at the hero */
export function chooseInteractable(G, ctx, w) {
  let best = null, bs = Infinity;
  for (let i = 0; i < G.interactables.length; i++) {
    const it = G.interactables[i];
    if (it.done) continue;
    if (it.world === 'd' && w > 0.5) continue;
    if (it.world === 'n' && w < 0.5) continue;
    if (it.cond && !it.cond()) continue;
    const s = scoreInteractable(it, ctx);
    if (s < bs) { bs = s; best = it; }
  }
  if (best && best.cond && !best.cond()) best = null;
  return best;
}

/** walking back toward the story path eases the headache (the hero's move direction against the way back) */
export function updateHeadToward(G) {
  const pl = G.player, h = G.headache;
  G.headToward = false;
  if (h > 0.02 && G.routeDir && !G.cineLock) {
    const md = pl.moveDir;
    const dot = md ? md[0] * G.routeDir[0] + md[1] * G.routeDir[1] : 0;
    G.headToward = dot > 0.25;
  }
}

/** after the hero moved: fallen into water / off the world → back to safe ground; else remember where it is safe */
export function checkFall(G, dt, w) {
  if (G.respawning || G.cineLock) return;
  const p = G.player.pos, wi = w > 0.5 ? 1 : 0;
  if (p[1] < 2.5 || G.world.hazardM(p[0], p[1] + 0.25, p[2], wi)) respawn(G, 'fall');
  else trackSafe(G, dt);
}

/** last position with ground under the feet in BOTH worlds (used to pull the hero back softly) */
export function trackSafe(G, dt) {
  const pl = G.player, p = pl.pos;
  G.safeT = (G.safeT || 0) + dt;
  if (!pl.onGround || G.safeT < 0.4) return;
  G.safeT = 0;
  const vx = Math.floor(p[0] / VS), vz = Math.floor(p[2] / VS), vy = Math.round(p[1] / VS) - 1;
  if (G.world.solid(vx, vy, vz, 0) && G.world.solid(vx, vy, vz, 1)) G.lastSafe = [p[0], p[1], p[2], pl.yaw];
}

export async function respawn(G, reason) {
  if (G.respawning) return;
  G.respawning = true;
  G.lock(true);
  if (reason === 'fall' && G.lastSafe && Math.hypot(G.lastSafe[0] - G.player.pos[0], G.lastSafe[2] - G.player.pos[2]) < 30) {
    // soft: a gasp, a blink, back on firm ground
    G.audio.sfx('splash'); G.vibrate(120); G.glitch = 0.8;
    await G.fade(1, 0.35);
    const s = G.lastSafe;
    G.placeSafe(s[0], s[1], s[2], s[3]);
    G.player.pose = 'idle';
    G.stab(-6);
    await G.wait(0.25);
    await G.fade(0, 0.7);
    G.lock(false);
    G.respawning = false;
    G.say(['…Холодно. Еле выбрался. Руки трясутся.', 'Что-то тянуло меня вниз. Я не хочу знать, что.'][(G.fallN = (G.fallN || 0) + 1) % 2], 3.8);
    if (G.story.onRespawn) G.story.onRespawn(reason);
    return;
  }
  G.audio.sfx(reason === 'collapse' ? 'scream' : 'splash');
  G.glitch = 1.5; G.vibrate(200);
  await G.fade(1, 0.6);
  const c = G.cp || { pos: [P.start[0] * VS, 8, P.start[1] * VS], yaw: Math.PI };
  G.placeSafe(c.pos[0], c.pos[1], c.pos[2], c.yaw);
  G.player.pose = 'idle';
  if (!G.duality.baseNight) { G.duality.base = 0; G.duality.wave.active = false; G.duality.nightTimer = 0; }
  G.duality.flicker = 0;
  G.stab(reason === 'collapse' ? 0 : -18);
  if (reason === 'collapse') { G.duality.stability = 45; G.flags.collapses = (G.flags.collapses || 0) + 1; }
  await G.wait(0.4);
  await G.fade(0, 1.2);
  G.lock(false);
  G.respawning = false;
  if (reason === 'collapse') G.say('…Я ещё здесь. Руки ледяные. Больше так нельзя.', 4);
  if (G.story.onRespawn) G.story.onRespawn(reason);
}

/** distance (m) to the story route; also remembers the direction back to it (G.routeDir) */
export function routeDistance(G) {
  const p = G.player.pos, vx = p[0] / VS, vz = p[2] / VS;
  // The entire settlement, yards, gardens, pasture, highway, and fields are open exploration zones
  if (vx >= 96 && vx <= 860 && vz >= 1550 && vz <= 2460) {
    G.routeDir = null;
    return 0;
  }
  let d = 1e9, tx = vx, tz = vz;
  for (let i = 0; i < ALL_ROUTE_POLYS.length; i++) {
    const r = ALL_ROUTE_POLYS[i];
    if (r.ch > Math.max(G.chapter, 1)) continue;
    const n = nearestOnPoly(r.pts, vx, vz);
    if (n[0] - r.w < d) { d = n[0] - r.w; tx = n[1]; tz = n[2]; }
  }
  for (let i = 0; i < CLEARINGS.length; i++) {
    const c = CLEARINGS[i];
    const dc = Math.hypot(vx - c.x, vz - c.z);
    if (dc - c.r < d) { d = dc - c.r; tx = c.x; tz = c.z; }
  }
  const l = Math.hypot(tx - vx, tz - vz);
  if (l > 0.01) {
    const b = G._routeDirBuf || (G._routeDirBuf = new Float32Array(2));
    b[0] = (tx - vx) / l;
    b[1] = (tz - vz) / l;
    G.routeDir = b;
  } else G.routeDir = null;
  return Math.max(0, d) * VS;
}

/** leaving the story path: headache, the world swims and blurs, then you collapse back to the road */
export function updateHeadache(G, dt) {
  if (G.cineLock || G.respawning || G.noHeadache) { G.headache = Math.max(0, G.headache - dt); return; }
  const d = routeDistance(G);
  // the border of the world is never reached: the headache grows long before it
  const p = G.player.pos, de = Math.min(p[0], p[2], WX * VS - p[0], WZ * VS - p[2]);
  const target = Math.max(smoothstep(11, 27, d), smoothstep(30, 13, de));
  G.headache += (target - G.headache) * Math.min(1, dt * (target > G.headache ? 0.9 : 2.5));
  const h = G.headache;
  if (h > 0.2 && G.headSaid < 1) { G.headSaid = 1; G.say('Виски сдавило. Будто кто-то шепчет: «Не туда».', 4); }
  if (h > 0.55 && G.headSaid < 2) { G.headSaid = 2; G.say('Мне плохо… Надо вернуться. Пожалуйста, назад к тропе.', 4); G.vibrate(80); }
  if (h < 0.08) G.headSaid = 0;
  if (h > 0.9 && !G.headToward) { G.headT += dt; if (G.headT > 1.2) { G.headT = 0; collapseToRoute(G); } } else G.headT = 0;
}

export async function collapseToRoute(G) {
  if (G.respawning) return;
  G.respawning = true;
  G.lock(true);
  G.say('…Не могу…', 2);
  G.player.pose = 'kneel'; G.player.lockPose = true;
  G.audio.sfx('heart'); G.vibrate(300);
  await G.wait(1.1);
  G.player.pose = 'lie';
  G.audio.sfx('heart');
  await G.wait(0.7);
  await G.fade(1, 0.9);
  const p = G.player.pos, vx = p[0] / VS, vz = p[2] / VS;
  const best = G._bestRoute || (G._bestRoute = new Float32Array(5));
  best[0] = 1e9;
  for (let i = 0; i < ALL_ROUTE_POLYS.length; i++) {
    const r = ALL_ROUTE_POLYS[i];
    if (r.ch > Math.max(G.chapter, 1)) continue;
    const n = nearestOnPoly(r.pts, vx, vz);
    if (n[0] < best[0]) best.set(n);
  }
  const x = best[1] * VS, z = best[2] * VS, w = G.worldAtPlayer() > 0.5 ? 1 : 0;
  G.player.lockPose = false; G.player.pose = 'idle';
  G.placeSafe(x, G.groundAt(x, z, w), z, Math.atan2(best[3], best[4]));
  G.headache = 0; G.headSaid = 0;
  G.stab(-8);
  await G.wait(0.5);
  await G.fade(0, 1.4);
  G.lock(false);
  G.respawning = false;
  G.say('…Я снова у тропы. Голова гудит. Лес не отпускает в сторону.', 4.5);
}
