// Rules of the dream and the nightmare shared by the web game (main.js) and the native client (Mezdu-android runs
// this module from the pack): the world at the hero's head, the turn of the world, «вглядеться», the stability.
// G is the game object (main.js Game, or the native client's G with the same members). Edit the rules here: both
// clients follow.

/** the night share of the world at the hero's head (0 dream .. 1 nightmare) */
export function worldAtPlayer(G) {
  const p = G.player.pos;
  return G.duality.worldAt(p[0], p[1] + 1, p[2]);
}

/** the nightmare for `dur` seconds around the hero (then back to the dream, unless the nightmare is the base world) */
export function toNight(G, dur, opts = {}) {
  const p = G.player.pos;
  if (G.duality.flip(1, [p[0], p[1] + 1, p[2]], opts) || opts.force) {
    if (!opts.quiet) { G.audio.sfx('flip'); G.glitch = Math.max(G.glitch, 1); G.vibrate([30, 40, 60]); }
  }
  G.duality.nightTimer = G.duality.baseNight ? 0 : dur;
}

export function toDream(G, opts = {}) {
  const p = G.player.pos;
  if (G.duality.flip(0, [p[0], p[1] + 1, p[2]], opts) && !opts.quiet) { G.audio.sfx('flipBack'); G.glitch = Math.max(G.glitch, 0.4); }
  G.duality.nightTimer = 0;
}

/** the world of the frame: the story's anchors become dream bubbles, the wave runs, the night share eases. Returns
 *  the night share at the hero's head. `paused`: the timers stand (a window is open), `idle`: not in a game */
export function updateWorld(G, dt, paused, idle) {
  const D = G.duality;
  D.bubbles.length = 0;
  for (const a of G.anchors) {
    if (!a.cond || a.cond()) {
      if (!a._b4) a._b4 = new Float32Array(4);
      a._b4[0] = a.pos[0]; a._b4[1] = a.pos[1]; a._b4[2] = a.pos[2]; a._b4[3] = a.r;
      D.bubbles.push(a._b4);
    }
  }
  D.update(paused ? 0 : dt, G.player.pos, paused || idle);
  const w = worldAtPlayer(G);
  G.nightSmooth += (w - G.nightSmooth) * Math.min(1, dt * 7);
  return w;
}

/** the mind: drained in the nightmare, restored in the dream; low → the world flickers, 0 → collapse */
export function updateStability(G, dt, w) {
  if (G.cineLock) return;
  const D = G.duality;
  const night = w > 0.5;
  if (night) { if (!(G.time < (G.stoneUntil || 0))) G.stab(-D.drain * (G.story.drainMul ? G.story.drainMul() : 1) * dt); }
  else G.stab(D.regen * (G.has('locket') ? 1.6 : 1) * dt);
  if (D.stability < 25 && !G.lowWarned && !D.baseNight) { G.lowWarned = true; D.flicker = 5; G.say('Я теряю себя… Нужно где-то сесть, у огня, у скамейки. Где угодно.', 4); }
  if (D.stability > 45) G.lowWarned = false;
  if (D.stability <= 0 && !G.respawning) G.respawn('collapse');
}

/** «Вглядеться»: a toggle (the eye button or R, one press per frame); on = the dream parts, the nightmare shows */
export function updatePeer(G, dt, eye) {
  const avail = eyeAvailable(G);
  G.eyeCool = Math.max(0, G.eyeCool - dt);
  const D = G.duality;
  if (G.peering && (D.target !== 1 || !avail)) G.peering = false; // the world changed by itself
  if (!avail) { G.ui.eye(false); return; }
  if (eye && G.eyeCool <= 0) {
    G.eyeCool = 0.6;
    if (G.peering) stopPeer(G); else peer(G);
  }
  if (G.peering && D.stability < 12) { stopPeer(G); G.say('Хватит… Глаза режет. Ещё немного — и я там останусь.', 3.5); }
  G.ui.eye(true, G.peering);
}

/** «вглядеться» is offered: the story gave the eye, the chapters up to 8, no cinematic */
export function eyeAvailable(G) {
  return !!G.flags.eye && G.chapter <= 8 && !G.cineLock;
}

export function peer(G) {
  if (G.chapter >= 9) { G.say('Тьма и так повсюду. Вглядываться не во что.', 3); return; }
  if (worldAtPlayer(G) > 0.5) { G.say('Я и так вижу… слишком много.', 2.5); return; }
  G.toNight(600, { speed: 40 });
  G.peering = true;
  G.stab(-3);
  G.flags.peered = (G.flags.peered || 0) + 1;
  if (G.flags.peered === 1) G.say('Если смотреть долго — сон расступается. Мне страшно, но под ним — правда.', 4.5);
  if (G.story.onPeer) G.story.onPeer();
}

export function stopPeer(G) {
  G.peering = false;
  if (G.duality.target === 1 && !G.duality.baseNight) G.toDream({ speed: 40 });
}

/** main.js cullMask: the worlds the chunks show (1 dream, 2 nightmare, 3 both: per pixel) */
export function cullMask(G) {
  const D = G.duality;
  return (!D.wave.active && D.bubbles.length === 0 && D.flicker <= 0 && !G.voidMode) ? (D.base ? 2 : 1) : 3;
}
