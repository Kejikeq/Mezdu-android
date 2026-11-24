// Terrain voxel materials. A voxel stores two material ids (dream | night<<8).
export const F_SOLID = 1, F_OPAQUE = 2, F_LEAF = 4, F_WATER = 8, F_EMIT = 16, F_GLOSS = 32, F_GLYPH = 64, F_HAZARD = 128;
const S = F_SOLID | F_OPAQUE;

const G = F_SOLID | F_GLOSS;

export const MATS = [];
export const M = {};
// surface patterns: every block face is drawn as a 12x12 grid of texel-voxels (4.2 cm, the
// same scale as the characters) with a material-specific procedural pattern in the shader.
export const PAT = { PLAIN: 0, GRASS: 1, DIRT: 2, STONE: 3, BARK: 4, BIRCH: 5, LEAF: 6, PLANK: 7, PLASTER: 8, ROOF: 9, BRICK: 10, GRAIN: 11, PATH: 12,
  MOSAIC: 13, MOSS: 14, CLIFF: 15, PINE: 16, DEADGRASS: 17, CHAR: 18, RUST: 19, BRAMBLE: 20, WINDOW: 21, DOOR: 22, RUG: 23, BEAM: 24, HOLLOW: 25,
  ASPHALT: 26, CONCRETE: 27, PAINT: 28, SLATE: 29, TILE: 30, ZINC: 31, RAIL: 32, PARQUET: 33, GLASS: 34, LACE: 35,
  FRAMEV: 36, FRAMEH: 37, WALLPAPER: 38 };
const PATS = {
  GRASS: 'GRASS', GRASS2: 'GRASS', DIRT: 'DIRT', PATH: 'PATH', STONE: 'STONE', STONE_DARK: 'STONE', MOSS: 'MOSS', SAND: 'GRAIN', BARK: 'BARK', BIRCH: 'BIRCH',
  LEAF: 'LEAF', LEAF2: 'LEAF', BLOSSOM: 'LEAF', BLOSSOM2: 'LEAF', WILLOW: 'PINE', HOLLOW: 'HOLLOW', PINE: 'PINE', PLANK: 'PLANK', BEAM: 'BEAM', ROOF: 'ROOF', PLASTER: 'PLASTER', WINDOW: 'WINDOW', BRICK: 'BRICK',
  STONE_RED: 'STONE', STONE_BLUE: 'STONE', STONE_YELLOW: 'STONE', STONE_GREEN: 'STONE', RUG: 'RUG', HEARTH: 'BRICK', MOSAIC_A: 'MOSAIC', MOSAIC_B: 'MOSAIC',
  MOSAIC_C: 'MOSAIC', MOSAIC_D: 'MOSAIC', MOSAIC_E: 'MOSAIC', BRAMBLE: 'BRAMBLE', FLOOR: 'PLANK', CLIFF: 'CLIFF', GRAVEL: 'GRAIN', DOOR: 'DOOR', IRON: 'RUST',
  DEAD_GRASS: 'DEADGRASS', DEAD_DIRT: 'DIRT', NSTONE: 'STONE', NBARK: 'BARK', DEAD_LEAF: 'LEAF', CHAR: 'CHAR', RUIN: 'STONE', ASH: 'GRAIN', THORN: 'BRAMBLE',
  BURNT: 'CHAR', RUST: 'RUST', SCRATCH: 'STONE', NPATH: 'PATH', NWALL: 'STONE', NCLIFF: 'CLIFF', NPLANK: 'PLANK', NROOF: 'ROOF', NFLOOR: 'PLANK', NDOOR: 'DOOR', GIRDER: 'RUST',
  ASPHALT: 'ASPHALT', BALLAST: 'GRAIN', CLAY: 'CLIFF', LOAM: 'CLIFF', TILLED: 'DIRT', STUBBLE: 'DEADGRASS', MUD: 'DIRT', ROADMARK: 'ASPHALT',
  CONCRETE: 'CONCRETE', PAINT_GREEN: 'PAINT', PAINT_BLUE: 'PAINT', PAINT_OCHRE: 'PAINT', BRICK_SILICATE: 'BRICK', PLASTER_YELLOW: 'PLASTER', SLATE: 'SLATE',
  TILE: 'TILE', ZINC: 'ZINC', SLEEPER: 'BEAM', RAIL: 'RAIL', PARQUET: 'PARQUET', PAINT_METAL: 'ZINC', GLASS: 'GLASS', TULLE: 'LACE', FRAME_V: 'FRAMEV', FRAME_H: 'FRAMEH', TRIM_LIME: 'PLASTER',
  WP_STRIPES: 'WALLPAPER', WP_FLORAL: 'WALLPAPER', WP_BLUE: 'WALLPAPER', WP_OCHRE: 'WALLPAPER', WP_KITCHEN: 'WALLPAPER', WP_GREEN: 'WALLPAPER',
  TILE_BATH: 'TILE', GARAGE_FLOOR: 'CONCRETE', N_WP: 'WALLPAPER', N_TILE: 'TILE', N_GLASS: 'GLASS',
};
// PBR response (metallic-roughness): [roughness, metallic, porosity]. Porosity = how much the surface darkens
// when wet (rain) and how readily it holds a water film. By pattern, then overrides by material name.
const PBR_PAT = {
  PLAIN: [0.8, 0, 0.3], GRASS: [0.92, 0, 0.5], DIRT: [0.95, 0, 0.9], STONE: [0.8, 0, 0.35], BARK: [0.9, 0, 0.5], BIRCH: [0.7, 0, 0.3], LEAF: [0.55, 0, 0.1],
  PLANK: [0.74, 0, 0.6], PLASTER: [0.9, 0, 0.6], ROOF: [0.7, 0, 0.35], BRICK: [0.86, 0, 0.6], GRAIN: [0.92, 0, 0.75], PATH: [0.94, 0, 0.85], MOSAIC: [0.22, 0, 0.05],
  MOSS: [0.96, 0, 0.8], CLIFF: [0.84, 0, 0.45], PINE: [0.6, 0, 0.1], DEADGRASS: [0.95, 0, 0.5], CHAR: [0.92, 0, 0.4], RUST: [0.78, 0.4, 0.4], BRAMBLE: [0.65, 0, 0.1],
  WINDOW: [0.04, 0, 0], DOOR: [0.5, 0, 0.3], RUG: [1.0, 0, 0.9], BEAM: [0.8, 0, 0.5], HOLLOW: [0.92, 0, 0.5],
  ASPHALT: [0.84, 0, 0.3], CONCRETE: [0.88, 0, 0.5], PAINT: [0.5, 0, 0.3], SLATE: [0.8, 0, 0.35], TILE: [0.12, 0, 0.02], ZINC: [0.38, 1, 0.02], RAIL: [0.3, 1, 0.02],
  PARQUET: [0.22, 0, 0.1], GLASS: [0.06, 0, 0], LACE: [0.95, 0, 0.3], FRAMEV: [0.42, 0, 0.15], FRAMEH: [0.42, 0, 0.15],
  WALLPAPER: [0.78, 0, 0.42],
};
const PBR = {
  WATER: [0.05, 0, 0], BLACK_WATER: [0.04, 0, 0], IRON: [0.5, 1, 0.05], GIRDER: [0.7, 0.7, 0.3], RUST: [0.85, 0.3, 0.45], SAND: [0.92, 0, 0.85], MUD: [0.5, 0, 1],
  ROADMARK: [0.6, 0, 0.2], BALLAST: [0.9, 0, 0.3], FLOOR: [0.24, 0, 0.28], NFLOOR: [0.72, 0, 0.5], PLASTER: [0.92, 0, 0.6], HEARTH: [0.9, 0, 0.4], LANTERN: [0.3, 0, 0],
  FIRE: [1, 0, 0], LIGHTWALL: [1, 0, 0], STONE_RED: [0.45, 0, 0.1], STONE_BLUE: [0.45, 0, 0.1], STONE_YELLOW: [0.45, 0, 0.1], STONE_GREEN: [0.45, 0, 0.1],
  SLEEPER: [0.85, 0, 0.3], PAINT_METAL: [0.45, 0, 0.02], TILLED: [0.97, 0, 1], CLAY: [0.8, 0, 0.7],
  TILE_BATH: [0.10, 0, 0.02], GARAGE_FLOOR: [0.85, 0, 0.35], N_WP: [0.92, 0, 0.65], N_TILE: [0.42, 0, 0.12], N_GLASS: [0.12, 0, 0.05],
};
function def(id, name, color, flags, vary = 0.08, emit = 0) {
  const [rough, metal, por] = PBR[name] || PBR_PAT[PATS[name] || 'PLAIN'];
  MATS[id] = { id, name, color, flags, vary, emit, pat: PAT[PATS[name] || 'PLAIN'], rough, metal, por };
  M[name] = id;
}
def(0, 'AIR', 0x000000, 0, 0);
// ---- dream
def(1, 'GRASS', 0x6e7a34, S, 0.10);
def(2, 'GRASS2', 0x8a8c40, S, 0.10);
def(3, 'DIRT', 0x5e5040, S, 0.10);
def(4, 'PATH', 0x8c867a, S, 0.09);
def(5, 'STONE', 0x8a8a82, S, 0.10);
def(6, 'STONE_DARK', 0x66665f, S, 0.09);
def(7, 'MOSS', 0x6a7a2c, S, 0.12);
def(8, 'SAND', 0xa8a08a, S, 0.06);
def(9, 'BARK', 0x5c4c3c, S, 0.12);
def(10, 'BIRCH', 0xd2ccbe, S, 0.10);
def(11, 'LEAF', 0x5e7030, S | F_LEAF, 0.16);
def(12, 'LEAF2', 0x7e8a3a, S | F_LEAF, 0.16);
def(13, 'BLOSSOM', 0xf2b6ca, S | F_LEAF, 0.14);
def(14, 'PINE', 0x3e5038, S | F_LEAF, 0.14);
def(15, 'WATER', 0x6e8a96, F_WATER | F_HAZARD, 0.0);
def(16, 'PLANK', 0x8a7258, S, 0.08);
def(17, 'BEAM', 0x54402e, S, 0.06);
def(18, 'ROOF', 0x7a5a48, S, 0.10);
def(19, 'PLASTER', 0xd4cdbc, S, 0.04);
def(20, 'WINDOW', 0x90b4c0, G, 0.02); // window glass: semi-transparent glossy pane (water/glass pass)
def(21, 'BRICK', 0x8a4c3a, S, 0.10);            // red ceramic brick
def(22, 'STONE_RED', 0xc8463c, S, 0.06);
def(23, 'STONE_BLUE', 0x3f6fc4, S, 0.06);
def(24, 'STONE_YELLOW', 0xe0b83a, S, 0.06);
def(25, 'STONE_GREEN', 0x4fa35a, S, 0.06);
def(26, 'LANTERN', 0xffb446, S | F_EMIT, 0.0, 3.8);
def(27, 'RUG', 0x8a3f3f, S, 0.06);
def(28, 'HEARTH', 0x5a5552, S, 0.08);
def(29, 'FIRE', 0xff9a40, S | F_EMIT, 0.2, 3.5);
def(30, 'MOSAIC_A', 0x4e8fbf, S, 0.05);
def(31, 'MOSAIC_B', 0xe8c85a, S, 0.05);
def(32, 'MOSAIC_C', 0x5aa46a, S, 0.05);
def(33, 'MOSAIC_D', 0xd77a6a, S, 0.05);
def(34, 'MOSAIC_E', 0xf2eee0, S, 0.04);
def(35, 'BRAMBLE', 0x3c4d2a, S | F_LEAF, 0.18);
def(36, 'FLOOR', 0x5d3215, S, 0.06);          // dark varnished chestnut floorboards catching warm tungsten specular gleam
def(37, 'CLIFF', 0x7d7b73, S, 0.10);
def(38, 'GRAVEL', 0x9a9284, S, 0.12);
def(39, 'DOOR', 0x8b5e38, S, 0.05);
def(40, 'LIGHTWALL', 0xfff6e8, S | F_EMIT, 0.0, 9.0);
def(41, 'IRON', 0x3a3a3e, S, 0.05);
// ---- landscape of the settlement (roads, railway bed, fields, exposed strata)
def(42, 'ASPHALT', 0x4b4a4a, S, 0.05);   // old sun-bleached asphalt
def(43, 'ROADMARK', 0xd6d1c0, S, 0.04);  // worn centre-line paint
def(44, 'BALLAST', 0x8b857c, S, 0.16);   // crushed granite of the railway bed
def(45, 'CLAY', 0x9b6044, S, 0.08);      // red-brown clay layers
def(46, 'LOAM', 0xb6975f, S, 0.08);      // ochre sandy loam layers
def(47, 'TILLED', 0x3b302a, S, 0.10);    // dug garden soil (chernozem)
def(48, 'STUBBLE', 0xb7a25c, S, 0.12);   // harvested grain field
def(49, 'MUD', 0x4f4337, S, 0.07);       // wet wheel ruts
// ---- built settlement (walls, roofs, floors, railway): docs/tasks/render.md
def(50, 'CONCRETE', 0x9a988f, S, 0.06);        // precast slabs, kerbs, platform
def(51, 'PAINT_GREEN', 0x55735a, S, 0.07);     // painted boards, peeling to grey wood
def(52, 'PAINT_BLUE', 0x6f8ea3, S, 0.07);
def(53, 'PAINT_OCHRE', 0xb58a3c, S, 0.07);
def(54, 'BRICK_SILICATE', 0xcfcabb, S, 0.06);  // white sand-lime brick
def(55, 'PLASTER_YELLOW', 0xd9bd72, S, 0.05);
def(56, 'SLATE', 0x8c8f8a, S, 0.07);           // corrugated asbestos-cement roofing
def(57, 'TILE', 0xd8dcd2, S, 0.04);            // glazed wall tiles
def(58, 'ZINC', 0xa9adae, S, 0.05);            // galvanised sheet
def(59, 'SLEEPER', 0x3d3129, S, 0.10);         // creosoted railway sleepers
// ---- nightmare
def(60, 'DEAD_GRASS', 0x67664e, S, 0.10);
def(61, 'DEAD_DIRT', 0x4a3e33, S, 0.10);
def(62, 'NSTONE', 0x55534f, S, 0.10);
def(63, 'NBARK', 0x2c2623, S, 0.10);
def(64, 'DEAD_LEAF', 0x5b4a33, S | F_LEAF, 0.18);
def(65, 'CHAR', 0x231d1a, S, 0.10);
def(66, 'RUIN', 0x4d4744, S, 0.10);
def(67, 'RED_GLOW', 0xff3a26, S | F_EMIT, 0.08, 2.2);
def(68, 'ASH', 0x5c5856, S, 0.08);
def(69, 'THORN', 0x2a2e1e, S | F_LEAF, 0.14);
def(70, 'BLACK_WATER', 0x050608, F_OPAQUE | F_GLOSS | F_HAZARD, 0.0);
def(71, 'BURNT', 0x4a423a, S, 0.10);
def(72, 'RUST', 0x7a3e22, S, 0.14);
def(73, 'SCRATCH', 0x8a7f78, S, 0.06);
def(74, 'NPATH', 0x5e554a, S, 0.08);
def(75, 'NWALL', 0x3a3532, S, 0.08);
def(76, 'BLOOD_LIGHT', 0xb01810, S | F_EMIT, 0.1, 1.6);
def(77, 'NCLIFF', 0x4a4844, S, 0.10);
def(78, 'GLYPH', 0x2a2420, S | F_GLYPH, 0.04);
def(79, 'NPLANK', 0x4a3a2c, S, 0.10);
def(80, 'NROOF', 0x3a2a24, S, 0.10);
def(81, 'NFLOOR', 0x3e3026, S, 0.08);
def(82, 'NDOOR', 0x2e2219, S, 0.06);
def(83, 'GIRDER', 0x5a3424, S, 0.12);
// ---- trees (round 4)
def(84, 'BLOSSOM2', 0xe58fb2, S | F_LEAF, 0.14);
def(85, 'WILLOW', 0x7d9c46, S | F_LEAF, 0.16);
def(86, 'HOLLOW', 0x4a3524, S, 0.06);
def(87, 'TRUNKC', 0x000000, F_SOLID, 0); // invisible collision for model trees
def(88, 'RAIL', 0x8d8a86, S, 0.04);            // steel rail, the running surface polished
def(89, 'PARQUET', 0x6b3b18, S, 0.07);         // rich varnished dark-walnut parquet floorboards
def(90, 'PAINT_METAL', 0x4f6f66, S, 0.05);     // painted gates, railings, sheds
def(91, 'GLASS', 0x2c3a40, S | F_GLOSS, 0.02); // window panes by day
def(92, 'TULLE', 0xe9e6dc, F_OPAQUE | F_LEAF, 0.03); // lace curtain: cut-out net with rosettes, not solid; its shadow is the lace pattern
def(93, 'FRAME_V', 0xe2ded2, S, 0.03);          // painted wooden window frame, vertical bars
def(94, 'FRAME_H', 0xe2ded2, S, 0.03);          // the same, horizontal bars and corners
def(95, 'TRIM_LIME', 0xe6e1d4, S, 0.04);        // limewashed plaster band round a window
// ---- room wallpapers, bath tile, garage slab & nightmare glass
def(96, 'WP_STRIPES', 0xa97d34, S, 0.04);       // vintage Soviet aged ochre striped hallway wallpaper
def(97, 'WP_FLORAL', 0x9e6e24, S, 0.04);        // aged ochre-mustard botanical floral wallpaper with peeling patches
def(98, 'WP_BLUE', 0x8ea2b4, S, 0.04);          // dusty blue trellis study wallpaper
def(99, 'WP_OCHRE', 0xa66f22, S, 0.04);         // warm vintage golden-ochre damask living room wallpaper
def(100, 'WP_KITCHEN', 0xb88c48, S, 0.04);      // warm aged ochre gingham kitchen wallpaper
def(101, 'WP_GREEN', 0x9ab496, S, 0.04);        // pistachio botanical wallpaper
def(102, 'TILE_BATH', 0xa6ccd4, S, 0.03);       // glossy seafoam ceramic bathroom tile
def(103, 'GARAGE_FLOOR', 0x747672, S, 0.06);    // concrete garage floor slab
def(104, 'N_WP', 0x5c4f46, S, 0.08);            // damp/peeling Nightmare wallpaper
def(105, 'N_TILE', 0x4b565a, S, 0.07);          // cracked gloomy Nightmare bath tile
def(106, 'N_GLASS', 0x3b2628, G, 0.03);         // smoky frosted translucent Nightmare glass

export const MAX_MAT = 112;

export const matFlags = new Uint8Array(256);
// foliage, trunks and roofs are solid but are not "ground": nobody should spawn or stand props on them
export const notGround = new Uint8Array(256);
for (const n of ['WINDOW', 'N_GLASS', 'TULLE', 'TRUNKC', 'BLOSSOM2', 'WILLOW', 'HOLLOW', 'LEAF', 'LEAF2', 'BLOSSOM', 'PINE', 'DEAD_LEAF', 'BARK', 'BIRCH', 'NBARK', 'ROOF', 'NROOF', 'THORN', 'BRAMBLE']) notGround[M[n]] = 1;
for (const m of MATS) if (m) matFlags[m.id] = m.flags;

const lin = (c) => Math.pow(c / 255, 2.2);

// GPU table: 2 vec4 per material: [r,g,b, flags | metallic 0..15 << 8 | porosity 0..15 << 12] [emit, vary, roughness, pattern]
export function materialTable() {
  const a = new Float32Array(256 * 8);
  for (const m of MATS) {
    if (!m) continue;
    const o = m.id * 8;
    a[o] = lin((m.color >> 16) & 255); a[o + 1] = lin((m.color >> 8) & 255); a[o + 2] = lin(m.color & 255);
    a[o + 3] = m.flags | (Math.round(m.metal * 15) << 8) | (Math.round(m.por * 15) << 12);
    a[o + 4] = m.emit; a[o + 5] = m.vary; a[o + 6] = m.rough; a[o + 7] = m.pat;
  }
  return a;
}

