
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

@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var shadowTex: texture_depth_2d;
@group(0) @binding(2) var shadowSmp: sampler_comparison;
@group(0) @binding(3) var<uniform> mats: array<vec4f, 512>;
@group(0) @binding(4) var<storage, read> chunkOrg: array<vec4f>;
@group(0) @binding(5) var<storage, read> minfo: array<ModelInfo>;
@group(0) @binding(6) var<storage, read> mfaces: array<u32>;
@group(0) @binding(7) var<storage, read> insts: array<Inst>;
@group(0) @binding(8) var<storage, read> vis: array<u32>;
@group(0) @binding(9) var<storage, read> parts: array<Particle>;
@group(0) @binding(10) var atlas: texture_2d<f32>;
@group(0) @binding(11) var<storage, read> gcol: array<u32>;
@group(0) @binding(12) var noise3: texture_3d<f32>;
@group(0) @binding(13) var repSmp: sampler;
@group(0) @binding(14) var colorLUT: texture_3d<f32>;
@group(0) @binding(15) var atlasPbr: texture_2d<f32>; // roughness, metallic, micro occlusion, wet mask
@group(0) @binding(16) var envD: texture_cube<f32>;   // sky reflections prefiltered by roughness (mips 0..4), dream
@group(0) @binding(17) var envN: texture_cube<f32>;   // ... nightmare
@group(0) @binding(18) var brdfLut: texture_2d<f32>;  // split-sum environment BRDF: x = n.v, y = roughness
@group(0) @binding(19) var shadowTex2: texture_depth_2d; // far shadow cascade
@group(0) @binding(20) var aoTex: texture_2d<f32>;    // last frame, half resolution: r = SSAO, g = contact shadow, b = depth key
@group(0) @binding(21) var ssrTex: texture_2d<f32>;   // last frame, quarter resolution: rgb = reflected radiance, a = confidence
override WMODE: u32 = 2u; // 0 = dream, 1 = nightmare (constant world), 2 = per-pixel world function

// face directions 0..5 = +x -x +y -y +z -z and quad corners 0..3 by arithmetic: no small lookup
// arrays (dynamically indexed private arrays spill to slow memory on mobile GPUs)
fn axv(a: u32) -> vec3f { return vec3f(f32(a == 0u), f32(a == 1u), f32(a == 2u)); }
fn nrmOf(d: u32) -> vec3f { return axv(d >> 1u) * select(-1.0, 1.0, (d & 1u) == 0u); }
fn uaxOf(d: u32) -> u32 {
  switch (d) {
    case 0u: { return 1u; }
    case 1u: { return 2u; }
    case 2u: { return 2u; }
    case 3u: { return 0u; }
    case 4u: { return 0u; }
    default: { return 1u; }
  }
}
fn vaxOf(d: u32) -> u32 {
  switch (d) {
    case 0u: { return 2u; }
    case 1u: { return 1u; }
    case 2u: { return 0u; }
    case 3u: { return 2u; }
    case 4u: { return 1u; }
    default: { return 0u; }
  }
}
fn nposOf(d: u32) -> f32 { return select(0.0, 1.0, (d & 1u) == 0u); }
fn cuOf(c: u32) -> f32 { return select(0.0, 1.0, c == 1u || c == 2u); }
fn cvOf(c: u32) -> f32 { return select(0.0, 1.0, c >= 2u); }
fn quadCorner(k: u32) -> u32 { return select(k, select(k - 2u, 0u, k == 3u), k >= 3u); } // 0 1 2 0 2 3
// voxel-space corner offset of a face corner: plane offset along the normal + the quad extents
fn faceOffset(d: u32, c: u32, du: f32, dv: f32) -> vec3f {
  return axv(d >> 1u) * nposOf(d) + axv(uaxOf(d)) * (cuOf(c) * du) + axv(vaxOf(d)) * (cvOf(c) * dv);
}

// G-buffer alpha: ambient occlusion in 5 bits + flags 0.5 = foliage, 0.25 = reflective (roughness < 0.3: the
// screen-space reflection rays start from these pixels), 0.125 = moving object (TAA trusts its history less)
fn gbA(ao: f32, foliage: bool, refl: bool, dyn: bool) -> f32 {
  return clamp(ao, 0.0, 1.0) * 0.115 + select(0.0, 0.5, foliage) + select(0.0, 0.25, refl) + select(0.0, 0.125, dyn);
}
// where a world point was on the screen in the last frame (xy) and its depth key (z); z < 0 = it was off screen
fn prevUV(p: vec3f) -> vec3f {
  let pc = F.prevVP * vec4f(p, 1.0);
  let uv = pc.xy / max(pc.w, 0.001) * vec2f(0.5, -0.5) + 0.5;
  if (pc.w <= 0.05 || uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0) { return vec3f(0.0, 0.0, -1.0); }
  return vec3f(clamp(uv, vec2f(0.002), vec2f(0.998)), sqrt(clamp(pc.w / 128.0, 0.0, 1.0)));
}
fn shadowUV(m: mat4x4f, p: vec3f) -> vec3f {
  let sp = m * vec4f(p, 1.0);
  return vec3f(sp.x * 0.5 + 0.5, 0.5 - sp.y * 0.5, sp.z);
}
// Sun visibility from two cascades centred on the hero. Near cascade: 4 bilinear comparison taps (a 3x3 footprint),
// with fine = true and soft shadows on the taps spread with the distance to the blocker (penumbra) and turn with
// the frame (TAA averages them). Far cascade: one filtered tap. The cascades blend over the rim of the near one.
fn shadowSun(p: vec3f, n: vec3f, fine: bool) -> f32 {
  if (F.counts.w == 0u) { return 1.0; }
  let q = shadowUV(F.shadowMat, p + n * 0.035);
  let e = max(abs(q.x - 0.5), abs(q.y - 0.5));
  var s1 = 1.0;
  if (e > 0.42 || q.z >= 1.0) {
    let r = shadowUV(F.shadowMat2, p + n * 0.09);
    if (r.x > 0.002 && r.x < 0.998 && r.y > 0.002 && r.y < 0.998 && r.z < 1.0) { s1 = textureSampleCompareLevel(shadowTex2, shadowSmp, r.xy, r.z - F.fx.w); }
    if (e >= 0.49 || q.z >= 1.0) { return s1; }
  }
  let z = q.z - F.fx.z;
  var s0 = 0.0;
  if (!fine) { s0 = textureSampleCompareLevel(shadowTex, shadowSmp, q.xy, z); }
  else {
    var k = 1.0;
    var cs = 1.0;
    var sn = 0.0;
    if (F.fx.y > 0.0) {
      let dim = vec2i(textureDimensions(shadowTex));
      let pc = vec2i(q.xy * vec2f(dim));
      var zb = 0.0;
      var nb = 0.0;
      for (var j = 0; j < 4; j++) {
        let d = textureLoad(shadowTex, clamp(pc + vec2i((j & 1) * 4 - 2, (j >> 1) * 4 - 2), vec2i(0), dim - vec2i(1)), 0);
        if (d < z) { zb += d; nb += 1.0; }
      }
      if (nb > 0.5) { k = clamp((z - zb / nb) * F.fx.y, 1.0, 4.5); }
      let a = fract(52.9829189 * fract(dot(p.xz * 37.0 + p.yy * 19.0, vec2f(0.06711056, 0.00583715))) + F.opt.w * 0.618034) * 6.2831853;
      cs = cos(a); sn = sin(a);
    }
    let t = F.grade.z * k;
    let o1 = vec2f(cs - sn, sn + cs) * t;
    let o2 = vec2f(-cs - sn, -sn + cs) * t;
    s0 = (textureSampleCompareLevel(shadowTex, shadowSmp, q.xy + o1, z) + textureSampleCompareLevel(shadowTex, shadowSmp, q.xy - o1, z)
      + textureSampleCompareLevel(shadowTex, shadowSmp, q.xy + o2, z) + textureSampleCompareLevel(shadowTex, shadowSmp, q.xy - o2, z)) * 0.25;
  }
  return mix(s0, s1, smoothstep(0.42, 0.49, e));
}
fn flashCone(p: vec3f) -> f32 {
  if (F.misc.y < 0.5) { return 0.0; }
  let d = p - F.flashPos.xyz;
  let d2 = dot(d, d);
  let invD = inverseSqrt(max(d2, 0.0001));
  let c = smoothstep(F.flashPos.w, F.flashPos.w + 0.05, dot(d * invD, F.flashDir.xyz));
  return c / (1.0 + d2 * 0.03);
}
// Forward+ Single Target Rendering: target 0 = scene HDR radiance/albedo (rgba16float)
struct GFragOut {
  @location(0) col: vec4f,
  @location(1) norm: vec4f, // xyz: normal, w: ao/flags (bit 1: foliage)
};
// ---- PBR (metallic-roughness). Light colours are "pi-less": diffuse = albedo * light * n.l, so the GGX
// distribution carries no 1/pi either.
struct Surf { alb: vec3f, rough: f32, metal: f32, ao: f32 };
// Cook-Torrance specular: GGX distribution, height-correlated Smith visibility, Schlick Fresnel; includes n.l
fn specGGX(n: vec3f, v: vec3f, l: vec3f, a: f32, f0: vec3f) -> vec3f {
  let hv = normalize(v + l);
  let nh = max(dot(n, hv), 0.0);
  let nv = max(dot(n, v), 0.001);
  let nl = max(dot(n, l), 0.0);
  let a2 = a * a;
  let dd = (nh * a2 - nh) * nh + 1.0;
  let vis = 0.5 / max(nl * sqrt(nv * nv * (1.0 - a2) + a2) + nv * sqrt(nl * nl * (1.0 - a2) + a2), 0.0001);
  let f = pow(1.0 - max(dot(l, hv), 0.0), 5.0);
  return (f0 + (vec3f(1.0) - f0) * f) * min(a2 / (dd * dd) * vis * nl, 12.0);
}
// ---- image-based light: the environment is the sky dome of the chapter's time of day (src/gfx/sky.js)
// diffuse: SH9 irradiance (pi-less, cosine-convolved on the CPU)
fn envIrr(n: vec3f, w: f32) -> vec3f {
  if (WMODE == 0u) { return max(F.shD[0].rgb + F.shD[1].rgb * n.y + F.shD[2].rgb * n.z + F.shD[3].rgb * n.x + F.shD[4].rgb * (n.x * n.y) + F.shD[5].rgb * (n.y * n.z) + F.shD[6].rgb * (3.0 * n.z * n.z - 1.0) + F.shD[7].rgb * (n.x * n.z) + F.shD[8].rgb * (n.x * n.x - n.y * n.y), vec3f(0.0)); }
  if (WMODE == 1u) { return max(F.shN[0].rgb + F.shN[1].rgb * n.y + F.shN[2].rgb * n.z + F.shN[3].rgb * n.x + F.shN[4].rgb * (n.x * n.y) + F.shN[5].rgb * (n.y * n.z) + F.shN[6].rgb * (3.0 * n.z * n.z - 1.0) + F.shN[7].rgb * (n.x * n.z) + F.shN[8].rgb * (n.x * n.x - n.y * n.y), vec3f(0.0)); }
  return max(mix(F.shD[0].rgb + F.shD[1].rgb * n.y + F.shD[2].rgb * n.z + F.shD[3].rgb * n.x + F.shD[4].rgb * (n.x * n.y) + F.shD[5].rgb * (n.y * n.z) + F.shD[6].rgb * (3.0 * n.z * n.z - 1.0) + F.shD[7].rgb * (n.x * n.z) + F.shD[8].rgb * (n.x * n.x - n.y * n.y), F.shN[0].rgb + F.shN[1].rgb * n.y + F.shN[2].rgb * n.z + F.shN[3].rgb * n.x + F.shN[4].rgb * (n.x * n.y) + F.shN[5].rgb * (n.y * n.z) + F.shN[6].rgb * (3.0 * n.z * n.z - 1.0) + F.shN[7].rgb * (n.x * n.z) + F.shN[8].rgb * (n.x * n.x - n.y * n.y), w), vec3f(0.0));
}
// specular: the cubemap prefiltered for the roughness (5 mips)
fn envSpec(r: vec3f, rough: f32, w: f32) -> vec3f {
  let lod = rough * 4.0;
  if (WMODE == 0u) { return textureSampleLevel(envD, repSmp, r, lod).rgb; }
  if (WMODE == 1u) { return textureSampleLevel(envN, repSmp, r, lod).rgb; }
  return mix(textureSampleLevel(envD, repSmp, r, lod).rgb, textureSampleLevel(envN, repSmp, r, lod).rgb, w);
}
// sun + diffuse and specular light of the environment + point lights + flashlight
fn shadePBR(p: vec3f, n: vec3f, w: f32, sh: f32, s: Surf) -> vec3f {
  let v = normalize(F.cam.xyz - p);
  let nv = max(dot(n, v), 0.001);
  let f0 = mix(vec3f(0.04), s.alb, s.metal);
  let cd = s.alb * (1.0 - s.metal);
  let a = max(s.rough * s.rough, 0.02);
  let sun = sunCol(w);
  // screen-space occlusion of the last frame, reprojected: SSAO dims the light of the environment, the contact
  // shadow dims the sun; rejected where the depth does not match (something moved in front)
  var ssao = 1.0;
  var contact = 1.0;
  let q = prevUV(p);
  if (F.fx.x > 0.5 && q.z >= 0.0) {
    let o = textureSampleLevel(aoTex, repSmp, q.xy, 0.0);
    let ok = 1.0 - smoothstep(0.02, 0.05, abs(o.b - q.z));
    ssao = mix(1.0, o.r, ok);
    contact = mix(1.0, o.g, ok);
  }
  // reflection of the environment: the prefiltered sky, replaced on smooth surfaces by what the screen-space
  // rays of the last frame found (SSR_SHADER)
  var env = envSpec(reflect(-v, n), s.rough, w);
  if (s.rough < 0.55 && F.fx2.x > 0.5 && q.z >= 0.0) {
    let ss = textureSampleLevel(ssrTex, repSmp, q.xy, 0.0);
    env = mix(env, ss.rgb, ss.a * (1.0 - smoothstep(0.25, 0.55, s.rough)));
  }
  var c = (cd * max(dot(n, F.sunDir.xyz), 0.0) + specGGX(n, v, F.sunDir.xyz, a, f0)) * sun * (sh * contact);
  c += cd * envIrr(n, w) * (F.pbr.y * (0.22 + 0.78 * s.ao) * ssao);
  let ab = textureSampleLevel(brdfLut, repSmp, clamp(vec2f(nv, s.rough), vec2f(0.008), vec2f(0.992)), 0.0).rg;
  c += env * (f0 * ab.x + vec3f(ab.y)) * (F.pbr.y * (0.25 + 0.75 * s.ao) * (0.4 + 0.6 * ssao));
  let wm = select(1u, 2u, w > 0.5);
  for (var i = 0u; i < F.counts.x; i++) {
    let L = F.lights[i];
    if ((u32(L.col.w) & wm) == 0u) { continue; }
    let d = L.pos.xyz - p;
    let d2 = dot(d, d);
    let r = L.pos.w;
    if (d2 >= r * r) { continue; }
    let invD = inverseSqrt(max(d2, 0.0001));
    let att = 1.0 - d2 * invD / r;
    let ld = d * invD;
    c += L.col.rgb * (att * att) * (cd * (max(dot(n, ld), 0.0) * 0.7 + 0.3) * (0.4 + 0.6 * s.ao) + specGGX(n, v, ld, a, f0));
  }
  if (w > 0.5 && F.misc.y > 0.5) {
    let fc = flashCone(p);
    let d = normalize(F.flashPos.xyz - p);
    c += vec3f(1.0, 0.93, 0.78) * F.flashDir.w * fc * (cd * (max(dot(n, d), 0.0) * 0.8 + 0.2) + specGGX(n, v, d, a, f0));
  }
  return c;
}

// noise is only evaluated near the ragged edges (|d - r| < noise amplitude): cheap on mobile
fn worldAt(p: vec3f) -> f32 {
  var w = F.waveP.w;
  if (F.waveP.z > 0.5) {
    var d = distance(p, F.wave.xyz);
    if (abs(d - F.wave.w) < 1.6) { d += (vnoise3(p * 0.35) - 0.5) * 3.0; }
    var inside = d < F.wave.w;
    if (F.wave2.w > 0.0) {
      // a reversed wave: the part its predecessor never reached already shows the target world
      var d2 = distance(p, F.wave2.xyz);
      if (abs(d2 - F.wave2.w) < 1.6) { d2 += (vnoise3(p * 0.35) - 0.5) * 3.0; }
      inside = inside || d2 > F.wave2.w;
    }
    w = select(F.waveP.x, F.waveP.y, inside);
  }
  for (var i = 0u; i < F.counts.y; i++) {
    let b = F.bubbles[i];
    var d = distance(p, b.xyz);
    if (abs(d - b.w) < 0.7) { d += (vnoise3(p * 0.6 + vec3f(7.0)) - 0.5) * 1.2; }
    if (d < b.w) { w = 0.0; }
  }
  return w;
}
fn waveRim(p: vec3f) -> f32 {
  if (F.waveP.z < 0.5) { return 0.0; }
  var d = distance(p, F.wave.xyz);
  if (abs(d - F.wave.w) > 4.0) { return 0.0; }
  d += (vnoise3(p * 0.35) - 0.5) * 3.0;
  return exp(-abs(d - F.wave.w) * 2.2);
}

@group(1) @binding(0) var<storage, read> faces: array<u32>;
struct TV { wp: vec3f, aoD: f32, aoN: f32, dir: u32, edgeMask: u32, mask: u32, matD: u32, matN: u32, du: f32, dv: f32 };
fn decodeTerrain(vi: u32) -> TV {
  // indexed quads: vertex index = quad * 4 + corner (the index buffer makes the two triangles)
  let fi = vi >> 2u;
  let w0 = faces[fi * 3u]; let w1 = faces[fi * 3u + 1u]; let w2 = faces[fi * 3u + 2u];
  var t: TV;
  t.dir = (w0 >> 15u) & 7u;
  t.edgeMask = (w2 >> 16u) & 15u;
  t.mask = (w0 >> 18u) & 3u;
  t.du = f32(((w0 >> 20u) & 31u) + 1u);
  t.dv = f32(((w0 >> 25u) & 31u) + 1u);
  let aoDw = w1 & 255u; let aoNw = (w1 >> 8u) & 255u;
  t.matD = (w1 >> 16u) & 255u; t.matN = (w1 >> 24u) & 255u;
  let a0 = aoDw & 3u; let a1 = (aoDw >> 2u) & 3u; let a2 = (aoDw >> 4u) & 3u; let a3 = (aoDw >> 6u) & 3u;
  // AO-aware diagonal: rotating the corners by one flips the triangulation of this quad
  let c = (vi + select(0u, 1u, a0 + a2 > a1 + a3)) & 3u;
  let lp = vec3f(f32(w0 & 31u), f32((w0 >> 5u) & 31u), f32((w0 >> 10u) & 31u)) + faceOffset(t.dir, c, t.du, t.dv);
  t.wp = (chunkOrg[w2 & 0xffffu].xyz + lp) * 0.125;
  t.aoD = f32((aoDw >> (c * 2u)) & 3u) / 3.0;
  t.aoN = f32((aoNw >> (c * 2u)) & 3u) / 3.0;
  return t;
}
struct TOut {
  @builtin(position) pos: vec4f,
  @location(0) wp: vec3f,
  @location(1) ao: vec4f,   // dream AO, nightmare AO, two palette noises (per vertex: low frequency)
  @location(2) @interpolate(flat) info: vec4u,
  @location(3) quadUV: vec2f,
};
@vertex fn vsTerrain(@builtin(vertex_index) vi: u32) -> TOut {
  let t = decodeTerrain(vi);
  let fl = u32(mats[t.matD * 2u].w) | u32(mats[t.matN * 2u].w);
  var wp = t.wp;
  if ((fl & 4u) != 0u && u32(mats[t.matD * 2u + 1u].w) != 21u) { // foliage sways, window glass does not
    let tt = F.cam.w;
    wp.x += sin(tt * 1.3 + wp.z * 0.45 + wp.y * 0.3) * 0.035;
    wp.z += cos(tt * 1.1 + wp.x * 0.4) * 0.03;
  }
  let fi = vi >> 2u;
  let w1 = faces[fi * 3u + 1u];
  let aoDw = w1 & 255u;
  let a0 = aoDw & 3u; let a1 = (aoDw >> 2u) & 3u; let a2 = (aoDw >> 4u) & 3u; let a3 = (aoDw >> 6u) & 3u;
  let c = (vi + select(0u, 1u, a0 + a2 > a1 + a3)) & 3u;
  var o: TOut;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.wp = wp;
  o.ao = vec4f(t.aoD, t.aoN, textureSampleLevel(noise3, repSmp, wp * vec3f(0.016, 0.04, 0.016), 0.0).r,
    textureSampleLevel(noise3, repSmp, wp * vec3f(0.07, 0.1, 0.07) + vec3f(0.37), 0.0).r);
  o.info = vec4u(t.dir | (t.edgeMask << 3u) | (u32(t.du) << 8u) | (u32(t.dv) << 16u), t.mask, t.matD, t.matN);
  o.quadUV = vec2f(cuOf(c) * t.du, cvOf(c) * t.dv);
  return o;
}
// water: corner offsets from the mesher make ramps at steps; ao.x carries the foam amount
@vertex fn vsWater(@builtin(vertex_index) vi: u32) -> TOut {
  let fi = vi / 6u;
  let k = vi - fi * 6u;
  let w0 = faces[fi * 3u]; let w1 = faces[fi * 3u + 1u]; let w2 = faces[fi * 3u + 2u];
  let dir = (w0 >> 15u) & 7u;
  let c = quadCorner(k);
  var lp = vec3f(f32(w0 & 31u), f32((w0 >> 5u) & 31u), f32((w0 >> 10u) & 31u)) + faceOffset(dir, c, 1.0, 1.0);
  let f = (w1 >> (c * 2u)) & 3u;
  if (f == 1u) { lp.y -= 0.5; } else if (f == 2u) { lp.y += 0.5; }
  var wp = (chunkOrg[w2 & 0xffffu].xyz + lp) * 0.125;
  var o: TOut;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.wp = wp;
  // subtle foam at the foot of each little fall
  o.ao = vec4f(select(0.0, 0.42, f == 2u && dir == 2u), 0.0, 0.5, 0.5);
  o.info = vec4u(dir, 1u, (w1 >> 16u) & 255u, 0u);
  o.quadUV = vec2f(cuOf(c), cvOf(c));
  return o;
}
struct SOut { @builtin(position) pos: vec4f, @location(0) wp: vec3f, @location(1) @interpolate(flat) mask: u32, @location(2) @interpolate(flat) mat: vec3u };
@vertex fn vsShadow(@builtin(vertex_index) vi: u32) -> SOut {
  let t = decodeTerrain(vi);
  var o: SOut;
  o.pos = F.shadowMat * vec4f(t.wp, 1.0);
  o.wp = t.wp;
  o.mask = t.mask;
  o.mat = vec3u(t.matD, t.matN, t.dir);
  return o;
}
@fragment fn fsShadowMasked(i: SOut) {
  let w = worldAt(i.wp);
  if ((i.mask & select(1u, 2u, w > 0.5)) == 0u) { discard; }
}
// dappled shadows from alpha-cut leaves
@fragment fn fsShadowLeaf(i: SOut) {
  let w = wAt(i.wp);
  let night = w > 0.5;
  if (WMODE == 2u && (i.mask & select(1u, 2u, night)) == 0u) { discard; }
  let mat = select(i.mat.x, i.mat.y, night);
  let h = hash3i(vec3i(floor(i.wp * 8.0 - nrmOf(i.mat.z) * 0.5)));
  if (atlasTexel(mat, i.mat.z, i.wp, h).a < 0.5) { discard; }
}

// Atlas tiles are ATILE x ATILE texels (atlas.js), baked on the CPU (3 face classes x 4 variants per material).
const ATILE = 64u;
const ATILEF = 64.0;
// Cut-out materials: foliage one tile per voxel face, window glass one per 0.5 m; one textureLoad per pixel.
fn atlasTexel(mat: u32, dir: u32, wp: vec3f, h: f32) -> vec4f {
  let glass = u32(mats[mat * 2u + 1u].w) == 21u; // window glass: one tile per 0.5 m like the terrain detail
  let lv = wp * select(8.0, 2.0, glass);
  var s = 0.0;
  var t = 0.0;
  if (dir == 2u || dir == 3u) { s = fract(lv.x); t = fract(lv.z); }
  else if (dir < 2u) { s = fract(lv.z); t = fract(lv.y); }
  else { s = fract(lv.x); t = fract(lv.y); }
  let ts = u32(min(floor(s * ATILEF), ATILEF - 1.0));
  let tt = u32(min(floor(t * ATILEF), ATILEF - 1.0));
  let fc = select(1u, select(2u, 0u, dir == 2u), dir == 2u || dir == 3u);
  let vr = u32(fract(h * 7.31) * 4.0) & 3u;
  return textureLoad(atlas, vec2u((fc * 4u + vr) * ATILE + ts, mat * ATILE + ATILE - 1u - tt), 0);
}
fn wAt(p: vec3f) -> f32 {
  if (WMODE == 2u) { return worldAt(p); }
  return f32(WMODE);
}
struct TerrainRes { col: vec3f, n: vec3f, ao: f32, refl: bool };
fn terrainColor(i: TOut, night: bool, w: f32) -> TerrainRes {
  let dir = i.info.x & 7u;
  let edgeMask = (i.info.x >> 3u) & 15u;
  let duF = max(f32((i.info.x >> 8u) & 255u), 1.0);
  let dvF = max(f32((i.info.x >> 16u) & 255u), 1.0);
  let mat = select(i.info.z, i.info.w, night);
  let m0 = mats[mat * 2u];
  let m1 = mats[mat * 2u + 1u];
  let baseN = nrmOf(dir);
  var n = baseN;
  let blockCoord = vec3i(floor(i.wp * 8.0 - baseN * 0.5));
  let h = hash3i(blockCoord);
  let vk = 1.0 + (h - 0.5) * 0.55 * m1.y;
  let dist = distance(i.wp, F.cam.xyz);
  let pat = u32(m1.w);
  let ax = dir >> 1u;
  // ─── Discrete per-cube solid brightness step (emphasizes separate individual cubes) ───
  let vStyle = u32(F.grass.w + 0.5);
  let vClusterH = hash3i(vec3i(blockCoord.x >> 2, blockCoord.y >> 2, blockCoord.z >> 2));
  let voxQuantShade = 0.90 + floor(h * 5.0) * 0.048;
  let clusterShade = 0.95 + floor(vClusterH * 3.0) * 0.045;

  // ─── Per-voxel UV inside merged or single quads ───
  let uQuad = fract(i.quadUV.x);
  let vQuad = fract(i.quadUV.y);
  let voxelEdge = min(min(uQuad, 1.0 - uQuad), min(vQuad, 1.0 - vQuad));
  let nearFade = 1.0 - smoothstep(5.0, 16.0, dist);

  // Subtle physical edge bevel for single voxel cubes (fades out smoothly to prevent Moiré lines)
  var cubeOcc = 1.0;
  var cubeRidge = 1.0;
  if (voxelEdge < 0.11 && nearFade > 0.01) {
    let edgeT = (1.0 - voxelEdge / 0.11) * nearFade;
    cubeOcc *= mix(1.0, 0.94, edgeT);
  }

  // Solid albedo per physical voxel; the micro detail comes from the atlas below
  let cubeCol = m0.rgb * (0.96 + h * 0.08);
  var albedo = cubeCol * vk * clusterShade * voxQuantShade * cubeRidge;

  // Real 3D Step Edge Shading along macro 90-degree block turns
  var stepEdgeDist = 1.0;
  if ((edgeMask & 1u) != 0u) { stepEdgeDist = min(stepEdgeDist, i.quadUV.x); }
  if ((edgeMask & 2u) != 0u) { stepEdgeDist = min(stepEdgeDist, max(0.0, duF - i.quadUV.x)); }
  if ((edgeMask & 4u) != 0u) { stepEdgeDist = min(stepEdgeDist, i.quadUV.y); }
  if ((edgeMask & 8u) != 0u) { stepEdgeDist = min(stepEdgeDist, max(0.0, dvF - i.quadUV.y)); }
  let edgeDarken = mix(select(0.96, 1.02, baseN.y > 0.5), 1.0, smoothstep(0.0, 0.12, stepEdgeDist));
  albedo *= edgeDarken;

  // On vertical macro steps of grass cubes, show natural underlying soil tone
  if (ax != 1u && (pat == 1u || pat == 14u || pat == 17u)) {
    let soilShade = 0.90 + floor(h * 4.0) * 0.05;
    albedo = mix(albedo, vec3f(0.30, 0.20, 0.12) * soilShade, 0.22);
  }

  // Quantized macro-biome tint (sampled per-cube so each cube remains a pure solid color)
  let n1 = i.ao.z;
  let n2 = i.ao.w;
  if (pat == 1u || pat == 14u || pat == 6u || pat == 16u || pat == 17u) {
    albedo *= mix(vec3f(1.08, 1.03, 0.86), vec3f(0.88, 1.02, 0.94), smoothstep(0.25, 0.75, n1)) * (0.92 + n2 * 0.16);
  } else {
    albedo *= mix(vec3f(1.03, 1.0, 0.95), vec3f(0.94, 0.98, 1.02), n1) * (0.92 + n2 * 0.16);
  }

  // ─── Vertical Step Risers: Per-Voxel-Cube Soil & Stone Variation (no sub-voxel horizontal striping) ───
  if (ax != 1u) {
    let voxRow = u32(blockCoord.y) & 7u;
    let colShift = u32(vClusterH * 2.0);
    if (pat == 1u || pat == 14u || pat == 17u) {
      if (voxRow >= 5u + (colShift & 1u)) {
        albedo *= 1.01;
      } else if (voxRow >= 2u) {
        albedo *= vec3f(0.97, 0.94, 0.90);
      } else {
        let pebble = select(0.96, 1.05, h > 0.72);
        albedo *= vec3f(0.94, 0.92, 0.90) * pebble;
      }
    } else if (pat == 2u || pat == 12u || pat == 11u) {
      if (voxRow >= 6u) {
        albedo *= vec3f(0.95, 0.93, 0.90);
      } else if (voxRow < 2u) {
        let pebble = select(0.95, 1.05, h > 0.68);
        albedo *= vec3f(0.94, 0.92, 0.90) * pebble;
      }
    } else if (pat == 3u || pat == 15u || pat == 18u) {
      let strataIdx = floor(f32(blockCoord.y >> 1) + (vClusterH - 0.5) * 2.0);
      let strataHash = fract(sin(strataIdx * 12.9898) * 43758.5453);
      let strataTint = mix(vec3f(0.93, 0.91, 0.88), vec3f(1.06, 1.04, 1.01), strataHash);
      albedo *= mix(vec3f(1.0), strataTint, 0.30);
    } else if (pat == 4u || pat == 5u || pat == 7u || pat == 24u) {
      let horizCoord = select(i.wp.x, i.wp.z, ax == 0u);
      let fiberIdx = floor(horizCoord * 16.0);
      let fiberHash = fract(sin(fiberIdx * 37.719 + floor(i.wp.y * 4.0) * 7.13) * 43758.5453);
      albedo *= mix(0.93, 1.04, fiberHash);
    }
    albedo *= 0.96;
  } else {
    albedo *= 1.02;
  }

  // ─── Blast Scorch & Soot Voxels on Fractured Crater Surfaces ───
  if (pat == 18u) {
    let soot = 0.56 + 0.44 * floor(h * 4.0) / 3.0;
    albedo *= vec3f(soot * 0.78, soot * 0.73, soot * 0.70);
  }

  if ((pat == 3u || pat == 15u) && baseN.y > 0.5) {
    let mossPatch = step(0.62, n1 + (vClusterH - 0.5) * 0.18);
    albedo = mix(albedo, vec3f(0.11, 0.22, 0.06) * voxQuantShade, mossPatch * 0.65);
  }
  let flags = u32(m0.w);
  // Combine macro Concave Corner Cavity AO with per-cube 3D step occlusion
  let rawAo = select(i.ao.x, i.ao.y, night);
  let macroAo = mix(rawAo, pow(clamp(rawAo, 0.03, 1.0), 1.28), select(0.50, 0.80, vStyle == 2u));
  var ao = clamp(macroAo * cubeOcc, 0.04, 1.0);
  // ─── PBR surface: material values, refined near the camera by the atlas (a 0.5 m tile of ATILE x ATILE texels:
  // colour relative to the material mean, relief from the height channel, roughness / metal / occlusion / wet mask)
  var rough = m1.z;
  var metal = f32((flags >> 8u) & 15u) / 15.0;
  var wetMask = 0.5;
  let detail = 1.0 - smoothstep(10.0, 26.0, dist);
  // atlas mip level: texels of the 0.5 m tile per screen pixel (each level halves every tile inside the atlas)
  let fw = max(length(dpdx(i.wp)), length(dpdy(i.wp))) * 2.0 * ATILEF;
  let mip = u32(clamp(floor(log2(max(fw, 1.0))), 0.0, 4.0));
  if (detail > 0.01) {
    let lv = i.wp * 2.0;
    var st = lv.xy;
    var ua = vec3f(1.0, 0.0, 0.0);
    var va = vec3f(0.0, 1.0, 0.0);
    if (ax == 1u) { st = lv.xz; va = vec3f(0.0, 0.0, 1.0); } else if (ax == 0u) { st = lv.zy; ua = vec3f(0.0, 0.0, 1.0); }
    let ts = u32(min(fract(st.x) * ATILEF, ATILEF - 1.0));
    let tt = u32(min(fract(st.y) * ATILEF, ATILEF - 1.0));
    let fcl = select(1u, select(2u, 0u, dir == 2u), ax == 1u);
    let vr = u32(hash3i(vec3i(floor(lv - baseN * 0.02))) * 4.0) & 3u;
    let org = vec2u((fcl * 4u + vr) * ATILE, mat * ATILE);
    let tx = textureLoad(atlas, (org + vec2u(ts, ATILE - 1u - tt)) >> vec2u(mip), mip);
    let pb = textureLoad(atlasPbr, (org + vec2u(ts, ATILE - 1u - tt)) >> vec2u(mip), mip);
    albedo *= mix(vec3f(1.0), tx.rgb * 4.0, detail); // the atlas stores colour / material mean x 0.25
    rough = mix(rough, pb.r, detail);
    metal = mix(metal, pb.g, detail);
    ao *= mix(1.0, pb.b, detail);
    wetMask = pb.a;
    if ((flags & 4u) == 0u) { // foliage keeps its cut-out mask in alpha: no relief there
      let st1 = 1u << mip; // the neighbouring texel of this level
      let hs = textureLoad(atlas, (org + vec2u((ts + st1) % ATILE, ATILE - 1u - tt)) >> vec2u(mip), mip).a;
      let ht = textureLoad(atlas, (org + vec2u(ts, ATILE - 1u - (tt + st1) % ATILE)) >> vec2u(mip), mip).a;
      n = normalize(baseN - (ua * (hs - tx.a) + va * (ht - tx.a)) * (0.6 * detail));
    }
  }
  let por = f32((flags >> 12u) & 15u) / 15.0;
  let wet = F.pbr.x * select(0.4, 1.0, baseN.y > 0.5);
  let hold = wet * (1.0 - 0.6 * por); // porous ground soaks the water up instead of keeping a film
  if (wet > 0.001) {
    let film = hold * mix(0.3, 1.0, wetMask); // the film stands in the hollows: smooth and level
    albedo *= mix(1.0, 0.6, wet * por);
    rough = mix(rough, 0.08, film);
    n = normalize(mix(n, baseN, film * 0.85));
  }
  let sh = shadowSun(i.wp, baseN, dist < 16.0); // 4-tap filter only near the camera
  var c = shadePBR(i.wp, n, w, sh, Surf(albedo, rough, metal, ao));
  if ((flags & 4u) != 0u && pat != 21u) {
    let back = max(dot(-n, F.sunDir.xyz), 0.0) * 0.36 + 0.1;
    c += albedo * sunCol(w) * back * sh;
  }
  if ((flags & 16u) != 0u) { c += albedo * m1.x; }
  if ((flags & 64u) != 0u) { c = mix(c, vec3f(0.5, 1.6, 2.2), clamp(flashCone(i.wp) * 1.5, 0.0, 1.0)); }
  // Mode 3: Binary Greedy Meshing & Voxel Grid Inspector overlay
  if (vStyle == 3u && (voxelEdge < 0.035 || stepEdgeDist < 0.04)) {
    c = mix(c, select(vec3f(0.06, 0.82, 0.58), vec3f(0.98, 0.58, 0.14), stepEdgeDist < 0.04), 0.78);
  }
  c += vec3f(1.0, 0.32, 0.22) * waveRim(i.wp) * 1.4;
  c = flatFog(c, i.wp, w);
  // Output macro block normal baseN to G-Buffer so screen-space 1px normal crease filter never flickers on ground cubes
  // reflective for the screen-space rays: smooth materials as a whole (not texel by texel) and wet surfaces
  return TerrainRes(c, baseN, ao, m1.z < 0.3 || hold > 0.3);
}
// constant-world (WMODE 0/1) or dynamic without discard: early-Z / HSR friendly + G-Buffer MRT output
@fragment fn fsTerrain(i: TOut) -> GFragOut {
  let w = wAt(i.wp);
  let night = w > 0.5;
  let res = terrainColor(i, night, w);
  return GFragOut(vec4f(res.col, 1.0), vec4f(res.n * 0.5 + 0.5, gbA(res.ao, false, res.refl, false)));
}
// foliage: alpha-cut individual leaves from the atlas, both sides lit
@fragment fn fsLeaf(i: TOut, @builtin(front_facing) ff: bool) -> GFragOut {
  let w = wAt(i.wp);
  let night = w > 0.5;
  if (WMODE == 2u && (i.info.y & select(1u, 2u, night)) == 0u) { discard; }
  let dir = i.info.x & 7u;
  let mat = select(i.info.z, i.info.w, night);
  let h = hash3i(vec3i(floor(i.wp * 8.0 - nrmOf(dir) * 0.5)));
  if (atlasTexel(mat, dir, i.wp, h).a < 0.5) { discard; }
  var o = i;
  if (!ff) { o.info.x = (o.info.x & ~7u) | (dir ^ 1u); }
  let res = terrainColor(o, night, w);
  return GFragOut(vec4f(res.col, 1.0), vec4f(res.n * 0.5 + 0.5, gbA(res.ao, true, false, false)));
}
@fragment fn fsTerrainMasked(i: TOut) -> GFragOut {
  let w = worldAt(i.wp);
  let night = w > 0.5;
  if ((i.info.y & select(1u, 2u, night)) == 0u) { discard; }
  let res = terrainColor(i, night, w);
  return GFragOut(vec4f(res.col, 1.0), vec4f(res.n * 0.5 + 0.5, gbA(res.ao, false, res.refl, false)));
}
@fragment fn fsWater(i: TOut) -> GFragOut {
  let w = wAt(i.wp);
  if (w > 0.5) { discard; }
  let t = F.cam.w;
  let q = i.wp.xz;
  // Hardware trilinear 3D noise fetch instead of 3x 8-corner hash evaluations (cuts ALU by 75%)
  let uvw = vec3f(q.x * 0.05 + t * 0.012, t * 0.008, q.y * 0.05 + t * 0.007);
  let n0 = textureSampleLevel(noise3, repSmp, uvw, 0.0).r;
  let nx = textureSampleLevel(noise3, repSmp, uvw + vec3f(0.015, 0.0, 0.0), 0.0).r - n0;
  let nz = textureSampleLevel(noise3, repSmp, uvw + vec3f(0.0, 0.0, 0.015), 0.0).r - n0;
  var n = normalize(vec3f(-nx * 3.2, 1.0, -nz * 3.2));
  let side = i.info.x != 2u;
  if (side) { n = nrmOf(i.info.x); }
  let v = normalize(F.cam.xyz - i.wp);
  let oneMinusNoV = 1.0 - max(dot(n, v), 0.0);
  let o2 = oneMinusNoV * oneMinusNoV;
  let fres = 0.02 + 0.98 * (o2 * o2 * oneMinusNoV);
  let sh = shadowSun(i.wp, vec3f(0.0, 1.0, 0.0), false);
  let r = reflect(-v, n);
  // reflection: the sky of the time of day, replaced by what the screen-space rays of the last frame found
  var refl = envSpec(vec3f(r.x, abs(r.y), r.z), 0.06, w);
  let pq = prevUV(i.wp);
  if (F.fx2.x > 0.5 && pq.z >= 0.0) {
    let ss = textureSampleLevel(ssrTex, repSmp, pq.xy, 0.0);
    refl = mix(refl, ss.rgb, ss.a);
  }
  let spec = specGGX(n, v, F.sunDir.xyz, 0.03, vec3f(0.02)) * sh;
  let deep = vec3f(0.02, 0.11, 0.14) * (F.skyD.rgb * 1.4 + F.sunD.rgb * 0.25 * sh);
  var col = mix(deep, refl, fres) + F.sunD.rgb * spec;
  var a = mix(0.56, 0.88, fres);
  let fn1 = textureSampleLevel(noise3, repSmp, vec3f(q.x * 0.22 + t * 0.04, t * 0.06, q.y * 0.22 - t * 0.03), 0.0).r;
  let foam = smoothstep(0.28, 0.65, i.ao.x * (0.45 + fn1 * 0.65));
  col = mix(col, vec3f(0.82, 0.90, 0.94) * (F.skyD.rgb * 1.1 + F.sunD.rgb * 0.35 * sh), foam * 0.28);
  a = max(a, foam * 0.42);
  if (side) {
    let fl = 0.5 + 0.5 * sin(i.wp.y * 14.0 + t * 15.0 + fn1 * 4.0);
    col = mix(col, vec3f(0.78, 0.88, 0.92) * (F.skyD.rgb * 1.15 + F.sunD.rgb * 0.3), 0.18 + 0.2 * fl);
    a = 0.65;
  }
  col += vec3f(1.0, 0.32, 0.22) * waveRim(i.wp);
  col = flatFog(col, i.wp, w);
  return GFragOut(vec4f(col * a, a), vec4f(n * 0.5 + 0.5, gbA(1.0, false, true, false)));
}

// ONE WIND for everything that sways: grass blades, plants and flowers (PART.SWAY), tree crowns and foliage cards.
// xz: a world position. Returns xy = the steady push along the wind with gust fronts rolling across the land
// (metres of lean per metre of height, before the material's own response), zw = a quick flutter (unit amplitude).
// The particles drift with the same vector (SimU.wind), so dust, leaves and the grass agree.
fn windAt(xz: vec2f) -> vec4f {
  let t = F.cam.w;
  let wv = F.wind.xy;
  let sp = length(wv);
  let dirW = select(vec2f(1.0, 0.0), wv / max(sp, 0.0001), sp > 0.0001);
  let along = dot(xz, dirW);
  let across = dot(xz, vec2f(-dirW.y, dirW.x));
  // gust fronts: bands across the wind that travel downwind; a slow swell makes some gusts stronger than others
  let front = 0.5 + 0.5 * sin(along * 0.23 - t * 1.15 + sin(across * 0.07 + t * 0.21) * 1.6);
  let gust = (0.35 + 0.65 * front * front) * (0.8 + 0.2 * sin(t * 0.37 + across * 0.03)) * F.wind.z;
  let flutter = vec2f(sin(t * 1.9 + xz.x * 0.8 + xz.y * 0.3), cos(t * 1.4 + xz.y * 0.7 + xz.x * 0.2));
  return vec4f(dirW * (sp * gust), flutter * (0.35 + 0.65 * gust));
}
@group(1) @binding(0) var<uniform> D: vec4u;
// what the prop fragment shaders work with
struct POut { pos: vec4f, wp: vec3f, n: vec3f, col: vec3f, ao: f32, mask: u32, fl: u32, lv: vec3f, quv: vec4f, vsz: f32, tu: vec3f, tv: vec3f, rgb: u32, extra: f32 };
// what actually travels from the vertex to the fragment stage, packed (mobile GPUs write every
// varying to memory): flags/mask/colour/voxel size in one flat vec4u, normal + U/V axes as 10:10:10
struct PV {
  @builtin(position) pos: vec4f,
  @location(0) wp: vec3f,
  @location(1) lv: vec3f,
  @location(2) quv: vec4f,
  @location(3) ao: f32,
  @location(4) @interpolate(flat) info: vec4u,
  @location(5) @interpolate(flat) frame: vec3u,
  @location(6) @interpolate(flat) extra: f32,
};
fn pk10(v: vec3f) -> u32 { let q = vec3u(clamp(v * 0.5 + 0.5, vec3f(0.0), vec3f(1.0)) * 1023.0 + 0.5); return q.x | (q.y << 10u) | (q.z << 20u); }
fn uk10(p: u32) -> vec3f { return vec3f(f32(p & 1023u), f32((p >> 10u) & 1023u), f32((p >> 20u) & 1023u)) * (2.0 / 1023.0) - 1.0; }
fn packP(o: POut) -> PV {
  var v: PV;
  v.pos = o.pos; v.wp = o.wp; v.lv = o.lv; v.quv = o.quv; v.ao = o.ao;
  v.info = vec4u(o.fl, o.mask, o.rgb, bitcast<u32>(o.vsz));
  v.frame = vec3u(pk10(normalize(o.n)), pk10(o.tu), pk10(o.tv));
  v.extra = o.extra;
  return v;
}
fn unpackP(v: PV) -> POut {
  var o: POut;
  o.pos = v.pos; o.wp = v.wp; o.lv = v.lv; o.quv = v.quv; o.ao = v.ao;
  o.fl = v.info.x; o.mask = v.info.y; o.rgb = v.info.z; o.vsz = bitcast<f32>(v.info.w);
  let rgb = vec3f(f32((o.rgb >> 16u) & 255u), f32((o.rgb >> 8u) & 255u), f32(o.rgb & 255u)) / 255.0;
  o.col = pow(rgb, vec3f(2.2));
  o.n = uk10(v.frame.x); o.tu = uk10(v.frame.y); o.tv = uk10(v.frame.z);
  o.extra = v.extra;
  return o;
}
@vertex fn vsProp(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> PV { return packP(propOut(vi, ii)); }
// tree shadows (shadow cull pass fills vis/args for shadow casters)
struct PShadOut {
  @builtin(position) pos: vec4f,
  @location(0) quv: vec4f,
  @location(1) @interpolate(flat) info: vec2u,
};
// tree shadows (the shadow cull pass fills vis/args for shadow casters); the foliage cards cut their leaf shapes
// out of the shadow map (fsPropShadow), so the crowns cast dappled shadows instead of rectangles
@vertex fn vsPropShadow(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> PShadOut {
  let o = propOut(vi, ii);
  return PShadOut(F.shadowMat * vec4f(o.wp, 1.0), o.quv, vec2u(o.fl, bitcast<u32>(o.vsz)));
}
fn propOut(vi: u32, ii: u32) -> POut {
  let mi = minfo[D.x];
  let inst = insts[vis[mi.visBase + ii]];
  // v1 faces: 2 words, one voxel each; v2 faces: 3 words, merged quads of chunky models or curved foliage cards
  let v2 = (mi.flags & 256u) != 0u;
  // indexed quads (vertex index = quad * 4 + corner)
  let fo = mi.faceStart + (vi >> 2u) * select(2u, 3u, v2);
  let w0 = mfaces[fo];
  let w1 = mfaces[fo + 1u];
  var dir = (w0 >> 24u) & 7u;
  var part = (w0 >> 27u) & 15u;
  var em = w0 >> 31u;
  var vpos = vec3f(f32(w0 & 255u), f32((w0 >> 8u) & 255u), f32((w0 >> 16u) & 255u));
  var du = 1.0; var dv = 1.0;
  var edgeMask = 15u;
  var cardMeta = 0u;
  if (v2) {
    let w2 = mfaces[fo + 2u];
    vpos = vec3f(f32(w0 & 1023u), f32((w0 >> 10u) & 4095u), f32((w0 >> 22u) & 1023u));
    dir = w2 & 7u; part = (w2 >> 3u) & 15u; em = (w2 >> 7u) & 1u;
    du = f32(((w2 >> 8u) & 255u) + 1u); dv = f32(((w2 >> 16u) & 255u) + 1u);
    cardMeta = (w2 >> 24u) & 255u;
    edgeMask = cardMeta & 15u;
  }
  // Full 8-bit 4-corner Voxel Cavity AO preserved for both v1 and v2 greedy quads
  let aow = w1 >> 24u;
  let flip = (aow & 3u) + ((aow >> 4u) & 3u) > ((aow >> 2u) & 3u) + ((aow >> 6u) & 3u);
  let c = (vi + select(0u, 1u, flip)) & 3u;
  let cu = cuOf(c);
  let cv = cvOf(c);
  let vc = vpos + vec3f(0.5);
  // thin far geometry (branches, wires, lone voxels): a face narrower than a pixel is widened to one pixel around
  // its centre (at most 3x), so it does not flicker in and out between frames
  let ppv = mi.pivot.w * length(inst.m0.xyz) * F.opt.x / max(distance(vec3f(inst.m0.w, inst.m1.w, inst.m2.w), F.cam.xyz), 0.5);
  let ku = clamp(1.0 / (ppv * du), 1.0, 3.0);
  let kv = clamp(1.0 / (ppv * dv), 1.0, 3.0);
  var lp = vpos + axv(dir >> 1u) * nposOf(dir) + axv(uaxOf(dir)) * ((cu - 0.5) * du * ku + 0.5 * du) + axv(vaxOf(dir)) * ((cv - 0.5) * dv * kv + 0.5 * dv);
  var quv = vec4f(cu * du, cv * dv, du, dv);
  var ua = axv(uaxOf(dir));
  var va = axv(vaxOf(dir));
  if (part == 15u) {
    // a thin branch: the one-voxel line becomes a rod of k voxels across (a few centimetres near the camera; never
    // thinner than about a pixel, so far twigs do not flicker); faces move toward the voxel centre line
    let k = clamp(1.6 / max(ppv, 0.001), 0.28, 1.0);
    lp += axv(dir >> 1u) * ((nposOf(dir) - 0.5) * (k - 1.0));
    if (du < 1.5) { lp += ua * ((cu - 0.5) * (k - 1.0)); }
    if (dv < 1.5) { lp += va * ((cv - 0.5) * (k - 1.0)); }
    part = 11u; // shaded as wood
  }
  var flexS = 0.0;
  var flexT = 0.0;
  var radDir = vec3f(1.0, 0.0, 0.0);
  var sideDir = vec3f(0.0, 0.0, 1.0);
  if (part == 10u && v2 && cardMeta > 0u) {
    // Doubly-curved 3x2 botanical foliage surface (wingMode 1..6 = 3 longitudinal arch segments x 2 gull-wings; 7 = cross-volume sheet)
    let wingMode = dir & 7u;
    var uUV = cu;
    var vUV = cv;
    if (wingMode >= 1u && wingMode <= 6u) {
      let vSeg = (wingMode - 1u) >> 1u;
      let uSeg = (wingMode - 1u) & 1u;
      uUV = (f32(uSeg) + cu) * 0.5;
      vUV = (f32(vSeg) + cv) * 0.33333334;
    }
    let azIdx = cardMeta & 31u;
    let pitchIdx = (cardMeta >> 5u) & 7u;
    let ang = f32(azIdx) * 0.19634954;
    radDir = vec3f(cos(ang), 0.0, sin(ang));
    sideDir = vec3f(-sin(ang), 0.0, cos(ang));
    flexS = (uUV - 0.5) * 2.0;
    flexT = vUV;
    var slope0 = 0.12;
    var archDrop = 0.68;
    switch (pitchIdx) {
      case 0u: { slope0 = 0.68; archDrop = 0.30; }
      case 1u: { slope0 = 0.40; archDrop = 0.48; }
      case 2u: { slope0 = 0.20; archDrop = 0.58; }
      case 3u: { slope0 = 0.04; archDrop = 0.68; }
      case 4u: { slope0 = -0.14; archDrop = 0.78; }
      case 5u: { slope0 = -0.32; archDrop = 0.88; }
      case 6u: { slope0 = -0.58; archDrop = 0.96; }
      default: { slope0 = -0.96; archDrop = 0.65; }
    }
    var radReach = dv * (flexT - 0.12 * flexT * flexT * flexT);
    if (pitchIdx >= 6u) {
      radReach = dv * (0.46 * flexT + 0.14 * flexT * flexT);
    }
    let yLong = dv * (slope0 * flexT - archDrop * flexT * flexT);
    var latSpan = du * 0.5 * (0.58 + 0.54 * sin(flexT * 2.55));
    var yWing = -du * 0.22 * abs(flexS) * (0.42 + 0.58 * flexT);
    if (wingMode == 7u) {
      let bank = select(-0.34, 0.34, (azIdx & 1u) == 0u);
      latSpan = du * 0.5;
      yWing = flexS * du * bank - 0.12 * dv * flexT * flexT;
    }
    lp = vpos + radDir * radReach + sideDir * (flexS * latSpan) + vec3f(0.0, yLong + yWing, 0.0);
    quv = vec4f(uUV * du, vUV * dv, du, dv);
    ua = sideDir;
    va = normalize(radDir + vec3f(0.0, slope0 - 2.0 * archDrop * flexT, 0.0));
  }
  let lvox = lp;
  var p = (lp - mi.pivot.xyz) * mi.pivot.w;
  var nrm = nrmOf(dir);
  if (part == 10u && v2 && cardMeta > 0u) {
    // Smooth canopy-outward + umbrella-arch normal eliminates flat-card intersection seams
    nrm = normalize(vec3f(
      p.x * 0.72 + radDir.x * (0.42 + 0.45 * flexT) + sideDir.x * (flexS * 0.32),
      max(0.36, 0.88 - 0.46 * flexT),
      p.z * 0.72 + radDir.z * (0.42 + 0.45 * flexT) + sideDir.z * (flexS * 0.32)
    ));
  }
  let t = F.cam.w;
  if (part == 1u || part == 2u) {
    let s = select(1.0, -1.0, part == 2u);
    let amp = select(1.05, 0.45, inst.extra > 25.0);
    let a = (sin(t * inst.extra + inst.phase) * 0.55 + 0.25) * amp * s;
    let ca = cos(a); let sa = sin(a);
    p = vec3f(p.x * ca - p.y * sa, p.x * sa + p.y * ca, p.z);
    nrm = vec3f(nrm.x * ca - nrm.y * sa, nrm.x * sa + nrm.y * ca, nrm.z);
  } else if (part == 4u) {
    p.x += sin(t * 11.0 + p.y * 40.0 + inst.phase) * 0.012;
    p.z += cos(t * 9.0 + p.y * 33.0) * 0.012;
  } else if (part == 12u) {
    // fragments hovering around the crowns
    p.y += sin(t * 0.7 + vc.x * 0.31 + vc.z * 0.17 + inst.phase) * 0.06;
  }
  let lp4 = vec4f(p, 1.0);
  var wp = vec3f(dot(inst.m0, lp4), dot(inst.m1, lp4), dot(inst.m2, lp4));
  // the wind (windAt): in world space, so every plant and tree leans the same way whatever its rotation
  let isTree = (mi.flags & 4u) != 0u;
  if (part == 3u || (isTree && (part == 10u || part == 11u))) {
    let hgt = max(p.y, 0.0); // metres above the base of the model
    let wa = windAt(vec2f(inst.m0.w, inst.m2.w)); // the whole plant or tree in one gust
    if (part == 3u) {
      wp += vec3f(wa.x * 0.2 + wa.z * 0.06, 0.0, wa.y * 0.2 + wa.w * 0.06) * hgt; // flowers, reeds, crops
    } else {
      wp += vec3f(wa.x * 0.011 + wa.z * 0.004, 0.0, wa.y * 0.011 + wa.w * 0.003) * hgt; // trunk and crown lean
      if (part == 10u) {
        let wl = windAt(wp.xz); // per leaf position: gusts sweep through the crown
        if (cardMeta > 0u) {
          // curved foliage cards bend elastically at their free end, like the grass
          let flex = clamp(flexT * 0.80 + abs(flexS) * 0.28, 0.0, 1.15);
          let flex2 = flex * flex;
          let ripple = sin(t * 3.3 + wp.x * 2.1 + wp.y * 1.7 + wp.z * 1.9);
          wp += vec3f(wl.x * 0.07 + wl.z * 0.025, -(length(wl.xy) * 0.04 + ripple * 0.012), wl.y * 0.07 + wl.w * 0.025) * flex2;
        } else {
          wp += vec3f(wl.z, wl.w * 0.6, wl.z * 0.7) * 0.004; // a leaf voxel flutters as one rigid piece
        }
      }
    }
  }
  var o: POut;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.wp = wp;
  o.n = vec3f(dot(inst.m0.xyz, nrm), dot(inst.m1.xyz, nrm), dot(inst.m2.xyz, nrm));
  o.tu = normalize(vec3f(dot(inst.m0.xyz, ua), dot(inst.m1.xyz, ua), dot(inst.m2.xyz, ua)));
  o.tv = normalize(vec3f(dot(inst.m0.xyz, va), dot(inst.m1.xyz, va), dot(inst.m2.xyz, va)));
  o.rgb = w1 & 0xffffffu;
  o.ao = f32((aow >> (c * 2u)) & 3u) / 3.0;
  o.mask = inst.mask;
  o.fl = part | (em << 4u) | (dir << 5u) | (((mi.flags >> 4u) & 3u) << 8u) | (select(0u, 1u, mi.pivot.w > 0.1) << 10u);
  o.lv = lvox;
  o.quv = quv;
  o.fl = o.fl | (select(0u, w1 & 3u, (mi.flags & 512u) != 0u) << 12u) | (select(edgeMask, cardMeta, part == 10u) << 14u);
  o.vsz = mi.pivot.w;
  o.extra = inst.extra;
  return o;
}
// Pixel-art foliage cluster texture evaluated on curved 2D bough surfaces (4cm pixel scale matching grass & characters).
// Shapes each curved surface into a lush scalloped cloud of overlapping pixel-art leaves/needles with dappled sky pinholes.
fn foliageCardTex(quv: vec4f, fl: u32, vsz: f32) -> vec4f {
  let shape = (fl >> 8u) & 3u; // 0: broadleaf, 1: conifer needle frond, 2: blossom, 3: weeping birch/willow
  let cardMeta = (fl >> 14u) & 255u;
  let physScale = clamp(vsz / 0.04, 1.6, 4.0);
  let totalPix = max(vec2f(6.0), floor(quv.zw * physScale));
  let uvRaw = clamp(quv.xy / max(quv.zw, vec2f(0.001)), vec2f(0.0), vec2f(0.9999));
  let pixF = floor(uvRaw * totalPix);
  let pix = vec2i(pixF);
  let uv = (pixF + 0.5) / totalPix;
  let s = (uv.x - 0.5) * 2.0;
  let t = uv.y;
  let seed = i32(cardMeta) * 19 + i32(shape) * 73;
  let hPix = hash3i(vec3i(pix.x, pix.y, seed + 41));

  // 1. Scalloped pixel-art cluster silhouette + dappled sky gaps (erases all rectangular card edges)
  if (shape == 1u) {
    // Conifer drooping needle fan: wide mid-frond tapering into serrated needle fingers
    let dy = (t - 0.46) / 0.52;
    let r = sqrt(s * s * (0.76 + 0.34 * t) + dy * dy);
    let ang = atan2(dy, s);
    let finger = sin(ang * 13.0 + f32(seed)) * 0.12 + cos(ang * 7.0 - f32(seed) * 0.7) * 0.10;
    let hBundle = hash3i(vec3i(pix.x / 2, pix.y / 3, seed + 5));
    let rLimit = 0.88 + finger + (hBundle - 0.5) * 0.24 + (hPix - 0.5) * 0.10;
    if (r > rLimit) { return vec4f(0.0); }
    if (r > 0.58 && hBundle < 0.20 && hPix < 0.52) { return vec4f(0.0); }
  } else if (shape == 3u) {
    // Weeping willow / birch cascading pixel-art strands
    let dy = (t - 0.48) / 0.50;
    let strandWave = sin(s * 9.5 + f32(seed)) * 0.13 + cos(s * 5.0 - f32(seed)) * 0.09;
    let r = sqrt(s * s * 0.84 + dy * dy) - strandWave * t;
    let hTuft = hash3i(vec3i(pix.x / 2, pix.y / 4, seed + 13));
    let rLimit = 0.88 + (hTuft - 0.5) * 0.24 + (hPix - 0.5) * 0.10;
    if (r > rLimit) { return vec4f(0.0); }
    if (t > 0.45 && abs(sin(s * 10.5 + f32(seed))) > 0.80 && hPix < 0.62) { return vec4f(0.0); }
  } else {
    // Broadleaf & blossom billowing multi-lobed pixel bouquet
    let dy = (t - 0.48) / 0.50;
    let r = sqrt(s * s * 0.86 + dy * dy);
    let ang = atan2(dy, s);
    let lobes = sin(ang * 5.0 + f32(seed) * 1.3) * 0.14 + cos(ang * 9.0 - f32(seed) * 0.8) * 0.09;
    let stagX = pix.x + (pix.y / 3) * 2;
    let hTuft = hash3i(vec3i(stagX / 3, pix.y / 3, seed + 19));
    let rLimit = 0.88 + lobes + (hTuft - 0.5) * 0.24 + (hPix - 0.5) * 0.10;
    if (r > rLimit) { return vec4f(0.0); }
    if (r > 0.56 && hTuft < 0.18 && hPix < 0.55) { return vec4f(0.0); }
  }

  // 2. Staggered pixel-art leaf shingles & bouquet shading (root-to-tip gradient like vsGrass)
  let boughGrad = 0.74 + 0.36 * smoothstep(0.0, 0.85, t) + 0.08 * (1.0 - abs(s));
  let bqCell = vec2i(pix.x / 6, pix.y / 6);
  let bqLocal = vec2f(f32(pix.x % 6) - 2.5, f32(pix.y % 6) - 2.5) / 3.0;
  let bqMound = 0.92 + 0.16 * clamp(1.0 - dot(bqLocal, bqLocal) * 0.45 + bqLocal.y * 0.25, 0.0, 1.2);
  let hBq = hash3i(vec3i(bqCell.x, bqCell.y, seed + 101));

  var leafTone = 1.0;
  var warmTip = vec3f(1.0);
  if (shape == 1u) {
    // Crisp ribbed conifer needle bundles
    let nStripe = (pix.x + pix.y * 2) % 3;
    let hNeedle = hash3i(vec3i(pix.x / 2, pix.y / 3, seed + 71));
    if (nStripe == 0) {
      leafTone = 0.72 + hNeedle * 0.12;
    } else if (nStripe == 1) {
      leafTone = 0.96 + hNeedle * 0.14;
    } else {
      leafTone = 1.15 + hNeedle * 0.14;
      warmTip = vec3f(1.04, 1.05, 0.90);
    }
  } else {
    // Staggered 4x4 overlapping pixel-art leaf shingles with dark upper tuck & sunlit lower blade tip
    let shiftX = pix.x + (pix.y / 4) * 2;
    let lx = ((shiftX % 4) + 4) % 4;
    let ly = ((pix.y % 4) + 4) % 4;
    let leafCell = vec2i(shiftX / 4, pix.y / 4);
    let hLeaf = hash3i(vec3i(leafCell.x, leafCell.y, seed + 83));
    if (ly == 0 || (ly == 1 && lx == 0)) {
      // Deep occluded shadow crease under the overlapping leaf shingle above
      leafTone = 0.68 + hLeaf * 0.12;
    } else if (ly == 3 && (lx == 1 || lx == 2)) {
      // Sunlit lower/outer leaf blade tip
      leafTone = 1.18 + hLeaf * 0.15;
      warmTip = select(vec3f(1.07, 1.06, 0.86), vec3f(1.20, 1.06, 1.14), shape == 2u);
    } else if (ly == 3) {
      // Shadow notch between adjacent leaf tips
      leafTone = 0.76 + hLeaf * 0.10;
    } else {
      // Rich midtone leaf blade with subtle midrib
      let midrib = select(1.0, 0.88, lx == 1 && ly == 2);
      leafTone = (0.94 + hLeaf * 0.18 + (hPix - 0.5) * 0.08) * midrib;
    }
  }

  let tint = warmTip * (leafTone * bqMound * boughGrad * (0.94 + hBq * 0.12));
  return vec4f(tint, 1.0);
}
@fragment fn fsPropShadow(s: PShadOut) {
  if ((s.info.x & 15u) == 10u && ((s.info.x >> 14u) & 255u) > 0u) {
    if (foliageCardTex(s.quv, s.info.x, bitcast<f32>(s.info.y)).w < 0.5) { discard; }
  }
}
// tree leaves: the leaf shape is cut out of each voxel face (pointed blade with a midrib, needles,
// five-petal blossoms); coarse far models show 2x2 small leaves per face. Returns -1 to discard.
fn leafShade(i: POut) -> f32 {
  let dir = (i.fl >> 5u) & 7u;
  let shape = (i.fl >> 8u) & 3u;
  var uv = vec2f(fract(dot(i.lv, axv(uaxOf(dir)))), fract(dot(i.lv, axv(vaxOf(dir))))) - 0.5;
  let cell = vec3i(floor(i.lv - nrmOf(dir) * 0.5));
  var h = hash3i(cell + vec3i(i32(dir) * 17, 0, 0));
  if (((i.fl >> 10u) & 1u) == 1u) {
    let q2 = (uv + 0.5) * 2.0;
    let qi = vec2i(floor(q2));
    uv = fract(q2) - 0.5;
    h = hash3i(cell * 3 + vec3i(qi.x, qi.y, i32(dir)));
  }
  let a = h * 6.283;
  let ca = cos(a); let sa = sin(a);
  let q = vec2f(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);
  if (shape == 1u) {
    // two crossed needles
    let n1 = abs(q.x) < 0.07 && abs(q.y) < 0.48;
    let n2 = abs(q.y + q.x * 0.6) < 0.06 && abs(q.x) < 0.42;
    if (!(n1 || n2)) { return -1.0; }
    return 0.85 + h * 0.3;
  }
  if (shape == 2u) {
    let r = length(uv);
    let th = atan2(uv.y, uv.x) + a;
    let pet = 0.24 + 0.26 * abs(cos(th * 2.5));
    if (r > pet) { return -1.0; }
    return select(1.0, 1.25, r < 0.08) * (0.9 + h * 0.2);
  }
  let yy = q.y * 2.0;
  let wdt = 0.45 * pow(max(1.0 - yy * yy, 0.0), 0.55);
  if (abs(q.x) > wdt) { return -1.0; }
  var k = 0.88 + h * 0.24;
  if (abs(q.x) < 0.035) { k *= 0.78; }
  if (fract((q.y + abs(q.x) * 0.9) * 5.0) < 0.14) { k *= 0.9; }
  return k * (0.9 + 0.2 * (abs(q.x) / max(wdt, 0.01)));
}
// Player-tracking watching eye on Nightmare ("Вглядывание") trees (PART.EYE = 7)
fn treeEyeShade(i: POut, w: f32) -> vec3f {
  let q = (i.quv.xy / max(i.quv.zw, vec2f(1.0))) * 2.0 - 1.0;
  let wOff = i.tu * q.x + i.tv * q.y;
  let eh = normalize(vec3f(-i.n.z, 0.0, i.n.x + 1e-5));
  let ex = clamp(dot(wOff, eh), -1.0, 1.0);
  let ey = clamp(wOff.y, -1.0, 1.0);

  // Compute gaze vector from this eye's world position toward the player's head
  let toP = normalize((F.player.xyz + vec3f(0.0, 1.25, 0.0)) - i.wp);
  let t = F.cam.w;
  let idHash = fract(sin(dot(floor(i.wp * 1.5), vec3f(12.9898, 78.233, 37.719))) * 43758.5453);
  let saccX = sin(t * 3.7 + idHash * 19.0) * 0.025;
  let saccY = cos(t * 4.3 + idHash * 13.0) * 0.02;
  let lookX = clamp(dot(toP, eh) * 0.58 + saccX, -0.44, 0.44);
  let lookY = clamp(toP.y * 0.55 + saccY, -0.28, 0.28);

  // Periodic organic blink per eye
  let blinkPh = fract(t * 0.18 + idHash);
  let open = smoothstep(0.0, 0.035, blinkPh) * (1.0 - smoothstep(0.955, 0.99, blinkPh));
  let lidY = (1.0 - ex * ex * 0.72) * (0.72 * open + 0.03);
  let rBall = ex * ex * 0.85 + ey * ey * 1.25;
  if (abs(ey) > lidY || rBall > 0.96) {
    let rim = smoothstep(lidY + 0.18, lidY, abs(ey)) * (1.0 - smoothstep(0.92, 1.08, rBall));
    return mix(vec3f(0.05, 0.008, 0.012), vec3f(0.28, 0.025, 0.03), rim);
  }

  // Bloodshot sclera with crimson capillaries near the corners
  let dp = vec2f(ex - lookX, (ey - lookY) * 1.12);
  let ir = length(dp);
  let vein = abs(sin(atan2(ey, ex) * 9.0 + rBall * 6.0));
  var col = mix(vec3f(0.55, 0.06, 0.06), vec3f(0.92, 0.72, 0.64), smoothstep(0.92, 0.32, rBall) * (0.75 + 0.25 * vein));

  // Glowing crimson-amber iris
  if (ir < 0.44) {
    let u = ir / 0.44;
    let fib = 0.82 + 0.18 * sin(atan2(dp.y, dp.x) * 16.0 + u * 8.0);
    let irisC = mix(vec3f(1.35, 0.32, 0.06), vec3f(0.78, 0.04, 0.05), u * u) * fib;
    col = mix(col, irisC, smoothstep(0.44, 0.36, ir));
  }

  // Vertical cat/demon slit pupil that tracks the player even more tightly
  let px = ex - lookX * 1.08;
  let py = ey - lookY * 1.08;
  let slitW = 0.095 * max(0.0, 1.0 - py * py * 7.5);
  let inPupil = smoothstep(slitW + 0.025, max(0.0, slitW - 0.015), abs(px)) * smoothstep(0.38, 0.30, abs(py));
  col = mix(col, vec3f(0.01, 0.004, 0.006), inPupil);

  // Wet specular highlight
  let glint = smoothstep(0.085, 0.02, length(vec2f(ex - lookX - 0.12, ey - lookY - 0.10)));
  col += vec3f(1.4, 1.1, 0.95) * glint;
  return col * (0.75 + 0.55 * w);
}

fn facetNormal(i: POut, nrmIn: vec3f) -> vec3f {
  return nrmIn;
}
// Surface-aligned 2D pixel-art texture of props, furniture, buildings, vehicles, characters and tree bark (from v2.0)
fn propPixelTex(i: POut, n: vec3f) -> vec4f {
  let part = i.fl & 15u;
  let cardMeta = (i.fl >> 12u) & 255u;
  if (part == 10u && cardMeta > 0u) {
    return vec4f(1.0, 1.0, 1.0, 0.5);
  }

  // Continuous 2D surface coordinates in meters -> quantized to crisp pixel-art texels (~2.5cm on props, ~3.2cm on bark)
  let pixSize = select(clamp(i.vsz * 0.48, 0.014, 0.028), 0.032, part == 11u);
  let uMeters = i.quv.x * i.vsz;
  let vMeters = i.quv.y * i.vsz;
  let pix = vec2i(floor(vec2f(uMeters, vMeters) / pixSize));
  let seed = i32((i.rgb * 2654435761u) >> 18u);
  let hPix = hash3i(vec3i(pix.x, pix.y, seed));
  let h2x2 = hash3i(vec3i(pix.x >> 1, pix.y >> 1, seed + 19));

  let maxC = max(i.col.r, max(i.col.g, i.col.b));
  let minC = min(i.col.r, min(i.col.g, i.col.b));
  let sat = (maxC - minC) / max(maxC, 0.001);
  let isWarmWood = i.col.r > i.col.g * 1.04 && i.col.g > i.col.b * 1.08 && sat > 0.16 && maxC < 0.72;
  let isMetal = sat < 0.16 && maxC > 0.14 && maxC < 0.72;
  let isStone = sat < 0.18 && !isMetal;
  let isFabric = (i.col.b > i.col.r * 1.12 || (i.col.r > i.col.b * 1.35 && sat > 0.42)) && part != 11u;

  var shade = 1.0;
  var height = 0.5;
  var tint = vec3f(1.0);

  if (part == 11u) {
    // Crisp Pixel-Art Tree Bark: 2x5 vertical bark plates with dark fissures, sunlit ridges, and birch lenticels
    let plateX = pix.x / 2;
    let shiftY = pix.y + (plateX & 1) * 2;
    let plateY = shiftY / 5;
    let lx = ((pix.x % 2) + 2) % 2;
    let ly = ((shiftY % 5) + 5) % 5;
    let hPlate = hash3i(vec3i(plateX, plateY, seed + 31));
    let isBirch = maxC > 0.52 && sat < 0.22;
    if (isBirch) {
      let lenticel = hash3i(vec3i(0, pix.y / 2, seed + 41)) < 0.22 && ((pix.x + pix.y * 3) % 6 < 3);
      shade = select(0.95 + (h2x2 - 0.5) * 0.12 + (hPix - 0.5) * 0.06, 0.28, lenticel);
      height = select(0.58, 0.22, lenticel);
    } else if (lx == 0 && (ly == 0 || hPlate < 0.34)) {
      // Deep vertical bark fissure pixel
      shade = 0.62 + hPix * 0.10;
      height = 0.20;
    } else {
      // Raised bark scale ridge
      let ridge = select(0.94, 1.12, lx == 1 && ly >= 2);
      shade = (0.86 + hPlate * 0.26) * ridge * (0.95 + (hPix - 0.5) * 0.10);
      height = select(0.54, 0.74, lx == 1);
    }
  } else if (isWarmWood) {
    // Pixel-Art Wood Planks & Furniture Grain: 5-pixel boards with elongated wood fibers & dark board seams
    let plankIdx = pix.x / 5;
    let withinPlank = ((pix.x % 5) + 5) % 5;
    let hBoard = hash3i(vec3i(plankIdx, 0, seed + 53));
    let hFiber = hash3i(vec3i(pix.x, pix.y / 4, seed + 61));
    if (withinPlank == 0 && i.quv.z >= 3.0) {
      shade = 0.72 + hPix * 0.08;
      height = 0.24;
    } else {
      let bevel = select(1.0, 1.08, withinPlank == 4);
      shade = (0.90 + hBoard * 0.18) * bevel * (0.92 + hFiber * 0.16 + (hPix - 0.5) * 0.06);
      height = 0.46 + hFiber * 0.22;
    }
  } else if (isFabric) {
    // Pixel-Art Woven Textile / Clothing / Upholstery: 2x2 diagonal twill weave
    let weave = ((pix.x + pix.y) & 1);
    let stitch = (((pix.x * 3 + pix.y) % 4) == 0);
    shade = select(0.92, 1.07, weave == 1) * select(1.0, 0.88, stitch) * (0.96 + (h2x2 - 0.5) * 0.08);
    height = select(0.42, 0.64, weave == 1);
  } else if (isMetal) {
    // Pixel-Art Brushed Metal & Riveted Panels
    let lx = ((pix.x % 10) + 10) % 10;
    let ly = ((pix.y % 10) + 10) % 10;
    let hBrush = hash3i(vec3i(pix.x / 4, pix.y, seed + 73));
    let onRivet = (lx == 1 || lx == 8) && (ly == 1 || ly == 8) && i.quv.z >= 3.0;
    shade = select(0.92 + hBrush * 0.16 + (hPix - 0.5) * 0.06, 1.18, onRivet);
    height = select(0.52 + (hBrush - 0.5) * 0.16, 0.80, onRivet);
  } else if (isStone) {
    // Pixel-Art Dressed Stone & Mineral Facets
    let row = pix.y / 4;
    let shiftX = pix.x + (row & 1) * 3;
    let col = shiftX / 6;
    let lx = ((shiftX % 6) + 6) % 6;
    let ly = ((pix.y % 4) + 4) % 4;
    let hStone = hash3i(vec3i(col, row, seed + 89));
    if ((lx == 0 || ly == 0) && i.quv.z >= 3.0) {
      shade = 0.76 + hPix * 0.08;
      height = 0.24;
    } else {
      let bevel = select(1.0, 1.09, ly == 3 || lx == 1);
      shade = (0.90 + hStone * 0.20) * bevel * (0.94 + (hPix - 0.5) * 0.10);
      height = 0.50 + hStone * 0.24;
    }
  } else {
    // Clean 2x2 Bayer-style pixel-art stipple for plaster, ceramic, paper, and character skin
    let bayer = f32(((pix.x & 1) << 1) ^ (pix.y & 1)) / 3.0 - 0.5;
    shade = 0.95 + h2x2 * 0.08 + bayer * 0.06 + (hPix - 0.5) * 0.05;
    height = 0.50 + bayer * 0.12;
  }

  return vec4f(tint * shade, height);
}


// rgb = colour, a = 1 for a reflective surface (roughness < 0.3)
fn propColorSh(i: POut, w: f32, night: bool, n: vec3f, sh: f32) -> vec4f {
  let dist = distance(i.wp, F.cam.xyz);
  let grazing = clamp(abs(dot(n, normalize(F.cam.xyz - i.wp))), 0.22, 1.0);
  let texFade = 1.0 - smoothstep(8.0, 20.0, dist / grazing); // the pixel texture (~2.5 cm texels) fades out before a texel shrinks below a pixel (no shimmer, less work)
  var pTex = vec4f(1.0, 1.0, 1.0, 0.5);
  if (texFade > 0.0) { pTex = propPixelTex(i, n); }
  let ao = clamp(i.ao * mix(1.0, clamp(0.84 + pTex.w * 0.30, 0.78, 1.08), texFade), 0.05, 1.0);
  let hv = hash3i(vec3i(floor(i.lv)));
  var alb = i.col * mix(vec3f(0.85 + hv * 0.3), pTex.rgb, texFade);
  let part = i.fl & 15u;
  // PBR class of the voxel (PART in models/vox.js): 13 metal, 14 smooth dielectric (glass, enamel, lacquer), 10 leaf, 11 wood
  var rough = 0.72;
  var metal = 0.0;
  if (part == 13u) { metal = 1.0; rough = 0.34; } else if (part == 14u) { rough = 0.14; } else if (part == 10u) { rough = 0.55; } else if (part == 11u) { rough = 0.86; }
  rough = clamp(rough + (hv - 0.5) * 0.12 + (0.5 - pTex.w) * 0.18 * texFade, 0.05, 1.0);
  let wet = F.pbr.x * (0.4 + 0.6 * max(n.y, 0.0));
  alb *= 1.0 - wet * 0.22 * (1.0 - metal);
  rough = mix(rough, 0.12, wet * 0.7);
  var c = shadePBR(i.wp, n, w, sh, Surf(alb, rough, metal, ao));
  if (((i.fl >> 4u) & 1u) == 1u) {
    var k = 1.4;
    if (part == 5u) { k = 1.0 + sin(F.cam.w * 3.5) * 0.8; }
    c += alb * k;
  }
  if (part == 6u) {
    let v = normalize(F.cam.xyz - i.wp);
    let oneMinus = 1.0 - abs(dot(n, v));
    let rim = oneMinus * oneMinus;
    c += vec3f(1.0, 0.85, 0.55) * (0.12 + rim * 0.7) * (0.6 + 0.4 * sin(F.cam.w * 3.5));
  }
  c += vec3f(1.0, 0.32, 0.22) * waveRim(i.wp) * 1.4;
  return vec4f(c, select(0.0, 1.0, rough < 0.3));
}
fn propColor(i: POut, w: f32, night: bool) -> vec4f {
  let n = facetNormal(i, normalize(i.n));
  var sh = 1.0;
  if ((i.mask & 16u) == 0u) { sh = shadowSun(i.wp, n, true); }
  return propColorSh(i, w, night, n, sh);
}

@fragment fn fsTree(pv: PV) -> GFragOut {
  var i = unpackP(pv);
  // the only discard: the leaf shapes of the foliage cards (the trees are drawn after the other models)
  let w = wAt(i.wp);
  let night = w > 0.5;
  if (WMODE == 2u && (i.mask & select(1u, 2u, night)) == 0u) { discard; }
  let part = i.fl & 15u;
  if (part == 7u) {
    let eyeCol = treeEyeShade(i, w);
    return GFragOut(vec4f(eyeCol, 1.0), vec4f(normalize(i.n) * 0.5 + 0.5, gbA(i.ao, false, false, false)));
  }
  let isLeaf = part == 10u;
  var k = 1.0;
  var leafTip = 0.5;
  if (isLeaf) {
    // curved 2D foliage cards (v2.0 trees): the pixel-art leaf cluster is cut out of the card
    let cardMeta = (i.fl >> 12u) & 255u;
    if (cardMeta == 0u) {
      // voxel leaf clouds: a leaf shape cut out of every voxel face (2x2 small leaves on coarse models)
      let ls = leafShade(i);
      if (ls < 0.0) { discard; }
      i.col = i.col * ls;
    } else {
      let fTex = foliageCardTex(i.quv, i.fl, i.vsz);
      if (fTex.w < 0.5) { discard; }
      i.col = i.col * fTex.rgb;
    }
    if (cardMeta > 0u) {
      let wingMode = (i.fl >> 5u) & 7u;
      if (wingMode >= 1u && wingMode <= 6u) {
        let row = (wingMode - 1u) / 2u;
        leafTip = (f32(row) + clamp(i.quv.y / max(i.quv.w, 1.0), 0.0, 1.0)) / 3.0;
      } else {
        leafTip = clamp(i.quv.y / max(i.quv.w, 1.0), 0.0, 1.0);
      }
      i.lv = vec3f(f32(cardMeta) * 0.13, f32(wingMode) * 0.29, 0.5); // no voxel seams across a curved card
    }
    k = 0.88 + 0.20 * leafTip;
    i.ao = clamp(i.ao * (0.68 + 0.32 * leafTip), 0.22, 1.0);
  } else {
    k = 0.76 + 0.24 * clamp(i.lv.y * i.vsz * 0.55, 0.0, 1.0); // darker root collar
  }
  let nrm = normalize(i.n);
  let sh0 = shadowSun(i.wp, nrm, false);
  let sh = select(sh0, 0.28 + 0.72 * sh0, isLeaf);
  var c = vec4f(0.0);
  if (isLeaf) {
    // the crown is many overlapping cards, so every leaf pixel may be shaded several times: leaves take a light model
    // without the specular part (a rough leaf shows almost none): sun with a soft wrap + sky light (SH9) + the bounce
    // the crown reads as a volume: leaves facing down and deep inside it get less sky; every bough a slightly
    // different green (one hash per card) so the crown is not one flat colour
    let skyVis = 0.5 + 0.5 * smoothstep(-0.6, 0.8, nrm.y);
    let ao = clamp(i.ao * skyVis, 0.05, 1.0);
    let hb = hash3i(vec3i(i32((i.fl >> 14u) & 255u), i32(floor(i.wp.y * 1.3)), 7));
    let wet = F.pbr.x * (0.4 + 0.6 * max(nrm.y, 0.0));
    let alb = i.col * vec3f(0.94 + hb * 0.1, 0.92 + hb * 0.16, 0.9 + hb * 0.08) * (1.0 - wet * 0.22);
    let sunC = sunCol(w);
    let ndl = max(dot(nrm, F.sunDir.xyz) * 0.6 + 0.4, 0.0) * 0.85; // soft wrap: light passes around thin leaves
    let v = normalize(F.cam.xyz - i.wp);
    let sheen = pow(max(dot(reflect(-F.sunDir.xyz, nrm), v), 0.0), 12.0) * 0.12 * sh; // the waxy glint of sunlit leaves
    c = vec4f(alb * (sunC * (ndl * sh) + envIrr(nrm, w) * (F.pbr.y * (0.22 + 0.78 * ao))) + sunC * sheen + vec3f(1.0, 0.32, 0.22) * waveRim(i.wp) * 1.4, 0.0);
  } else {
    c = propColorSh(i, w, night, nrm, sh);
  }
  var tr = vec3f(0.0);
  if (isLeaf) {
    // Realistic botanical foliage translucency: chloroplast subsurface transmission (reuses sh: 0 extra shadow fetches!)
    let sunBack = max(dot(-nrm, F.sunDir.xyz), 0.0);
    let v = normalize(F.cam.xyz - i.wp);
    let d = max(0.0, dot(v, -F.sunDir.xyz));
    let forwardScatter = d * d * d * 0.5;
    let sunCol = sunCol(w);
    let transmitTint = select(vec3f(1.15, 1.28, 0.82), vec3f(1.4, 0.35, 0.45), night);
    tr = i.col * transmitTint * sunCol * (sunBack * 0.45 + forwardScatter + 0.12) * (0.35 + 0.65 * sh);
  }
  var outCol = c.rgb * k + tr;
  outCol = flatFog(outCol, i.wp, w);
  return GFragOut(vec4f(outCol, 1.0), vec4f(nrm * 0.5 + 0.5, gbA(i.ao, true, false, false)));
}
@fragment fn fsPropMasked(pv: PV) -> GFragOut {
  let i = unpackP(pv);
  if (i.extra > 0.001 && i.extra < 0.999) {
    let dither = fract(sin(dot(floor(i.wp * 16.0), vec3f(12.9898, 78.233, 37.719))) * 43758.5453);
    if (dither > i.extra) { discard; }
  }
  let w = worldAt(i.wp);
  let night = w > 0.5;
  if ((i.mask & select(1u, 2u, night)) == 0u) { discard; }
  let c = propColor(i, w, night);
  return GFragOut(vec4f(c.rgb, 1.0), vec4f(normalize(i.n) * 0.5 + 0.5, gbA(i.ao, false, c.a > 0.5, (i.mask & 32u) != 0u)));
}
// stable world: the cull pass already filtered instances by world mask -> no discard
@fragment fn fsProp(pv: PV) -> GFragOut {
  let i = unpackP(pv);
  let w = wAt(i.wp);
  let c = propColor(i, w, w > 0.5);
  return GFragOut(vec4f(c.rgb, 1.0), vec4f(normalize(i.n) * 0.5 + 0.5, gbA(i.ao, false, c.a > 0.5, (i.mask & 32u) != 0u)));
}

struct GOut { @builtin(position) pos: vec4f, @location(0) col: vec3f };
fn grassShadow(p: vec3f) -> f32 { return shadowSun(p, vec3f(0.0, 1.0, 0.0), false); }
// What grows in a 0.5 m cell. Kinds are assigned by src/world/grassmap.js:
// 1 meadow, 2 tall grass in ear, 3 dry autumn grass, 4 mown, 5 roadside, 6 sedge, 7 moss, 8 forest shade,
// 9 stubble, 10 dead (nightmare). dens 0..1, blade height h0..h1 m, width m, share of ear stalks, wind response.
struct GKind { dens: f32, h0: f32, h1: f32, wid: f32, ears: f32, sway: f32, tipA: vec3f, tipB: vec3f, root: vec3f };
fn grassKind(k: u32) -> GKind {
  switch (k) {
    case 1u: { return GKind(1.0, 0.10, 0.34, 0.026, 0.05, 1.0, vec3f(0.30, 0.30, 0.06), vec3f(0.16, 0.21, 0.04), vec3f(0.04, 0.05, 0.02)); }
    case 2u: { return GKind(1.0, 0.28, 0.72, 0.028, 0.30, 1.2, vec3f(0.27, 0.30, 0.07), vec3f(0.17, 0.23, 0.05), vec3f(0.05, 0.06, 0.02)); }
    case 3u: { return GKind(0.85, 0.26, 0.62, 0.022, 0.50, 1.2, vec3f(0.52, 0.42, 0.16), vec3f(0.40, 0.36, 0.12), vec3f(0.10, 0.09, 0.04)); }
    case 4u: { return GKind(1.0, 0.03, 0.08, 0.030, 0.0, 0.4, vec3f(0.22, 0.28, 0.06), vec3f(0.17, 0.23, 0.05), vec3f(0.05, 0.06, 0.02)); }
    case 5u: { return GKind(0.8, 0.05, 0.16, 0.024, 0.04, 0.7, vec3f(0.30, 0.29, 0.10), vec3f(0.24, 0.25, 0.08), vec3f(0.07, 0.07, 0.03)); }
    case 6u: { return GKind(1.0, 0.35, 0.85, 0.036, 0.12, 0.8, vec3f(0.13, 0.24, 0.07), vec3f(0.10, 0.19, 0.08), vec3f(0.03, 0.05, 0.02)); }
    case 7u: { return GKind(0.9, 0.03, 0.09, 0.034, 0.0, 0.3, vec3f(0.22, 0.34, 0.09), vec3f(0.16, 0.27, 0.07), vec3f(0.04, 0.06, 0.02)); }
    case 8u: { return GKind(0.55, 0.08, 0.22, 0.030, 0.0, 0.8, vec3f(0.14, 0.22, 0.05), vec3f(0.11, 0.18, 0.05), vec3f(0.03, 0.04, 0.02)); }
    case 9u: { return GKind(0.7, 0.07, 0.13, 0.012, 0.0, 0.15, vec3f(0.60, 0.50, 0.22), vec3f(0.50, 0.42, 0.18), vec3f(0.22, 0.17, 0.08)); }
    case 10u: { return GKind(0.7, 0.05, 0.18, 0.020, 0.0, 0.0, vec3f(0.11, 0.10, 0.085), vec3f(0.09, 0.085, 0.075), vec3f(0.02, 0.018, 0.016)); }
    default: { return GKind(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0)); }
  }
}
@vertex fn vsGrass(@builtin(vertex_index) vi: u32) -> GOut {
  let BB = max(u32(F.grass.y), 1u);
  let ii = (vi >> 2u) / BB; // the 0.5 m cell
  var o: GOut;
  o.pos = vec4f(2.0, 2.0, 2.0, 1.0);
  o.col = vec3f(0.0);
  // the 0.5 m cell grid sits in front of the camera (nothing is generated behind it)
  let N = u32(F.grass.x);
  let fwd = normalize(vec2f(F.camRight.z, -F.camRight.x));
  let gf = fwd * F.grass.z * 0.5 + F.cam.xz;
  let cx = i32(ii % N) - i32(N / 2u) + i32(floor(gf.x * 2.0));
  let cz = i32(ii / N) - i32(N / 2u) + i32(floor(gf.y * 2.0));
  if (cx < 1 || cz < 1 || cx >= 383 || cz >= 639) { return o; }
  let cell = gcol[983040u + u32(cx) + u32(cz) * 384u];
  if ((cell & 255u) == 0u) { return o; }
  let cc = vec2f((f32(cx) + 0.5) * 0.5, (f32(cz) + 0.5) * 0.5);
  let toC = cc - F.cam.xz;
  let dist = length(toC);
  let R = F.grass.z;
  if (dist > R) { return o; }
  if (dist > 3.0 && dot(toC, fwd) < -0.3 * dist) { return o; } // cells behind the camera
  // the blade and the voxel column it stands on (exact ground level, no grass on paving)
  let b = (vi >> 2u) % BB; // indexed: (cell * blades + blade) * 4 + corner
  let hb = hashu((u32(cx) * 73856093u) ^ (u32(cz) * 19349663u) ^ (b * 83492791u));
  let r1 = f32(hb & 1023u) / 1023.0; let r2 = f32((hb >> 10u) & 1023u) / 1023.0; let r3 = f32((hb >> 20u) & 1023u) / 1023.0;
  let r4 = f32(hashu(hb ^ 0x9e3779b9u) & 1023u) / 1023.0;
  let bx = cc.x + (r1 - 0.5) * 0.5;
  let bz = cc.y + (r2 - 0.5) * 0.5;
  let ci = u32(bx * 8.0) + u32(bz * 8.0) * 1536u;
  let lv = (gcol[ci >> 2u] >> ((ci & 3u) * 8u)) & 255u;
  if (lv == 0u) { return o; }
  let yD = f32(lv) * 0.125;
  let w = worldAt(vec3f(bx, yD + 0.3, bz));
  let night = w > 0.5;
  let kind = select(cell & 15u, (cell >> 4u) & 15u, night);
  if (kind == 0u) { return o; }
  let K = grassKind(kind);
  let y = select(yD, select(f32((cell >> 8u) & 127u) * 0.125, yD, ((cell >> 15u) & 1u) == 1u), night);
  // fewer but wider blades with distance: the cover stays, the vertex load drops
  let fade = 1.0 - smoothstep(R * 0.6, R, dist);
  let lod = mix(1.0, 0.4, smoothstep(R * 0.15, R * 0.7, dist)) * (0.35 + 0.65 * fade);
  if (f32(b) >= F.grass.y * K.dens * (f32((cell >> 20u) & 15u) / 15.0) * lod) { return o; }
  let ear = r4 < K.ears && !night; // a stalk carrying a seed head
  let hv = 0.6 + f32((cell >> 16u) & 15u) / 15.0 * 0.8;
  let h = mix(K.h0, K.h1, r3 * (0.4 + 0.6 * r3)) * hv * (0.35 + 0.65 * fade) * select(1.0, 1.2, ear);
  let base = vec3f(bx, y, bz);
  // billboard around Y: blades taper to the tip, ear stalks are thin and widen into the head
  let side = normalize(vec3f(base.z - F.cam.z, 0.0, F.cam.x - base.x));
  let c = vi & 3u;
  let u = cuOf(c); let v = cvOf(c);
  let wb = max(K.wid / sqrt(max(lod, 0.2)), 1.5 * dist / F.opt.x); // never thinner than 1.5 px: no shimmer of far blades
  let wv = select(wb * (1.0 - 0.82 * v), mix(0.007, wb * 0.95, v), ear);
  var p = base + side * (u - 0.5) * wv;
  // bend: every blade leans its own way, gusts roll over the field, the hero pushes blades away
  let t = F.cam.w;
  let wa = windAt(base.xz); // the same wind as the plants and the trees
  var bend = vec2f(r1 - 0.5, r2 - 0.5) * h * 0.5;
  bend += (wa.xy * 0.36 + wa.zw * 0.2) * h * K.sway;
  if (night) { bend = vec2f(r1 - 0.5, r2 - 0.5) * h * 1.2; }
  let away = base.xz - F.player.xz;
  let ad = length(away);
  if (ad < 0.7) { bend += away / max(ad, 0.01) * (0.7 - ad) * 0.5 * h * 3.0; }
  p += vec3f(bend.x, 0.0, bend.y) * v * v;
  p.y += h * v;
  o.pos = F.viewProj * vec4f(p, 1.0);
  // palette gradient: dark base -> lit tip, patches of lush / dry grass, straw-coloured ears
  let pch = 0.5 + 0.5 * sin(f32(cx) * 0.11 + sin(f32(cz) * 0.07) * 2.0) * cos(f32(cz) * 0.09);
  var tip = mix(K.tipA, K.tipB, pch) * (0.85 + r3 * 0.3);
  if (ear) { tip = vec3f(0.50, 0.40, 0.16) * (0.8 + r1 * 0.4); }
  else if (r1 > 0.985 && kind <= 2u) { tip = vec3f(0.9, 0.78, 0.25); }
  let alb = mix(K.root, tip, v);
  let sh = grassShadow(base + vec3f(0.0, 0.1, 0.0));
  let sun = sunCol(w);
  let sky = skyCol(w);
  o.col = alb * (sun * (0.35 + 0.5 * v) * sh + sky * (0.55 + 0.45 * v)) + alb * sun * 0.25 * v * sh;
  return o;
}
@fragment fn fsGrass(i: GOut) -> GFragOut {
  return GFragOut(vec4f(i.col, 1.0), vec4f(0.5, 1.0, 0.5, gbA(1.0, true, false, false)));
}

struct PtOut { @builtin(position) pos: vec4f, @location(0) uv: vec2f, @location(1) col: vec4f };
@vertex fn vsPart(@builtin(vertex_index) vi: u32) -> PtOut {
  let ii = vi >> 2u; // indexed: particle * 4 + corner
  let pt = parts[ii];
  var o: PtOut;
  o.pos = vec4f(2.0, 2.0, 2.0, 1.0);
  o.uv = vec2f(0.0);
  o.col = vec4f(0.0);
  let ty = u32(pt.v.w);
  if (ty == 0u || pt.p.w <= 0.0) { return o; }
  let q = vec2f(cuOf(vi & 3u), cvOf(vi & 3u)) * 2.0 - 1.0; // indexed: 4 corners per particle
  var wp = pt.p.xyz;
  let w = worldAt(wp);
  let night = w > 0.5;
  let t = F.cam.w;
  let seed = pt.c.w;
  var size = 0.05;
  var col = vec4f(0.0);
  var r = F.camRight.xyz;
  var u = F.camUp.xyz;
  switch ty {
    case 1u: {
      let blink = pow(max(sin(t * (1.1 + fract(seed * 7.1)) + seed * 40.0), 0.0), 3.0);
      // a small crisp light (no soft halo): far away the lens turns it into a bokeh disc
      size = 0.014 + blink * 0.016;
      if (night) { col = vec4f(vec3f(1.0, 0.1, 0.04) * (1.0 + blink * 5.0), 0.0); }
      else { col = vec4f(vec3f(1.0, 0.92, 0.42) * (1.5 + blink * 12.0), 0.0) * F.fx2.y; } // dream: only from dusk on
      col = col * smoothstep(0.4, 1.0, distance(wp, F.cam.xyz));
    }
    case 2u, 3u: {
      let sh = shadowSun(wp, vec3f(0.0, 1.0, 0.0), false);
      let sunC = sunCol(w);
      let base = select(vec3f(1.0, 0.96, 0.88), vec3f(1.0, 0.82, 0.45), ty == 3u);
      size = select(0.016, 0.026, ty == 3u);
      col = vec4f(base * (sunC * (sh * 0.9 + 0.04) * 0.55 + vec3f(0.02)), 0.0);
    }
    case 4u: {
      let life = pt.p.w;
      size = 0.25 + (1.0 - life) * 1.3;
      let a = life * (1.0 - life) * 1.2 * select(1.0, 0.0, night);
      col = vec4f(vec3f(0.62, 0.62, 0.62) * a, a);
    }
    case 5u: {
      size = 0.022;
      col = vec4f(vec3f(1.0, 0.45, 0.1) * 3.5 * pt.p.w * select(1.0, 0.0, night), 0.0);
    }
    case 6u: {
      size = 0.04;
      col = vec4f(0.0, 0.0, 0.0, pt.p.w * 0.9);
    }
    case 10u: {
      size = 0.018 + fract(seed * 7.3) * 0.012;
      let a = min(pt.p.w * 2.0, 1.0) * select(0.75, 0.0, night);
      col = vec4f(vec3f(0.85, 0.92, 0.97) * (F.skyD.rgb * 1.4 + F.sunD.rgb * 0.6) * a, a * 0.8);
    }
    case 7u: {
      size = 0.055;
      let k = fract(seed * 13.7);
      var lc = vec3f(0.42, 0.6, 0.22);
      if (k > 0.6) { lc = vec3f(0.95, 0.62, 0.72); }
      if (k < 0.25) { lc = vec3f(0.85, 0.6, 0.22); }
      if (night) { lc = vec3f(0.16, 0.12, 0.1); }
      let sh = shadowSun(wp, vec3f(0.0, 1.0, 0.0), false);
      col = vec4f(lc * lc * (sunCol(w) * (0.25 + 0.75 * sh) * 0.5 + skyCol(w)), 1.0);
      let a = t * (1.0 + fract(seed * 3.0) * 2.0) + seed * 10.0;
      let ca = cos(a); let sa = sin(a);
      let r2 = r * ca + u * sa;
      u = (u * ca - r * sa);
      r = r2 * (0.35 + 0.65 * abs(sin(a * 0.7)));
    }
    case 9u: {
      size = pt.c.x;
      o.pos = F.viewProj * vec4f(wp + vec3f(q.x, 0.0, q.y) * size, 1.0);
      o.uv = q;
      o.col = vec4f(0.0, 0.0, 0.0, pt.c.y);
      return o;
    }
    default: { }
  }
  // nothing floats right at the lens (it would be a huge soft blob): fade out near the camera
  col = col * smoothstep(0.5, 1.4, distance(wp, F.cam.xyz));
  wp = wp + (r * q.x + u * q.y) * size;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.uv = q;
  o.col = col;
  return o;
}
@fragment fn fsPart(i: PtOut) -> GFragOut {
  let r2 = dot(i.uv, i.uv);
  if (r2 > 1.0) { discard; }
  var a = exp(-r2 * 3.2);
  if (i.col.a >= 0.999) { a = 1.0 - smoothstep(0.55, 1.0, r2); }
  return GFragOut(vec4f(i.col.rgb * a, a), vec4f(0.5, 0.5, 0.5, 0.0));
}
