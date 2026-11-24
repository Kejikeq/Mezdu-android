
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

@vertex fn vsFull(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4f {
  let x = f32((vi << 1u) & 2u);
  let y = f32(vi & 2u);
  return vec4f(x * 2.0 - 1.0, y * 2.0 - 1.0, 0.0, 1.0);
}

fn skyDome(rd: vec3f, w: f32) -> vec3f {
  let zen = mix(F.skyPD[0].rgb, F.skyPN[0].rgb, w);
  // the horizon is warm towards a low sun and cool opposite to it
  let side = 0.5 + 0.5 * dot(rd.xz, F.sunDir.xz) / max(length(F.sunDir.xz), 0.0001);
  let hor = mix(mix(F.skyX[0].rgb, F.skyX[1].rgb, w), mix(F.skyPD[1].rgb, F.skyPN[1].rgb, w), side * side);
  let gnd = mix(F.skyPD[2].rgb, F.skyPN[2].rgb, w);
  let glow = mix(F.skyPD[3].rgb, F.skyPN[3].rgb, w);
  let up = max(rd.y, 0.0);
  let k = 1.0 - (1.0 - up) * (1.0 - up);
  let s = max(dot(rd, F.sunDir.xyz), 0.0);
  let s2 = s * s;
  let s4 = s2 * s2;
  let s16 = s4 * s4 * s4 * s4;
  let c = mix(hor, zen, k) + glow * (s4 * 0.38 + s16 * s16 * 0.95);
  return mix(gnd, c, smoothstep(-0.25, 0.0, rd.y));
}

struct BakeU { face: u32, env: u32, rough: f32, size: f32 };
@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var<uniform> B: BakeU;
fn faceDir(face: u32, uv: vec2f) -> vec3f {
  switch (face) {
    case 0u: { return vec3f(1.0, -uv.y, -uv.x); }
    case 1u: { return vec3f(-1.0, -uv.y, uv.x); }
    case 2u: { return vec3f(uv.x, 1.0, uv.y); }
    case 3u: { return vec3f(uv.x, -1.0, -uv.y); }
    case 4u: { return vec3f(uv.x, -uv.y, 1.0); }
    default: { return vec3f(-uv.x, -uv.y, -1.0); }
  }
}
fn hamm(i: u32, n: u32) -> vec2f { return vec2f(f32(i) / f32(n), f32(reverseBits(i)) * 2.3283064365386963e-10); }
// a GGX-distributed half vector around +z for roughness alpha a
fn ggxH(xi: vec2f, a: f32) -> vec3f {
  let phi = 6.2831853 * xi.x;
  let ct = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
  let st = sqrt(max(1.0 - ct * ct, 0.0));
  return vec3f(st * cos(phi), st * sin(phi), ct);
}
@fragment fn fsEnv(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let n = normalize(faceDir(B.face, fc.xy / B.size * 2.0 - 1.0));
  let w = f32(B.env);
  if (B.rough < 0.01) { return vec4f(skyDome(n, w), 1.0); }
  let tx = normalize(cross(select(vec3f(1.0, 0.0, 0.0), vec3f(0.0, 0.0, 1.0), abs(n.z) < 0.99), n));
  let ty = cross(n, tx);
  var col = vec3f(0.0);
  var ws = 0.0;
  for (var i = 0u; i < 64u; i++) {
    let h = ggxH(hamm(i, 64u), B.rough * B.rough);
    let hw = tx * h.x + ty * h.y + n * h.z;
    let l = 2.0 * dot(n, hw) * hw - n;
    let nl = dot(n, l);
    if (nl > 0.0) { col += skyDome(l, w) * nl; ws += nl; }
  }
  return vec4f(col / max(ws, 0.001), 1.0);
}
// scale and bias of F0 for the specular reflection of the environment (same GGX / Smith as specGGX)
@fragment fn fsLut(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let nv = fc.x / 64.0;
  let rough = fc.y / 64.0;
  let a = max(rough * rough, 0.002);
  let a2 = a * a;
  let v = vec3f(sqrt(1.0 - nv * nv), 0.0, nv);
  var sc = 0.0;
  var bi = 0.0;
  for (var i = 0u; i < 128u; i++) {
    let h = ggxH(hamm(i, 128u), a);
    let vh = max(dot(v, h), 0.0);
    let l = 2.0 * vh * h - v;
    let nl = l.z;
    if (nl > 0.0) {
      let vis = 0.5 / (nl * sqrt(nv * nv * (1.0 - a2) + a2) + nv * sqrt(nl * nl * (1.0 - a2) + a2));
      let gv = vis * vh * nl * 4.0 / max(h.z, 0.0001);
      let f = pow(1.0 - vh, 5.0);
      sc += (1.0 - f) * gv;
      bi += f * gv;
    }
  }
  return vec4f(sc / 128.0, bi / 128.0, 0.0, 1.0);
}
