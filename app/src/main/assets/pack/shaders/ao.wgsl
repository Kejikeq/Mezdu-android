
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

// linear view depth (metres) of a depth-buffer value
fn viewZ(dz: f32) -> f32 { return F.taa.x * F.taa.y / (F.taa.y - dz * (F.taa.y - F.taa.x)); }
// the light of the two worlds at world blend w (0 dream .. 1 nightmare)
fn sunCol(w: f32) -> vec3f { return mix(F.sunD.rgb, F.sunN.rgb, w); }
fn skyCol(w: f32) -> vec3f { return mix(F.skyD.rgb, F.skyN.rgb, w); }
fn fogCol(w: f32) -> vec3f { return mix(F.fogD.rgb, F.fogN.rgb, w); }
// distance fog when the volumetric fog pass is off (F.counts.z == 0)
fn flatFog(c: vec3f, p: vec3f, w: f32) -> vec3f {
  if (F.counts.z != 0u) { return c; }
  return mix(c, fogCol(w), 1.0 - exp(-distance(p, F.cam.xyz) * 0.022));
}

@vertex fn vsFull(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4f {
  let x = f32((vi << 1u) & 2u);
  let y = f32(vi & 2u);
  return vec4f(x * 2.0 - 1.0, y * 2.0 - 1.0, 0.0, 1.0);
}

struct AoU { samples: f32, steps: f32, frame: f32, sunUp: f32 };
@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var depthTex: texture_depth_2d;
@group(0) @binding(2) var gbufTex: texture_2d<f32>;
@group(0) @binding(3) var<uniform> A: AoU;
// scene depth (view space) where the world point lands on the screen, and the point's own depth; x < 0 = off screen
fn probe(wp: vec3f, dd: vec2f) -> vec2f {
  let c = F.viewProj * vec4f(wp, 1.0);
  if (c.w < 0.05) { return vec2f(-1.0, 0.0); }
  let uv = c.xy / c.w * vec2f(0.5, -0.5) + 0.5;
  if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0) { return vec2f(-1.0, 0.0); }
  return vec2f(viewZ(textureLoad(depthTex, vec2i(uv * dd), 0)), c.w);
}
@fragment fn fsAo(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let dd = vec2f(textureDimensions(depthTex));
  let pz = min(vec2i(fc.xy * 2.0), vec2i(dd) - vec2i(1));
  let dz = textureLoad(depthTex, pz, 0);
  if (dz >= 1.0) { return vec4f(1.0, 1.0, 1.0, 1.0); }
  let vz = viewZ(dz);
  let gb = textureLoad(gbufTex, pz, 0);
  let n = normalize(gb.rgb * 2.0 - 1.0);
  let uv = (vec2f(pz) + 0.5) / dd;
  let h4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, dz, 1.0);
  let p = h4.xyz / h4.w + n * 0.03;
  let ign = fract(52.9829189 * fract(dot(fc.xy + A.frame * 5.588238, vec2f(0.06711056, 0.00583715))));
  var ao = 1.0;
  if (A.samples > 0.5 && vz < 40.0) {
    let tx = normalize(cross(select(vec3f(1.0, 0.0, 0.0), vec3f(0.0, 0.0, 1.0), abs(n.z) < 0.9), n));
    let ty = cross(n, tx);
    let rad = 0.45;
    var occ = 0.0;
    let ns = u32(A.samples);
    for (var i = 0u; i < ns; i++) {
      let t = (f32(i) + 0.5) / A.samples;
      let a = (f32(i) + ign) * 2.3999632;
      let r = sqrt(t);
      let s = probe(p + (tx * (cos(a) * r) + ty * (sin(a) * r) + n * sqrt(1.0 - t)) * (rad * (0.35 + 0.65 * t)), dd);
      if (s.x < 0.0) { continue; }
      let df = s.y - s.x; // > 0: the sample is behind what the camera sees there
      occ += step(0.03, df) * (1.0 - smoothstep(rad * 0.8, rad * 2.2, df));
    }
    ao = 1.0 - min(occ / A.samples * 1.5, 0.9) * (1.0 - smoothstep(28.0, 40.0, vz));
    if (gb.a >= 0.495) { ao = mix(1.0, ao, 0.4); } // foliage: mostly air between the leaves
  }
  var cs = 1.0;
  if (A.steps > 0.5 && A.sunUp > 0.5 && vz < 24.0 && dot(n, F.sunDir.xyz) > 0.02) {
    let len = min(0.55, 0.12 + vz * 0.05);
    let ns = u32(A.steps);
    for (var i = 0u; i < ns; i++) {
      let s = probe(p + F.sunDir.xyz * (len * (f32(i) + ign) / A.steps), dd);
      if (s.x < 0.0) { break; }
      let df = s.y - s.x;
      if (df > 0.02 && df < 0.3) { cs = 0.0; break; }
    }
    cs = mix(1.0, cs, 1.0 - smoothstep(16.0, 24.0, vz));
  }
  return vec4f(ao, cs, sqrt(clamp(vz / 128.0, 0.0, 1.0)), 1.0);
}
