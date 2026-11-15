// Figures and NPCs spawned per chapter
import { CHAPTERS_DATA } from '../chapters_data.js';
import { TK } from './common.js';

export function setupFigures(ctx) {
  const { G, S, gD, gN, pl } = ctx;
  S.setupFigures = () => {
    G.figures.clear();
    const ch = G.chapter || 1;
    const cd = CHAPTERS_DATA[ch];
    if (cd && cd.npcs) {
      for (const npc of cd.npcs) {
        const [x, z] = npc.pos;
        const isNightNpc = npc.world === 'n';
        const y = npc.y !== undefined ? npc.y : (isNightNpc ? gN(x, z) : gD(x, z));
        const mask = npc.world === 'n' ? 2 : (npc.world === 'd' ? 1 : 3);
        const modelIdx = G.models[npc.model || (isNightNpc ? 'figure_n' : 'figure')] ?? G.models.figure;
        G.figures.add({
          model: modelIdx,
          pos: [x, y, z],
          yaw: npc.yaw || 0,
          mask,
          face: true,
        });
      }
    }
    // Chapter 7 thicket ambient figures + reaching figure with student card
    if (ch === 7) {
      for (const [lx, lz, yaw] of [[33, 37.2, 2.6], [43.5, 37, -2.4], [31, 46, 0.9], [44.5, 46.5, -0.6]]) {
        const [x, z] = TK(lx, lz);
        G.figures.add({ model: G.models.figure_n, pos: [x, gN(x, z), z], yaw, mask: 2, far: true });
      }
      const [rx, rz] = TK(36.6, 41.4);
      if (!G.has('photo_3')) {
        S.reachFig = G.figures.add({ model: G.models.figure_reach, pos: [rx, gN(rx, rz), rz], yaw: Math.PI / 2, mask: 3 });
      }
    }
  };

  G.onUpdate(() => {
    const p = pl();
    for (const f of G.figures.list) {
      const d = Math.hypot(p[0] - f.pos[0], p[2] - f.pos[2]);
      if (f.far) f.visible = d > 9;
      if (f.face && d < 12) f.yaw = Math.atan2(p[0] - f.pos[0], p[2] - f.pos[2]);
    }
  });
}
