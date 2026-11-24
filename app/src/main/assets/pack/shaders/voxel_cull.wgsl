
struct Light { pos: vec4f, col: vec4f };
struct Frame {
  viewProj: mat4x4f, invViewProj: mat4x4f, shadowMat: mat4x4f,
  cam: vec4f, camRight: vec4f, camUp: vec4f, sunDir: vec4f,
  sunD: vec4f, sunN: vec4f, skyD: vec4f, skyN: vec4f, gndD: vec4f, gndN: vec4f,
  fogD: vec4f, fogN: vec4f, fogP: vec4f, wave: vec4f, waveP: vec4f, res: vec4f,
  misc: vec4f, flashPos: vec4f, flashDir: vec4f, player: vec4f, fadeCol: vec4f, grade: vec4f, outRes: vec4f,
  counts: vec4u,
  bubbles: array<vec4f, 8>,
  lights: array<Light, 8>,
  grass: vec4f,
  prevVP: mat4x4f,
  taa: vec4f,
  wave2: vec4f,
  pbr: vec4f, // x: wetness 0..1 (rain), y: share of the sky light that reaches the scene (rooms), w: automatic exposure factor
  skyPD: array<vec4f, 4>, // sky dome of the dream: zenith, horizon, ground, sun glow (src/gfx/sky.js)
  skyPN: array<vec4f, 4>, // ... of the nightmare
  shD: array<vec4f, 9>,   // diffuse light of the environment, SH9 (dream / nightmare)
  shN: array<vec4f, 9>,
  shadowMat2: mat4x4f,    // far shadow cascade (shadowMat is the near one)
  fx: vec4f,              // x: screen-space occlusion texture is valid, y: penumbra texels per unit of depth (0 = hard), z / w: depth bias of the near / far cascade
  fx2: vec4f,             // x: screen-space reflection texture is valid, y: darkness of the time of day (0 day .. 1 night), zw: TAA un-jitter offset (uv)
  skyX: array<vec4f, 2>,  // dream / nightmare: rgb = horizon opposite to the sun, a = stars
  opt: vec4f,             // x: focal length in render pixels, y: sharpening 0..1, z: chromatic aberration in pixels, w: temporal noise phase (0 when TAA is off)
  wind: vec4f,            // xy: the wind over the ground (direction x strength, the same vector the particles drift with), z: gustiness
};
struct ModelInfo { faceStart: u32, faceCount: u32, visBase: u32, flags: u32, pivot: vec4f, rad: vec4f };
struct Inst { m0: vec4f, m1: vec4f, m2: vec4f, model: u32, mask: u32, phase: f32, extra: f32 };
struct RigPose {
  pos: vec4f, // xyz: position, w: scale
  yaw: f32,
  poseId: u32, // 0:idle, 1:walk, 2:sit, 3:kneel, 4:lie, 5:wash_ashore, 6:anxious, 7:reach, 8:dig
  phase: f32,
  time: f32,
  speed: f32,
  mask: u32,
  headache: f32,
  reach: f32,
  holdingTool: u32,
  seatId: u32, // 0:none, 1:ground, 2:bench, 3:sofa
  slot: u32,
  models: vec4u, // x: torso, y: head, z: uarm, w: uarmL
  models2: vec4u, // x: farm, y: farmL, z: leg, w: body (unified skinned mesh)
  _pad: vec3u,
};
struct Particle { p: vec4f, v: vec4f, c: vec4f };

const CHUNK_SIZE_16: u32 = 16u;
const VOXEL_FLAG_EMPTY: u32 = 0u;
const VOXEL_FLAG_VISIBLE: u32 = 1u;
const VOXEL_FLAG_HIDDEN: u32 = 2u;

struct VoxelChunkUniform {
  chunkDim: vec4u,   // x: 16 (chunk width), y: chunk height, z: 16 (chunk depth), w: total chunks
  worldOffset: vec4i,// x, y, z: chunk origin in voxels, w: 0
  params: vec4u,     // x: worldMode, y: drawSlot, z: pad, w: pad
};

struct VoxelDrawArgs {
  count: u32,
  instanceCount: atomic<u32>,
  firstIndex: u32,
  baseVertex: i32,
  firstInstance: u32,
};

@group(0) @binding(0) var<uniform> VC: VoxelChunkUniform;
@group(0) @binding(1) var<storage, read> chunkVoxels: array<u32>;
@group(0) @binding(2) var<storage, read_write> voxelFlags: array<u32>;
@group(0) @binding(3) var<storage, read_write> drawArgs: array<VoxelDrawArgs>;
@group(0) @binding(4) var<storage, read_write> visibleVoxels: array<u32>;

const NEIGHBORS_8 = array<vec2i, 8>(
  vec2i(-1, -1), vec2i( 0, -1), vec2i( 1, -1),
  vec2i(-1,  0),                vec2i( 1,  0),
  vec2i(-1,  1), vec2i( 0,  1), vec2i( 1,  1)
);

fn isVoxelSolid(x: i32, y: i32, z: i32, chunkId: u32) -> bool {
  if (x < 0 || x >= i32(CHUNK_SIZE_16) || z < 0 || z >= i32(CHUNK_SIZE_16) || y < 0 || y >= i32(VC.chunkDim.y)) {
    return false; // Out-of-bounds chunk seam neighbors treated as exposed
  }
  let idx = chunkId * (CHUNK_SIZE_16 * CHUNK_SIZE_16 * VC.chunkDim.y) + u32(y) * 256u + u32(z) * 16u + u32(x);
  return (chunkVoxels[idx] & 0xffu) != 0u;
}

@compute @workgroup_size(16, 16, 1)
fn cullVoxelNeighbors(
  @builtin(local_invocation_id) lid: vec3u,
  @builtin(workgroup_id) wid: vec3u
) {
  let x = lid.x;
  let z = lid.y;
  let y = wid.x;
  let chunkId = wid.y;

  if (x >= CHUNK_SIZE_16 || z >= CHUNK_SIZE_16 || y >= VC.chunkDim.y || chunkId >= VC.chunkDim.w) {
    return;
  }

  let idx = chunkId * (CHUNK_SIZE_16 * CHUNK_SIZE_16 * VC.chunkDim.y) + y * 256u + z * 16u + x;
  let v = chunkVoxels[idx];

  if ((v & 0xffu) == 0u) {
    voxelFlags[idx] = VOXEL_FLAG_EMPTY;
    return;
  }

  var surroundedCount: u32 = 0u;
  for (var i = 0u; i < 8u; i++) {
    let off = NEIGHBORS_8[i];
    if (isVoxelSolid(i32(x) + off.x, i32(y), i32(z) + off.y, chunkId)) {
      surroundedCount++;
    }
  }

  let topSolid = (y + 1u < VC.chunkDim.y) && isVoxelSolid(i32(x), i32(y + 1u), i32(z), chunkId);
  var bottomSolid = true;
  if (y > 0u) {
    bottomSolid = isVoxelSolid(i32(x), i32(y) - 1, i32(z), chunkId);
  }

  // If a voxel is completely surrounded by other voxels, flag it as 'hidden'
  // to avoid unnecessary GPU draw calls, maintaining the 16x16 chunk architecture.
  if (surroundedCount == 8u && topSolid && bottomSolid) {
    voxelFlags[idx] = VOXEL_FLAG_HIDDEN;
    return;
  }

  voxelFlags[idx] = VOXEL_FLAG_VISIBLE;
  let slot = atomicAdd(&drawArgs[VC.params.y].instanceCount, 1u);
  visibleVoxels[slot] = idx;
}
