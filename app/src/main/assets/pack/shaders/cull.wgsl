
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

struct CullU { planes: array<vec4f, 6>, cam: vec4f, count: vec4u, wave: vec4f, wave2: vec4f, waveP: vec4f, bubbles: array<vec4f, 8>, nb: vec4u };
// 32-byte slots; word 1 is the instance count for both draw and drawIndexed layouts
struct DrawArgs { count: u32, instanceCount: atomic<u32>, a: u32, b: u32, c: u32, d: u32, e: u32, f: u32 };
@group(0) @binding(0) var<uniform> U: CullU;
@group(0) @binding(1) var<storage, read> minfo: array<ModelInfo>;
@group(0) @binding(2) var<storage, read> insts: array<Inst>;
@group(0) @binding(3) var<storage, read_write> args: array<DrawArgs>;
@group(0) @binding(4) var<storage, read_write> vis: array<u32>;
// instance ranges (start, count, first thread) of the map cells near the camera + the dynamic block
@group(0) @binding(5) var<storage, read> ranges: array<vec4u>;
fn rangedIndex(g: u32) -> u32 {
  var lo = 0u; var hi = max(U.nb.y, 1u) - 1u;
  loop {
    if (lo >= hi) { break; }
    let mid = (lo + hi + 1u) / 2u;
    if (ranges[mid].z <= g) { lo = mid; } else { hi = mid - 1u; }
  }
  let r = ranges[lo];
  return r.x + (g - r.z);
}
@compute @workgroup_size(64) fn cull(@builtin(global_invocation_id) gid: vec3u) {
  if (gid.x >= U.count.x) { return; }
  let i = rangedIndex(gid.x);
  let inst = insts[i];
  if (inst.mask == 0u || inst.model >= U.count.z) { return; }
  if (U.count.y == 1u && (inst.mask & 4u) == 0u) { return; }
  if ((inst.mask & U.count.w) == 0u) { return; }
  let mi = minfo[inst.model];
  let isSkinned = (mi.flags & 8192u) != 0u;
  let p = vec3f(inst.m0.w, inst.m1.w, inst.m2.w);
  let cullP = select(p, p + vec3f(0.0, 0.9, 0.0), isSkinned);
  let baseR = mi.rad.x * length(inst.m0.xyz);
  let r = select(baseR, max(baseR, 2.5), isSkinned);
  // mixed frame: an instance clearly inside one world (away from the wave fronts and bubble edges)
  // is drawn only in that world's version; near a front both versions stay for the per-pixel test
  if (U.count.w == 3u && (inst.mask & 3u) != 3u) {
    var w = U.waveP.w; var unsure = false;
    if (U.waveP.z > 0.5) {
      let dw = distance(p, U.wave.xyz);
      var inside = dw < U.wave.w;
      unsure = abs(dw - U.wave.w) < r + 3.0;
      if (U.wave2.w > 0.0) { let d2 = distance(p, U.wave2.xyz); inside = inside || d2 > U.wave2.w; unsure = unsure || abs(d2 - U.wave2.w) < r + 3.0; }
      w = select(U.waveP.x, U.waveP.y, inside);
    }
    for (var b = 0u; b < U.nb.x; b++) {
      let bb = U.bubbles[b]; let db = distance(p, bb.xyz);
      if (db < bb.w) { w = 0.0; }
      unsure = unsure || abs(db - bb.w) < r + 2.0;
    }
    if (!unsure && (inst.mask & select(1u, 2u, w > 0.5)) == 0u) { return; }
  }
  let d = distance(cullP, U.cam.xyz);
  // Fog-aware impostor & distance culling:
  // Key story entities (deer, figures, rabbit, rigs) with mi.rad.y > 55m stay visible up to mi.rad.y
  if (d - r > max(55.0, mi.rad.y)) { return; }
  let lod = (mi.flags & 2u) != 0u; // 2u = far / low-poly / impostor model
  let dl = max(d - r * 0.8, 0.0);
  // Near high-poly models (lod == false) are culled at d - r > max(32.0, mi.rad.y)
  if (!lod && d - r > max(32.0, mi.rad.y)) { return; }
  // two preset multipliers: cam.w scales the draw distance, nb.z (f32 bits) scales the switches
  // between detail levels; 1024u = a farther detail level exists, so this model's far end is a switch
  let kl = bitcast<f32>(U.nb.z);
  if (select(d - r, dl, lod) > mi.rad.y * select(U.cam.w, kl, (mi.flags & 1024u) != 0u)) { return; }
  if (lod && dl < mi.rad.z * kl) { return; }
  if (!(isSkinned && d < 8.0)) {
    for (var k = 0; k < 6; k++) {
      let pl = U.planes[k];
      if (dot(pl.xyz, cullP) + pl.w < -r) { return; }
    }
  }
  let slot = atomicAdd(&args[inst.model].instanceCount, 1u);
  // never past the model's own share of the list (rad.w = capacity): an extra instance would be drawn by the next model
  if (slot >= u32(mi.rad.w)) { atomicSub(&args[inst.model].instanceCount, 1u); return; }
  vis[mi.visBase + slot] = i;
}
// shadow casters (far tree models) inside the shadow box: cam = shadow centre, cam.w = half extent
@compute @workgroup_size(64) fn cullShadow(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  if (i >= U.count.x) { return; }
  let inst = insts[i];
  if (inst.mask == 0u || inst.model >= U.count.z || (inst.mask & 16u) != 0u) { return; }
  if ((inst.mask & U.count.w) == 0u) { return; }
  let mi = minfo[inst.model];
  if ((mi.flags & 1u) == 0u) { return; }
  let p = vec3f(inst.m0.w, inst.m1.w, inst.m2.w);
  let r = mi.rad.x * length(inst.m0.xyz);
  if (abs(p.x - U.cam.x) > U.cam.w + r || abs(p.z - U.cam.z) > U.cam.w + r) { return; }
  let slot = atomicAdd(&args[inst.model].instanceCount, 1u);
  // never past the model's own share of the list (rad.w = capacity): an extra instance would be drawn by the next model
  if (slot >= u32(mi.rad.w)) { atomicSub(&args[inst.model].instanceCount, 1u); return; }
  vis[mi.visBase + slot] = i;
}
