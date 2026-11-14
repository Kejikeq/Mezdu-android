
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

@vertex fn vsFull(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4f {
  let x = f32((vi << 1u) & 2u);
  let y = f32(vi & 2u);
  return vec4f(x * 2.0 - 1.0, y * 2.0 - 1.0, 0.0, 1.0);
}

@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var sceneTex: texture_2d<f32>;
@group(0) @binding(2) var depthTex: texture_depth_2d;
@group(0) @binding(3) var histTex: texture_2d<f32>;
@group(0) @binding(4) var linSmp: sampler;
@fragment fn fsTaa(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let ip = vec2i(fc.xy);
  let dims = vec2i(textureDimensions(sceneTex));
  let cur = textureLoad(sceneTex, ip, 0).rgb;
  if (F.taa.w < 0.5) { return vec4f(cur, 1.0); }
  // clamp box from the 4 direct neighbours (a cross: 5 reads instead of 9)
  var mn = cur; var mx = cur; var avg = cur;
  for (var k = 0; k < 4; k++) {
    var o = vec2i(1, 0);
    if (k == 1) { o = vec2i(-1, 0); } else if (k == 2) { o = vec2i(0, 1); } else if (k == 3) { o = vec2i(0, -1); }
    let c = textureLoad(sceneTex, clamp(ip + o, vec2i(0), dims - vec2i(1)), 0).rgb;
    mn = min(mn, c); mx = max(mx, c); avg += c;
  }
  let d = textureLoad(depthTex, ip, 0);
  let uv = (vec2f(ip) + 0.5) / vec2f(dims);
  let w4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, d, 1.0);
  let wp = w4.xyz / w4.w;
  let pp = F.prevVP * vec4f(wp, 1.0);
  let puv = vec2f(pp.x / pp.w * 0.5 + 0.5, 0.5 - pp.y / pp.w * 0.5);
  if (pp.w <= 0.0 || puv.x < 0.0 || puv.y < 0.0 || puv.x > 1.0 || puv.y > 1.0) { return vec4f(cur, 1.0); }
  let hist = textureSampleLevel(histTex, linSmp, puv, 0.0).rgb;
  // soften the clamp box a little toward the mean (less flicker on thin features)
  let m = avg / 5.0;
  let hc = clamp(hist, mix(mn, m, 0.15), mix(mx, m, 0.15));
  let motion = length((puv - uv) * vec2f(dims));
  let a = clamp(0.09 + motion * 0.015, 0.09, 0.4);
  return vec4f(mix(hc, cur, a), 1.0);
}
