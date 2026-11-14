
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

struct SimU { dt: f32, time: f32, count: u32, frame: u32, cam: vec4f, smoke: vec4f, ember: vec4f, drip: vec4f, wind: vec4f };
@group(0) @binding(0) var<uniform> S: SimU;
@group(0) @binding(1) var<storage, read_write> parts: array<Particle>;
@group(0) @binding(2) var<storage, read> hmap: array<f32>;
fn groundAt(x: f32, z: f32) -> f32 {
  let ix = clamp(i32(x * 2.0), 0, 1535);
  let iz = clamp(i32(z * 2.0), 0, 2559);
  return hmap[ix + iz * 1536];
}
fn rnd(i: u32, k: u32) -> f32 { return f32(hashu(i * 1664525u + k * 1013904223u + S.frame * 2654435761u)) / 4294967296.0; }
@compute @workgroup_size(64) fn sim(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  if (i >= S.count) { return; }
  var pt = parts[i];
  let ty = u32(pt.v.w);
  let dt = S.dt;
  switch ty {
    case 1u: {
      let t = S.time * 0.33 + pt.c.w * 50.0;
      let tgt = pt.c.xyz + vec3f(sin(t * 1.3) * 2.4 + sin(t * 0.7) * 1.4, sin(t * 0.9) * 0.7, cos(t * 1.1) * 2.4 + cos(t * 0.5) * 1.4);
      var v = pt.v.xyz + ((tgt - pt.p.xyz) * 0.8 - pt.v.xyz * 0.9) * dt;
      var p = pt.p.xyz + v * dt;
      let g = groundAt(p.x, p.z) + 0.25;
      if (p.y < g) { p.y = g; v.y = abs(v.y); }
      pt.p = vec4f(p, 1.0);
      pt.v = vec4f(v, pt.v.w);
    }
    case 2u, 3u: {
      let wob = vec3f(sin(S.time * 0.5 + pt.c.w * 9.0), sin(S.time * 0.37 + pt.c.w * 5.0) * 0.5, cos(S.time * 0.43 + pt.c.w * 7.0)) * 0.06;
      var p = pt.p.xyz + (pt.v.xyz + S.wind.xyz * 0.15 + wob) * dt;
      let hs = vec3f(9.0, 4.5, 9.0);
      let rel = p - S.cam.xyz + hs;
      p = S.cam.xyz + (rel - floor(rel / (2.0 * hs)) * 2.0 * hs) - hs;
      pt.p = vec4f(p, 1.0);
    }
    case 4u: {
      var life = pt.p.w - dt * 0.12;
      var p = pt.p.xyz;
      var v = pt.v.xyz;
      if (life <= 0.0) {
        if (S.smoke.w > 0.5 && rnd(i, 9u) < 0.03) {
          life = 1.0; p = S.smoke.xyz + vec3f(rnd(i, 2u) - 0.5, 0.0, rnd(i, 3u) - 0.5) * 0.4; v = vec3f(0.0, 0.45 + rnd(i, 4u) * 0.3, 0.0);
        } else { life = 0.0; }
      } else { v += (S.wind.xyz * 0.6 - v * 0.15) * dt; v.y += 0.04 * dt; p += v * dt; }
      pt.p = vec4f(p, life);
      pt.v = vec4f(v, pt.v.w);
    }
    case 5u: {
      var life = pt.p.w - dt * 0.8;
      var p = pt.p.xyz;
      var v = pt.v.xyz;
      if (life <= 0.0) {
        if (S.ember.w > 0.5 && rnd(i, 9u) < 0.05) {
          life = 0.6 + rnd(i, 1u) * 0.4; p = S.ember.xyz + vec3f(rnd(i, 2u) - 0.5, 0.0, rnd(i, 3u) - 0.5) * 0.5;
          v = vec3f((rnd(i, 5u) - 0.5) * 0.4, 1.0 + rnd(i, 4u) * 1.3, (rnd(i, 6u) - 0.5) * 0.4);
        } else { life = 0.0; }
      } else { v += vec3f(sin(S.time * 7.0 + f32(i)) * 0.9, -0.2, cos(S.time * 6.0 + f32(i)) * 0.9) * dt; p += v * dt; }
      pt.p = vec4f(p, life);
      pt.v = vec4f(v, pt.v.w);
    }
    case 10u: {
      // splash: droplets thrown up where the stream steps down (home = c.xyz)
      var life = pt.p.w - dt * 1.6;
      var p = pt.p.xyz;
      var v = pt.v.xyz;
      if (life <= 0.0) {
        if (pt.c.y > 0.0 && distance(pt.c.xyz, S.cam.xyz) < 40.0) {
          life = 0.5 + rnd(i, 1u) * 0.5;
          p = pt.c.xyz + vec3f(rnd(i, 2u) - 0.5, 0.0, rnd(i, 3u) - 0.5) * 0.45;
          v = vec3f((rnd(i, 5u) - 0.5) * 1.2, 0.6 + rnd(i, 4u) * 1.3, (rnd(i, 6u) - 0.5) * 1.2);
        } else { life = 0.0; }
      } else { v.y -= 7.5 * dt; p += v * dt; }
      pt.p = vec4f(p, life);
      pt.v = vec4f(v, pt.v.w);
    }
    case 6u: {
      var life = pt.p.w - dt * 0.9;
      var p = pt.p.xyz;
      var v = pt.v.xyz;
      if (life <= 0.0) {
        if (S.drip.w > 0.5 && rnd(i, 9u) < 0.08) { life = 1.0; p = S.drip.xyz + vec3f(rnd(i, 2u) - 0.5, 0.0, rnd(i, 3u) - 0.5) * 0.12; v = vec3f(0.0, -0.1, 0.0); }
        else { life = 0.0; }
      } else {
        v.y -= 3.0 * dt; p += v * dt;
        let g = groundAt(p.x, p.z);
        if (p.y < g) { p.y = g; v = vec3f(0.0); }
      }
      pt.p = vec4f(p, life);
      pt.v = vec4f(v, pt.v.w);
    }
    case 7u: {
      var p = pt.p.xyz + (vec3f(sin(S.time * 1.1 + pt.c.w * 20.0) * 0.4, -0.42, cos(S.time * 0.9 + pt.c.w * 13.0) * 0.3) + S.wind.xyz * 0.4) * dt;
      let rel = p - S.cam.xyz;
      if (p.y < groundAt(p.x, p.z) || abs(rel.x) > 14.0 || abs(rel.z) > 14.0) {
        p = S.cam.xyz + vec3f((rnd(i, 1u) - 0.5) * 26.0, 4.0 + rnd(i, 2u) * 6.0, (rnd(i, 3u) - 0.5) * 26.0);
      }
      pt.p = vec4f(p, 1.0);
    }
    default: { }
  }
  parts[i] = pt;
}
