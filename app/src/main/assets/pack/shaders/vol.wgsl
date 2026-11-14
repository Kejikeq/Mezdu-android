
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

@vertex fn vsFull(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4f {
  let x = f32((vi << 1u) & 2u);
  let y = f32(vi & 2u);
  return vec4f(x * 2.0 - 1.0, y * 2.0 - 1.0, 0.0, 1.0);
}

@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var shadowTex: texture_depth_2d;
@group(0) @binding(2) var shadowSmp: sampler_comparison;
@group(0) @binding(3) var depthTex: texture_depth_2d;
@group(0) @binding(4) var fogNoise: texture_3d<f32>;
@group(0) @binding(5) var repSmp: sampler;
fn hgPhase(c: f32, g: f32) -> f32 { let g2 = g * g; return (1.0 - g2) / (12.566 * pow(max(1.0 + g2 - 2.0 * g * c, 0.0001), 1.5)); }
fn worldAtCheap(p: vec3f) -> f32 {
  var w = F.waveP.w;
  if (F.waveP.z > 0.5) { w = select(F.waveP.x, F.waveP.y, distance(p, F.wave.xyz) < F.wave.w || (F.wave2.w > 0.0 && distance(p, F.wave2.xyz) > F.wave2.w)); }
  for (var i = 0u; i < F.counts.y; i++) { let b = F.bubbles[i]; if (distance(p, b.xyz) < b.w) { w = 0.0; } }
  return w;
}
fn fogDensity(p: vec3f, w: f32) -> f32 {
  let base = mix(F.fogD.w, F.fogN.w, w);
  let h = max(p.y - F.fogP.x, 0.0);
  var d = base * exp(-h * F.fogP.y);
  // one trilinear fetch from a periodic 32^3 noise volume instead of 8 hashes per step
  let n = textureSampleLevel(fogNoise, repSmp, (p * vec3f(0.08, 0.15, 0.08) + vec3f(F.cam.w * 0.11, 0.0, F.cam.w * 0.04)) * 0.25, 0.0).r;
  d *= (1.0 - F.fogP.z) + F.fogP.z * 2.0 * n;
  return d;
}
fn shadowVol(p: vec3f) -> f32 {
  if (F.counts.w == 0u) { return 1.0; }
  let sp = F.shadowMat2 * vec4f(p, 1.0); // the far cascade is bound here: the shafts reach further than the near one
  let uv = vec2f(sp.x * 0.5 + 0.5, 0.5 - sp.y * 0.5);
  if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0 || sp.z >= 1.0) { return 1.0; }
  return textureSampleCompareLevel(shadowTex, shadowSmp, uv, sp.z - 0.002);
}
@fragment fn fsVol(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let dims = vec2i(textureDimensions(depthTex));
  let full = min(vec2i(fc.xy * 2.0), dims - vec2i(1)); // half resolution: the centre pixel of a 2x2 block
  let d = textureLoad(depthTex, full, 0);
  let uv = (vec2f(full) + 0.5) / vec2f(dims);
  let wp4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, d, 1.0);
  let wp = wp4.xyz / wp4.w;
  let ro = F.cam.xyz;
  var rd = wp - ro;
  var dist = length(rd);
  rd = rd / max(dist, 0.0001);
  let sky = d >= 1.0;
  if (sky) { dist = F.fogP.w * 0.42; }
  dist = min(dist, F.fogP.w);
  let steps = max(F.counts.z, 1u);
  let jit = fract(52.9829189 * fract(dot(fc.xy, vec2f(0.06711056, 0.00583715))));
  let cosT = dot(rd, F.sunDir.xyz);
  // forward scattering: soft shafts toward the sun without a blinding peak (g 0.6, capped); sideways as before
  let ph = min(mix(hgPhase(cosT, 0.6), 0.0796, 0.3) * 4.6, 2.6);
  var T = 1.0;
  var L = vec3f(0.0);
  var lastLi = mix(F.fogD.rgb, F.fogN.rgb, F.waveP.w);
  var tPrev = 0.0;
  for (var s = 0u; s < steps; s++) {
    // the steps crowd towards the camera (power 1.6): light shafts near the hero keep their edges
    let t = dist * pow((f32(s) + jit) / f32(steps), 1.6);
    let tEnd = dist * pow(f32(s + 1u) / f32(steps), 1.6);
    let sl = tEnd - tPrev;
    tPrev = tEnd;
    let p = ro + rd * t;
    let w = worldAtCheap(p);
    let dens = fogDensity(p, w);
    let sh = shadowVol(p);
    var Li = sunCol(w) * sh * ph + fogCol(w);
    let wm = select(1u, 2u, w > 0.5);
    for (var i = 0u; i < min(F.counts.x, 3u); i++) {
      let Lt = F.lights[i];
      if ((u32(Lt.col.w) & wm) == 0u) { continue; }
      let dd = distance(Lt.pos.xyz, p);
      let att = max(1.0 - dd / (Lt.pos.w * 0.7), 0.0);
      Li += Lt.col.rgb * att * att * 0.45;
    }
    let tr = exp(-dens * sl);
    L += T * Li * (1.0 - tr);
    T *= tr;
    lastLi = Li;
    if (T < 0.01) { break; }
  }
  // Keep sky & sun clearly visible through upper atmospheric haze
  if (sky) {
    let skyClear = smoothstep(0.02, 0.28, max(rd.y, 0.0));
    let minT = mix(0.45, 0.78, skyClear);
    if (T < minT) {
      L *= (1.0 - minT) / max(1.0 - T, 0.001);
      T = minT;
    }
  } else {
    let e = smoothstep(F.fogP.w * 0.68, F.fogP.w * 0.98, dist);
    L += T * e * lastLi; T *= 1.0 - e;
  }
  return vec4f(L, T);
}
