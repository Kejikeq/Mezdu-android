
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

struct SsrU { steps: f32, frame: f32, grow: f32, pad: f32 };
@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var depthTex: texture_depth_2d;
@group(0) @binding(2) var gbufTex: texture_2d<f32>;
@group(0) @binding(3) var sceneTex: texture_2d<f32>;
@group(0) @binding(4) var linSmp: sampler;
@group(0) @binding(5) var<uniform> U: SsrU;
// xy: screen position of a world point, z: its depth minus the scene depth there (> 0: behind the scene); w < 0: off screen
fn probe(wp: vec3f, dd: vec2f) -> vec4f {
  let c = F.viewProj * vec4f(wp, 1.0);
  if (c.w < 0.05) { return vec4f(0.0, 0.0, 0.0, -1.0); }
  let uv = c.xy / c.w * vec2f(0.5, -0.5) + 0.5;
  if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0) { return vec4f(0.0, 0.0, 0.0, -1.0); }
  let dz = textureLoad(depthTex, vec2i(uv * dd), 0);
  return vec4f(uv, c.w - viewZ(dz), select(1.0, 0.0, dz >= 1.0));
}
@fragment fn fsSsr(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let dd = vec2f(textureDimensions(depthTex));
  let pz = min(vec2i(fc.xy * 4.0), vec2i(dd) - vec2i(1));
  let gb = textureLoad(gbufTex, pz, 0);
  let rest = gb.a - select(0.0, 0.5, gb.a >= 0.495);
  let dz = textureLoad(depthTex, pz, 0);
  if (rest < 0.245 || dz >= 1.0) { return vec4f(0.0); }
  let n = normalize(gb.rgb * 2.0 - 1.0);
  let uv = (vec2f(pz) + 0.5) / dd;
  let h4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, dz, 1.0);
  let p = h4.xyz / h4.w + n * 0.05;
  let vd = normalize(p - F.cam.xyz);
  let r = reflect(vd, n);
  // a ray coming back at the camera would need what is behind it
  let away = 1.0 - smoothstep(0.25, 0.6, dot(r, -vd));
  if (away <= 0.0) { return vec4f(0.0); }
  let ign = fract(52.9829189 * fract(dot(fc.xy + U.frame * 5.588238, vec2f(0.06711056, 0.00583715))));
  var t0 = 0.0;
  var t = 0.12 + 0.12 * ign;
  var hit = vec4f(0.0, 0.0, 0.0, -1.0);
  let ns = u32(U.steps);
  for (var i = 0u; i < ns; i++) {
    let s = probe(p + r * t, dd);
    if (s.w < 0.0) { break; }
    if (s.z > 0.0 && s.w > 0.5) {
      if (s.z > 0.5 + t * 0.15) { break; } // far behind something: the ray is hidden, not a hit
      // refine between the last free point and this one
      var a = t0;
      var b = t;
      hit = s;
      for (var k = 0; k < 4; k++) {
        let m = (a + b) * 0.5;
        let sm = probe(p + r * m, dd);
        if (sm.w > 0.5 && sm.z > 0.0) { b = m; hit = sm; } else { a = m; }
      }
      t = b;
      break;
    }
    t0 = t;
    t = t * U.grow + 0.05;
  }
  if (hit.w < 0.5) { return vec4f(0.0); }
  let e = min(min(hit.x, 1.0 - hit.x), min(hit.y, 1.0 - hit.y));
  let col = textureSampleLevel(sceneTex, linSmp, hit.xy, 0.0).rgb;
  return vec4f(min(col, vec3f(8.0)), away * smoothstep(0.0, 0.07, e) * (1.0 - smoothstep(14.0, 22.0, t)));
}
