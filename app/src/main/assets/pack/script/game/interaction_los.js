// ============================================================================
// Pure 3D Voxel Line-of-Sight (LOS) & Interaction Scoring
// Ensures interactables and object glints are only visible/usable at close
// visual contact and never through solid walls, floors, or ceilings.
// ============================================================================

/**
 * Raymarches through the voxel world from eye `(ex, ey, ez)` to target `(tx, ty, tz)`.
 * Returns true if there is an unobstructed line of sight, or false if solid voxel
 * geometry blocks the view between the viewer and the object.
 *
 * @param {(vx: number, vy: number, vz: number) => boolean} solidVoxelFn - returns true if voxel (vx, vy, vz) is opaque/solid
 * @param {number} ex - viewer eye X in meters
 * @param {number} ey - viewer eye Y in meters
 * @param {number} ez - viewer eye Z in meters
 * @param {number} tx - target X in meters
 * @param {number} ty - target Y in meters
 * @param {number} tz - target Z in meters
 * @param {number} [vs=0.125] - voxel size in meters
 * @param {number} [endMargin=0.34] - margin near target so surface-mounted props/doors don't self-occlude
 * @returns {boolean}
 */
export function hasLineOfSight(solidVoxelFn, ex, ey, ez, tx, ty, tz, vs = 0.125, endMargin = 0.34) {
  const dx = tx - ex;
  const dy = ty - ey;
  const dz = tz - ez;
  const dist = Math.hypot(dx, dy, dz);
  if (dist <= endMargin + 0.12) return true;

  const invDist = 1 / dist;
  const ux = dx * invDist;
  const uy = dy * invDist;
  const uz = dz * invDist;

  const step = Math.max(0.04, vs * 0.45);
  const startT = 0.16;
  const stopT = Math.max(startT, dist - endMargin);

  for (let t = startT; t < stopT; t += step) {
    const px = ex + ux * t;
    const py = ey + uy * t;
    const pz = ez + uz * t;
    const vx = Math.floor(px / vs);
    const vy = Math.floor(py / vs);
    const vz = Math.floor(pz / vs);
    if (solidVoxelFn(vx, vy, vz)) {
      return false;
    }
  }
  return true;
}

/**
 * Evaluates whether an interactable `it` can be interacted with right now and
 * returns a distance-and-gaze score (lower is better), or `Infinity` if out of
 * range, on another floor, behind the camera/player, or occluded by a wall.
 *
 * @param {object} it - interactable item `{ pos: [x,y,z], r?: number,doorRef?: object, when?: (v)=>boolean }`
 * @param {object} ctx
 * @param {number[]} ctx.playerPos - `[x, y, z]` player feet in meters
 * @param {number} ctx.playerYaw - player facing yaw in radians
 * @param {number[]} ctx.camPos - `[x, y, z]` camera position in meters
 * @param {number[]} ctx.camForward - `[fx, fy, fz]` unit camera forward vector
 * @param {(vx: number, vy: number, vz: number) => boolean} ctx.solidVoxelFn
 * @param {number} [ctx.vs=0.125]
 * @returns {number} score (`Infinity` if not interactable)
 */
export function scoreInteractable(it, ctx) {
  if (!it || !it.pos) return Infinity;
  const { playerPos, playerYaw, camPos, camForward, solidVoxelFn, vs = 0.125 } = ctx;

  const eyeX = playerPos[0];
  const eyeY = playerPos[1] + 1.52;
  const eyeZ = playerPos[2];

  const tx = it.pos[0];
  const ty = it.pos[1];
  const tz = it.pos[2];

  // Vertical proximity check: never interact across floors/ceilings
  const dyFeet = ty - (playerPos[1] + 0.95);
  if (Math.abs(dyFeet) > 1.45) return Infinity;

  // Strict close-contact interaction radius: cap oversized radii to realistic reach
  const rawR = it.r || 1.75;
  const maxR = it.doorRef ? Math.min(rawR, 2.05) : Math.min(rawR, 1.85);

  const dx = tx - playerPos[0];
  const dz = tz - playerPos[2];
  const d3 = Math.hypot(dx, dyFeet * 0.85, dz);
  if (d3 > maxR) return Infinity;

  // Visual gaze alignment: object must be in front of camera view (or very close in front of player)
  const horizDist = Math.hypot(dx, dz) || 0.001;
  const toObjX = dx / horizDist;
  const toObjZ = dz / horizDist;

  const pFwdX = Math.sin(playerYaw);
  const pFwdZ = Math.cos(playerYaw);
  const playerDot = toObjX * pFwdX + toObjZ * pFwdZ;

  let camDot = playerDot;
  if (camPos && camForward) {
    const cdx = tx - camPos[0];
    const cdy = ty - camPos[1];
    const cdz = tz - camPos[2];
    const cLen = Math.hypot(cdx, cdy, cdz) || 0.001;
    camDot = (cdx * camForward[0] + cdy * camForward[1] + cdz * camForward[2]) / cLen;
  }

  // Must be within visual cone unless standing practically touching the object (< 0.75m)
  if (d3 > 0.75 && camDot < 0.22 && playerDot < 0.15) {
    return Infinity;
  }

  // Direct visual contact check: raycast from player eye to target (and slightly raised target for floor props)
  const endMargin = it.doorRef ? 0.48 : 0.34;
  const losEye =
    hasLineOfSight(solidVoxelFn, eyeX, eyeY, eyeZ, tx, ty + 0.12, tz, vs, endMargin) ||
    hasLineOfSight(solidVoxelFn, eyeX, eyeY - 0.35, eyeZ, tx, ty + 0.22, tz, vs, endMargin);

  if (!losEye) return Infinity;

  // Prefer objects that are both close and directly aligned with the player's gaze
  const gazeFactor = 1.15 - Math.max(-0.5, Math.min(1, Math.max(camDot, playerDot))) * 0.45;
  return d3 * gazeFactor;
}
