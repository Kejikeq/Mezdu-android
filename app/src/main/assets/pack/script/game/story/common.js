// Shared helpers of the story scenes: metres from world voxels and the area converters (story scenes are
// authored in local coordinates of an area, in metres, and placed on the big map).
import { VS, AREA } from '../../world/layout.js';

export const m = (v) => v * VS;
export const AR = (a) => { const dx = AREA[a][0] * VS, dz = AREA[a][1] * VS; const f = (x, z) => [x + dx, z + dz]; f.x = (x) => x + dx; f.z = (z) => z + dz; return f; };
export const CR = AR('crossing'), MD = AR('meadow'), HO = AR('house'), TK = AR('thicket'), UPA = AR('upstream'), NO = AR('north');
export const dist2 = (a, x, z) => Math.hypot(a[0] - x, a[2] - z);
