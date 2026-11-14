
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
  models2: vec4u, // x: farm, y: farmL, z: leg
  _pad: vec3u,
};
struct Particle { p: vec4f, v: vec4f, c: vec4f };

fn hashu(x: u32) -> u32 {
  let v = x * 747796405u + 2891336453u;
  let w = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
  return (w >> 22u) ^ w;
}
fn hash3i(p: vec3i) -> f32 {
  let h = hashu(bitcast<u32>(p.x) + hashu(bitcast<u32>(p.y) + hashu(bitcast<u32>(p.z))));
  return f32(h) / 4294967296.0;
}
fn vnoise3(p: vec3f) -> f32 {
  let fl = floor(p);
  let i = vec3i(fl);
  let f = p - fl;
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash3i(i); let b = hash3i(i + vec3i(1, 0, 0));
  let c = hash3i(i + vec3i(0, 1, 0)); let d = hash3i(i + vec3i(1, 1, 0));
  let e = hash3i(i + vec3i(0, 0, 1)); let g = hash3i(i + vec3i(1, 0, 1));
  let h = hash3i(i + vec3i(0, 1, 1)); let k = hash3i(i + vec3i(1, 1, 1));
  let x00 = mix(a, b, u.x); let x10 = mix(c, d, u.x); let x01 = mix(e, g, u.x); let x11 = mix(h, k, u.x);
  return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

struct Bug { p: vec4f, v: vec4f, h: vec4f, t: vec4f };
struct BugU { dt: f32, time: f32, count: u32, base: u32, frame: u32, asleep: u32, p1: u32, p2: u32 }; // asleep: night, nobody flies
@group(0) @binding(0) var<uniform> B: BugU;
@group(0) @binding(1) var<storage, read_write> bugs: array<Bug>;
@group(0) @binding(2) var<storage, read_write> insts: array<Inst>;
@group(0) @binding(3) var<storage, read> hmap: array<f32>;
fn groundAt(x: f32, z: f32) -> f32 {
  let ix = clamp(i32(x * 2.0), 0, 1535);
  let iz = clamp(i32(z * 2.0), 0, 2559);
  return hmap[ix + iz * 1536];
}
fn rnd(i: u32, k: u32) -> f32 { return f32(hashu(i * 2246822519u + k * 3266489917u + B.frame * 668265263u)) / 4294967296.0; }
fn adiff(a: f32, b: f32) -> f32 { return atan2(sin(a - b), cos(a - b)); }
@compute @workgroup_size(64) fn bugsim(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  if (i >= B.count) { return; }
  var b = bugs[i];
  let dt = B.dt;
  let drag = b.v.w > 0.5;
  if (b.v.w > 1.5) {
    // bird: graceful circles in the sky above clearings and paths, flapping then gliding
    let ph = b.p.w;
    let ang = B.time * (0.11 + fract(ph * 7.3) * 0.06) + ph;
    let rad = 8.5 + fract(ph * 3.1) * 11.5;
    let hy = groundAt(b.h.x, b.h.z) + 10.5 + fract(ph * 5.7) * 6.5 + sin(B.time * 0.32 + ph) * 1.8;
    let p = vec3f(b.h.x + cos(ang) * rad, hy, b.h.z + sin(ang) * rad);
    let yaw = atan2(-sin(ang), cos(ang));
    b.p = vec4f(p, ph);
    bugs[i] = b;
    let sc = 1.45;
    let c = cos(yaw) * sc; let s = sin(yaw) * sc;
    var inst: Inst;
    inst.m0 = vec4f(c, 0.0, s, p.x); inst.m1 = vec4f(0.0, sc, 0.0, p.y); inst.m2 = vec4f(-s, 0.0, c, p.z);
    inst.model = u32(b.t.w); inst.mask = select(1u | 16u | 32u, 0u, B.asleep == 1u); inst.phase = ph;
    inst.extra = select(0.0, 7.5, sin(B.time * 0.45 + ph * 3.0) > -0.2);
    insts[B.base + i] = inst;
    return;
  }
  var timer = b.h.w - dt;
  if (timer <= 0.0 || distance(b.p.xyz, b.t.xyz) < 0.25) {
    let rad = select(3.0, 4.5, drag);
    let tx = b.h.x + (rnd(i, 1u) - 0.5) * 2.0 * rad;
    let tz = b.h.z + (rnd(i, 2u) - 0.5) * 2.0 * rad;
    let ty = groundAt(tx, tz) + select(0.25 + rnd(i, 3u) * 1.4, 0.35 + rnd(i, 3u) * 0.7, drag);
    b.t = vec4f(tx, ty, tz, b.t.w);
    timer = select(2.0 + rnd(i, 4u) * 3.0, 0.7 + rnd(i, 4u) * 2.0, drag);
  }
  var v = b.v.xyz;
  let to = b.t.xyz - b.p.xyz;
  let dist = length(to);
  if (drag) {
    let speed = select(0.0, 4.5, dist > 0.35);
    v = mix(v, to / max(dist, 0.001) * speed, min(dt * 5.0, 1.0));
    v += vec3f(sin(B.time * 23.0 + f32(i)), sin(B.time * 17.0 + f32(i) * 3.0), cos(B.time * 19.0 + f32(i))) * 0.06;
  } else {
    let dirv = (to + vec3f(0.0, sin(B.time * 4.0 + b.p.w) * 0.5, 0.0)) / max(dist, 0.001);
    v = mix(v, dirv * 1.0, min(dt * 2.0, 1.0));
    v.y += sin(B.time * 11.0 + b.p.w * 3.0) * 0.06;
  }
  let p = b.p.xyz + v * dt;
  var yaw = b.h.y;
  if (length(v.xz) > 0.12) { yaw = yaw + adiff(atan2(v.x, v.z), yaw) * min(dt * 7.0, 1.0); }
  b.p = vec4f(p, b.p.w);
  b.v = vec4f(v, b.v.w);
  b.h = vec4f(b.h.x, yaw, b.h.z, timer);
  bugs[i] = b;
  let c = cos(yaw);
  let s = sin(yaw);
  var inst: Inst;
  inst.m0 = vec4f(c, 0.0, s, p.x);
  inst.m1 = vec4f(0.0, 1.0, 0.0, p.y);
  inst.m2 = vec4f(-s, 0.0, c, p.z);
  inst.model = u32(b.t.w);
  inst.mask = select(1u | 16u | 32u, 0u, B.asleep == 1u);
  inst.phase = b.p.w;
  inst.extra = select(13.0, 48.0, drag);
  insts[B.base + i] = inst;
}
