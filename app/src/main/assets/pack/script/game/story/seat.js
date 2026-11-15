// Smooth walk to a seat along waypoints and sit down, from any approach angle
import { angleLerp } from '../../engine/math.js';

export function setupSeat(ctx) {
  const { G, S, gD } = ctx;
  const smoothWalkAndSit = async (waypoints, finalYaw, seatType) => {
    G.lock(true);
    G.player.seat = seatType;
    S.sitting = seatType;
    for (const pt of waypoints) {
      const sx = G.player.pos[0], sz = G.player.pos[2];
      const tx = pt[0], tz = pt[1];
      const dist = Math.hypot(tx - sx, tz - sz);
      if (dist > 0.04) {
        const walkYaw = Math.atan2(tx - sx, tz - sz);
        const dur = Math.max(0.18, Math.min(1.2, dist / 2.5));
        const steps = Math.max(6, Math.round(dur * 35));
        const dt = dur / steps;
        for (let s = 1; s <= steps; s++) {
          const u = s / steps;
          const t = u * u * (3 - 2 * u);
          const cx = sx + (tx - sx) * t;
          const cz = sz + (tz - sz) * t;
          const cy = gD(cx, cz);
          G.player.pos[0] = cx;
          G.player.pos[1] = cy;
          G.player.pos[2] = cz;
          G.player.visY = cy;
          G.player.yaw = angleLerp(G.player.yaw, walkYaw, 0.35);
          G.player.pose = 'walk';
          G.player.speed = 2.2;
          G.player.phase += dt * 6.5;
          await G.wait(dt);
        }
      }
    }
    if (finalYaw !== undefined) {
      const startYaw = G.player.yaw;
      const turnSteps = 8;
      const turnDt = 0.22 / turnSteps;
      for (let s = 1; s <= turnSteps; s++) {
        const u = s / turnSteps;
        const t = u * u * (3 - 2 * u);
        G.player.yaw = angleLerp(startYaw, finalYaw, t);
        G.player.camYaw = angleLerp(G.player.camYaw, finalYaw + 0.5, 0.15);
        await G.wait(turnDt);
      }
      G.player.yaw = finalYaw;
    }
    const groundY = gD(G.player.pos[0], G.player.pos[2]);
    G.player.pos[1] = groundY;
    G.player.visY = groundY;
    G.player.vel[1] = 0;
    G.player.speed = 0;
    G.player.pose = 'sit';
    G.player.seat = seatType;
    S.sitting = seatType;
    G.lock(false);
  };
  return { smoothWalkAndSit };
}
