
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

// linear view depth (metres) of a depth-buffer value
fn viewZ(dz: f32) -> f32 { return F.taa.x * F.taa.y / (F.taa.y - dz * (F.taa.y - F.taa.x)); }
// the light of the two worlds at world blend w (0 dream .. 1 nightmare)
fn sunCol(w: f32) -> vec3f { return mix(F.sunD.rgb, F.sunN.rgb, w); }
fn skyCol(w: f32) -> vec3f { return mix(F.skyD.rgb, F.skyN.rgb, w); }
fn fogCol(w: f32) -> vec3f { return mix(F.fogD.rgb, F.fogN.rgb, w); }
// distance fog when the volumetric fog pass is off (F.counts.z == 0)
fn flatFog(c: vec3f, p: vec3f, w: f32) -> vec3f {
  if (F.counts.z != 0u) { return c; }
  let d = max(0.0, distance(p, F.cam.xyz) - select(24.0, 5.0, w > 0.5));
  return mix(c, fogCol(w), clamp(1.0 - exp(-d * 0.012), 0.0, 0.62));
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
@group(0) @binding(20) var linSmp: sampler; // linear clamp-to-edge sampler for brdfLut
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
fn shadowUV(m: mat4x4f, p: vec3f) -> vec3f {
  let sp = m * vec4f(p, 1.0);
  return vec3f(sp.x * 0.5 + 0.5, 0.5 - sp.y * 0.5, sp.z);
}
// Screen-locked manga square-dot halftone screentone applied ONLY to sun light/shadow (never on lit faces or AO).
// Fixed 4x4 render-pixel staggered screen grid with crisp 1x1 (penumbra) and 2x2 (shadow) square dots:
// constant screen size — NEVER grows, shrinks, or rescales with viewing angle or camera distance!
fn mangaShadow(sh: f32, ndl: f32, fragXY: vec2f) -> f32 {
  let sunActive = smoothstep(0.35, 0.70, F.pbr.y) * smoothstep(0.03, 0.14, F.sunDir.y);
  if (sunActive <= 0.001) { return 1.0; }
  let direct = clamp(sh * max(ndl, 0.0), 0.0, 1.0);
  if (direct >= 0.42) { return 1.0; }
  let shadowAmt = smoothstep(0.42, 0.06, direct) * sunActive;
  let p = vec2u(floor(fragXY));
  let row = (p.y >> 2u) & 1u;
  let gx = (p.x + row * 2u) & 3u;
  let gy = p.y & 3u;
  var isDot = false;
  if (shadowAmt >= 0.52) {
    isDot = (gx >= 1u && gx <= 2u && gy >= 1u && gy <= 2u);
  } else if (shadowAmt >= 0.14) {
    isDot = (gx == 1u && gy == 1u);
  }
  return select(1.0, 0.72, isDot);
}
// Fast 1-tap hardware-compared shadow visibility across two locked cascades (4x-8x faster than 4-tap PCF/PCSS;
// mangaShadow turns the hardware bilinear penumbra into crisp 2x2-px manga square-dot screentone).
fn shadowSun(p: vec3f, n: vec3f, fine: bool) -> f32 {
  if (F.counts.w == 0u) { return 1.0; }
  let ndlAbs = abs(dot(n, F.sunDir.xyz));
  let nOff = mix(0.052, 0.016, ndlAbs);
  let q = shadowUV(F.shadowMat, p + n * nOff);
  let e = max(abs(q.x - 0.5), abs(q.y - 0.5));
  var s1 = 1.0;
  if (e > 0.42 || q.z >= 1.0) {
    let r = shadowUV(F.shadowMat2, p + n * mix(0.11, 0.045, ndlAbs));
    if (r.x > 0.002 && r.x < 0.998 && r.y > 0.002 && r.y < 0.998 && r.z < 1.0) {
      s1 = textureSampleCompareLevel(shadowTex2, shadowSmp, r.xy, r.z - F.fx.w);
    }
    if (e >= 0.49 || q.z >= 1.0) { return s1; }
  }
  let z = q.z - F.fx.z;
  let s0 = textureSampleCompareLevel(shadowTex, shadowSmp, q.xy, z);
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
// Forward+ Single Target Rendering: target 0 = scene HDR radiance (zero MRT G-buffer overhead)
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
  // Hammon height-correlated Smith GGX visibility (O(1), zero sqrt() calls)
  let vis = 0.5 / max(mix(2.0 * nl * nv, nl + nv, a), 0.0001);
  let om = 1.0 - max(dot(l, hv), 0.0);
  let om2 = om * om;
  let f = om2 * om2 * om;
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
// Analytical Karis/Lazarov BRDF LUT approximation (exact to <0.002, eliminates ~1M texture fetches/frame)
fn envBRDFApprox(rough: f32, nv: f32) -> vec2f {
  let c0 = vec4f(-1.0, -0.0275, -0.572, 0.022);
  let c1 = vec4f(1.0, 0.0425, 1.04, -0.04);
  let r = rough * c0 + c1;
  let a004 = min(r.x * r.x, exp2(-9.28 * nv)) * r.x + r.y;
  return vec2f(-1.04, 1.04) * a004 + r.zw;
}
// sun + diffuse and specular light of the environment (1-bounce forest floor bounce + multi-bounce AO + specOcc) + point lights + flashlight
fn shadePBR(p: vec3f, n: vec3f, w: f32, sh: f32, s: Surf) -> vec3f {
  let camVec = F.cam.xyz - p;
  let camD2 = dot(camVec, camVec);
  let v = camVec * inverseSqrt(max(camD2, 1e-6));
  let nv = max(dot(n, v), 0.001);
  let f0 = mix(vec3f(0.04), s.alb, s.metal);
  let cd = s.alb * (1.0 - s.metal);
  let a = max(s.rough * s.rough, 0.02);
  let sun = sunCol(w);
  let irr = envIrr(n, w);
  let isMatte = s.rough > 0.84 && s.metal < 0.05;
  var env = irr * 0.85;
  if (!isMatte) { env = envSpec(reflect(-v, n), s.rough, w); }
  let nlSun = max(dot(n, F.sunDir.xyz), 0.0);
  // Multi-bounce colored ambient occlusion: O(1) geometric-series approximation (zero SFU pow() calls per pixel)
  let aoScalar = 0.18 + 0.82 * s.ao;
  let aoMulti = aoScalar / max(vec3f(1.0) - s.alb * (0.55 * (1.0 - aoScalar)), vec3f(0.32));
  // Specular cone micro-occlusion & direct sun micro-shadowing in crevices (zero SFU exp2/pow)
  let specOcc = clamp(mix(s.ao, s.ao * s.ao, 1.0 - s.rough) + nv * 0.28 * s.ao, 0.14 * s.ao, 1.0);
  let sunMicroSh = clamp(sh * (0.40 + 0.60 * s.ao), 0.0, 1.0);
  var c = vec3f(0.0);
  if (nlSun > 0.0 && sh > 0.001) {
    c = cd * nlSun * sun * sh + specGGX(n, v, F.sunDir.xyz, a, f0) * sun * sunMicroSh;
  }
  var ptDiff = vec3f(0.0);
  var ptSpec = vec3f(0.0);
  var ptEnergy = 0.0;
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
    let att2 = (att * att) / (1.0 + d2 * 0.14);
    let ld = d * invD;
    let ndl = max(dot(n, ld), 0.0);
    var specL = vec3f(0.0);
    if (ndl > 0.0 && (s.rough < 0.72 || s.metal > 0.1)) { specL = specGGX(n, v, ld, a, f0) * (0.45 + 0.55 * s.ao); }
    let lCol = L.col.rgb * att2;
    ptDiff += lCol * (cd * (ndl * 0.72 + 0.28) * (0.45 + 0.55 * s.ao));
    ptSpec += lCol * specL;
    ptEnergy += dot(lCol, vec3f(0.3, 0.55, 0.15));
  }
  // When in shaded interiors lit by room lamps, suppress exterior green-grass bounce & cool outdoor sky wash so warm room fill reads naturally
  let indoorWarm = clamp(ptEnergy * 0.55, 0.0, 0.72) * (1.0 - smoothstep(0.02, 0.25, sh));
  let envScale = mix(1.0, 0.36, indoorWarm);
  c += cd * irr * aoMulti * (F.pbr.y * 0.88 * envScale);
  // 1-bounce indirect light: lush forest greenery bounce outdoors, warm plaster/oak room bounce indoors + soft sunlit terminator wrap
  let downBounce = clamp(0.55 - 0.45 * n.y, 0.0, 1.0);
  let outBounceTint = mix(vec3f(0.16, 0.23, 0.085), vec3f(0.06, 0.024, 0.02), w);
  let inBounceTint = mix(vec3f(0.14, 0.11, 0.078), vec3f(0.045, 0.025, 0.024), w);
  let bounceTint = mix(outBounceTint, inBounceTint, indoorWarm);
  c += cd * sun * bounceTint * aoMulti * (downBounce * (0.28 + 0.56 * max(F.sunDir.y, 0.05)) * (0.30 + 0.70 * F.pbr.y) * mix(1.0, 0.58, indoorWarm));
  c += cd * sun * (aoMulti * (0.042 * max(dot(n, F.sunDir.xyz) * 0.5 + 0.5, 0.0) * (1.0 - indoorWarm) * F.pbr.y));
  c += cd * vec3f(1.0, 0.76, 0.48) * (ptEnergy * 0.085 * aoMulti * (0.35 + 0.65 * indoorWarm));
  // Subtle micro-fresnel sky catchlight on grazing edges (gated so interiors & matte/front faces skip the 2nd cubemap fetch)
  let omNv = 1.0 - nv;
  let omNv2 = omNv * omNv;
  let skyEdge = (omNv2 * omNv2) * (1.0 - s.metal) * 0.14 * s.ao * (F.pbr.y * envScale) * smoothstep(0.45, 0.92, F.pbr.y) * mix(0.20, 1.0, clamp(sh * 4.0, 0.0, 1.0)) * (1.0 - indoorWarm * 0.65);
  if (skyEdge > 0.003 && !isMatte) {
    c += envSpec(n, min(s.rough, 0.35), w) * skyEdge * (0.55 + 0.45 * clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
  }
  let ab = envBRDFApprox(s.rough, nv);
  c += env * (f0 * ab.x + vec3f(ab.y)) * (F.pbr.y * specOcc * envScale);
  c += ptDiff + ptSpec;
  if (w > 0.5 && F.misc.y > 0.5) {
    let fc = flashCone(p);
    if (fc > 0.001) {
      let d = normalize(F.flashPos.xyz - p);
      c += vec3f(1.0, 0.93, 0.78) * F.flashDir.w * fc * (cd * (max(dot(n, d), 0.0) * 0.8 + 0.2) + specGGX(n, v, d, a, f0));
    }
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

struct HairU { rigSlots: vec4u, lod: vec4u };
struct HairStrand { p0w: vec4f, p1m: vec4f, p2w: vec4f, p3c: vec4f };
@group(1) @binding(0) var<uniform> H: HairU;
@group(1) @binding(1) var<storage, read> strands: array<HairStrand>;

struct HOut {
  @builtin(position) pos: vec4f,
  @location(0) wp: vec3f,
  @location(1) n: vec3f,
  @location(2) tan: vec3f,
  @location(3) col: vec3f,
  @location(4) tc: vec2f, // x: root->tip t, y: cross-rib shading
  @location(5) @interpolate(flat) hMeta: vec3u, // x: mask, y: rigId, z: seed8
  @location(6) extra: f32,
};

fn hSafeNorm(v: vec3f, fb: vec3f) -> vec3f {
  let l2 = dot(v, v);
  return select(fb, v * inverseSqrt(max(l2, 1e-8)), l2 > 1e-8);
}

@vertex fn vsHair(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> HOut {
  var o: HOut;
  o.pos = vec4f(2.0, 2.0, 2.0, 1.0);
  o.wp = vec3f(0.0);
  o.n = vec3f(0.0, 1.0, 0.0);
  o.tan = vec3f(0.0, -1.0, 0.0);
  o.col = vec3f(0.0);
  o.tc = vec2f(0.0);
  o.hMeta = vec3u(0u);
  o.extra = 1.0;
  let stride = max(H.lod.x, 1u);
  let si = ii * stride;
  if (si >= H.rigSlots.w) { return o; }

  let s = strands[si];
  let packed = bitcast<u32>(s.p1m.w);
  let rigId = packed & 15u;
  let seed8 = (packed >> 12u) & 255u;
  let baseSlot = select(select(H.rigSlots.x, H.rigSlots.y, rigId == 1u), H.rigSlots.z, rigId >= 2u);
  let rootInst = insts[baseSlot];
  let headInst = insts[baseSlot + 3u];
  if (rootInst.mask == 0u || dot(headInst.m0.xyz, headInst.m0.xyz) <= 1e-6) { return o; }

  // Fast GPU world-mask, frustum, distance & strand-density LOD cull BEFORE Bezier/wind evaluation
  let headW = vec3f(headInst.m0.y * 1.56 + headInst.m0.w, headInst.m1.y * 1.56 + headInst.m1.w, headInst.m2.y * 1.56 + headInst.m2.w);
  let wHead = worldAt(headW);
  if ((rootInst.mask & select(1u, 2u, wHead > 0.5)) == 0u) { return o; }
  let headVec = headW - F.cam.xyz;
  let headDist2 = dot(headVec, headVec);
  if (headDist2 > 400.0) { return o; }
  let headClip = F.viewProj * vec4f(headW, 1.0);
  if (headClip.w < -0.55 || abs(headClip.x) > headClip.w * 1.35 + 0.55 || abs(headClip.y) > headClip.w * 1.35 + 0.55) { return o; }
  var lodW = select(1.0, bitcast<f32>(H.lod.z), H.lod.z != 0u);
  if (headDist2 > 90.25) {
    if ((ii & 3u) != 0u) { return o; }
    lodW *= 1.95;
  } else if (headDist2 > 20.25) {
    if ((ii & 1u) != 0u) { return o; }
    lodW *= 1.42;
  }

  // Adaptive geometry: 15-vert crisp 2-segment flat ribbon on mobile/low-res (3.6x fewer micro-tris), or full 54-vert V-ribbed strand at desktop HD
  var t = 0.0;
  var lane = 1u;
  var isTip = false;
  if (H.lod.y != 0u) {
    // 15 verts per strand: 2 curved ribbon segments x 6 verts + 3 tapered tip verts
    if (vi >= 12u) {
      let vInTri = vi - 12u;
      if (vInTri == 2u) {
        t = 1.0;
        lane = 1u;
        isTip = true;
      } else {
        t = 0.80;
        lane = select(0u, 2u, vInTri == 1u);
      }
    } else {
      let seg = vi / 6u;
      let qk = vi - seg * 6u;
      let c = quadCorner(qk);
      let rIdx = seg + select(0u, 1u, c >= 2u);
      t = select(select(0.0, 0.42, rIdx == 1u), 0.80, rIdx >= 2u);
      lane = select(0u, 2u, c == 1u || c == 2u);
    }
  } else {
    // 54 verts per strand: 4 silky body segments x 12 verts (left+right V-ribbed quads) + 6 tapered tip verts
    var ring = 0u;
    if (vi >= 48u) {
      let tloc = vi - 48u;
      let subTri = tloc / 3u;
      let vInTri = tloc - subTri * 3u;
      if (vInTri == 2u) {
        ring = 5u;
        lane = 1u;
        isTip = true;
      } else {
        ring = 4u;
        lane = subTri + vInTri;
      }
    } else {
      let seg = vi / 12u;
      let loc = vi - seg * 12u;
      let subQuad = loc / 6u;
      let qk = loc - subQuad * 6u;
      let c = quadCorner(qk);
      ring = seg + select(0u, 1u, c >= 2u);
      lane = subQuad + select(0u, 1u, c == 1u || c == 2u);
    }
    t = f32(ring) * 0.20;
  }
  let omt = 1.0 - t;
  let p0 = s.p0w.xyz;
  let c1 = s.p1m.xyz;
  let c2 = s.p2w.xyz;
  let p3 = s.p3c.xyz;
  let posB = omt * omt * omt * p0 + 3.0 * omt * omt * t * c1 + 3.0 * omt * t * t * c2 + t * t * t * p3;
  let tanB = 3.0 * omt * omt * (c1 - p0) + 6.0 * omt * t * (c2 - c1) + 3.0 * t * t * (p3 - c2);

  var wpC = vec3f(dot(headInst.m0, vec4f(posB, 1.0)), dot(headInst.m1, vec4f(posB, 1.0)), dot(headInst.m2, vec4f(posB, 1.0)));
  let wTan = hSafeNorm(vec3f(dot(headInst.m0.xyz, tanB), dot(headInst.m1.xyz, tanB), dot(headInst.m2.xyz, tanB)), vec3f(0.0, -1.0, 0.0));
  let radB = hSafeNorm(posB - vec3f(0.0, 1.56, -0.01), vec3f(0.0, 1.0, 0.0));
  let wRad = hSafeNorm(vec3f(dot(headInst.m0.xyz, radB), dot(headInst.m1.xyz, radB), dot(headInst.m2.xyz, radB)), vec3f(0.0, 1.0, 0.0));

  // Dynamic inertial hair sway (reads damped spring lag/bounce from pelvis/torso slots) + organic wind flutter weighted by t^2
  let cB0 = insts[baseSlot + 1u];
  let cB1 = insts[baseSlot + 2u];
  let hLagLocal = vec3f(cB0.extra * 0.48, cB1.phase * 0.65, cB0.phase * 0.48);
  let hLagW = vec3f(dot(headInst.m0.xyz, hLagLocal), dot(headInst.m1.xyz, hLagLocal), dot(headInst.m2.xyz, hLagLocal));
  let hAct = clamp(cB1.extra, 0.08, 1.5);
  let wStr = F.wind.xy * F.wind.z;
  let sway = sin(F.cam.w * (2.4 + hAct * 1.6) + wpC.x * 5.0 + wpC.z * 4.5 + f32(seed8) * 0.05) * (0.0018 + hAct * 0.0012)
           + sin(F.cam.w * 1.1 + wpC.y * 3.0) * 0.0012;
  let tipW = t * t;
  wpC += (hLagW + vec3f(wStr.x * 0.014 + sway, -abs(sway) * 0.28, wStr.y * 0.014 + sway * 0.8)) * tipW;

  let viewDir = hSafeNorm(F.cam.xyz - wpC, vec3f(0.0, 0.0, 1.0));
  let blendDir = hSafeNorm(mix(viewDir, wRad, 0.38), wRad);
  let side = hSafeNorm(cross(wTan, blendDir), hSafeNorm(cross(wTan, viewDir), vec3f(1.0, 0.0, 0.0)));
  let outN = hSafeNorm(cross(side, wTan), wRad);

  let dist = distance(wpC, F.cam.xyz);
  let wPhys = mix(s.p0w.w, s.p2w.w, t) * lodW;
  let minPixW = dist * 0.00125;
  let wHalf = select(max(wPhys, minPixW) * (1.0 - t * 0.16), 0.0, isTip);

  var wp = wpC;
  var nV = outN;
  var crossSh = 1.0;
  if (lane == 0u) {
    wp -= side * wHalf;
    nV = hSafeNorm(mix(outN, -side, 0.62), outN);
    crossSh = 0.85;
  } else if (lane == 1u) {
    if (!isTip) { wp += outN * (wHalf * 0.58); }
    crossSh = 1.07;
  } else {
    wp += side * wHalf;
    nV = hSafeNorm(mix(outN, side, 0.62), outN);
    crossSh = 0.89;
  }

  let rgb24 = bitcast<u32>(s.p3c.w);
  let rgb = vec3f(f32((rgb24 >> 16u) & 255u), f32((rgb24 >> 8u) & 255u), f32(rgb24 & 255u)) / 255.0;
  let cLin = (rgb * rgb) * (0.8 + 0.2 * rgb);

  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.wp = wp;
  o.n = hSafeNorm(mix(nV, wRad, 0.45), wRad);
  o.tan = wTan;
  o.col = cLin;
  o.tc = vec2f(t, crossSh);
  o.hMeta = vec3u(rootInst.mask, rigId, seed8);
  o.extra = 1.0;
  return o;
}

@fragment fn fsHair(i: HOut) -> @location(0) vec4f {
  // Zero-discard fragment shader: world-mask culling moved to vsHair -> re-enables Hardware Early-Z & Forward Pixel Kill on Mali/Adreno!
  let w = worldAt(i.wp);
  let night = w > 0.5;
  let n = hSafeNorm(i.n, vec3f(0.0, 1.0, 0.0));
  let tang = hSafeNorm(i.tan, vec3f(0.0, -1.0, 0.0));
  let t = clamp(i.tc.x, 0.0, 1.0);
  let camV = F.cam.xyz - i.wp;
  let dist2 = dot(camV, camV);
  let dist = sqrt(dist2);
  var sh = 1.0;
  if ((i.hMeta.x & 16u) == 0u) {
    if (dot(n, F.sunDir.xyz) > 0.0) { sh = shadowSun(i.wp, n, false); } else { sh = 0.0; }
  }

  // Smooth root-to-tip melanin gradient with clean low-noise tone (integer hash: zero SFU sin)
  let rootAO = 0.52 + 0.48 * smoothstep(0.0, 0.54, t);
  let strandGrain = (f32(hashu((i.hMeta.z * 747796405u) ^ (u32(t * 10.0) * 2891336453u)) & 255u) / 255.0 - 0.5) * 0.035 * (1.0 - smoothstep(2.0, 7.0, dist));
  let ao = clamp(rootAO * i.tc.y, 0.36, 1.0);
  let tipTint = mix(vec3f(0.76, 0.72, 0.68), vec3f(0.98, 0.93, 0.88), smoothstep(0.24, 0.94, t));
  let alb = i.col * tipTint * (1.0 + strandGrain);

  // Soft matte-silky hair PBR base with crisp manga square-dot shadow shading
  let msH = mangaShadow(sh, dot(n, F.sunDir.xyz), i.pos.xy);
  var col = shadePBR(i.wp, n, w, sh, Surf(alb * msH, 0.88, 0.0, ao));

  // Subdued natural Marschner 3-lobe anisotropic hair sheen (pure multiplies: zero SFU pow()!)
  if (dist < 6.5) {
    let v = camV * inverseSqrt(max(dist2, 1e-6));
    let t1 = hSafeNorm(tang - n * 0.09, tang);
    let t2 = hSafeNorm(tang + n * 0.15, tang);
    let kkGate = mix(0.20, 1.0, sh) * (0.28 + 0.72 * F.pbr.y) * smoothstep(0.06, 0.40, t);
    if (kkGate > 0.02) {
      let hSun = normalize(F.sunDir.xyz + v);
      let d1 = dot(t1, hSun);
      let d2 = dot(t2, hSun);
      let st1_2 = max(0.0, 1.0 - d1 * d1);
      let st1_4 = st1_2 * st1_2; let st1_8 = st1_4 * st1_4; let st1_16 = st1_8 * st1_8; let st1_32 = st1_16 * st1_16;
      let st2_2 = max(0.0, 1.0 - d2 * d2);
      let st2_4 = st2_2 * st2_2; let st2_8 = st2_4 * st2_4;
      let sunC = sunCol(w);
      let rTint = mix(alb, vec3f(0.92, 0.86, 0.80), 0.26);
      let rLobe = rTint * sunC * st1_32 * 0.032;
      let trtLobe = (alb * vec3f(1.12, 0.88, 0.72)) * sunC * (st2_8 * st2_2 * sqrt(st2_2)) * 0.085;
      let ttBase = max(dot(-v, F.sunDir.xyz), 0.0);
      let tt2 = ttBase * ttBase;
      let ttForward = (tt2 * tt2) * (0.24 + 0.76 * t) * (1.0 - abs(dot(n, v)) * 0.45);
      let ttLobe = (alb * vec3f(1.22, 0.86, 0.58)) * sunC * ttForward * 0.075;
      col += (rLobe + trtLobe + ttLobe) * kkGate;
    }

    // Subdued warm indoor/lamp Marschner sheen (close portrait range only, zero SFU pow)
    if (dist < 3.2 && F.counts.x > 0u) {
      let wm = select(1u, 2u, night);
      for (var li = 0u; li < F.counts.x; li++) {
        let L = F.lights[li];
        if ((u32(L.col.w) & wm) == 0u) { continue; }
        let ldVec = L.pos.xyz - i.wp;
        let d2l = dot(ldVec, ldVec);
        let r = L.pos.w;
        if (d2l >= r * r) { continue; }
        let invD = inverseSqrt(max(d2l, 0.0001));
        let lDir = ldVec * invD;
        let att = 1.0 - d2l * invD / r;
        let att2 = (att * att) / (1.0 + d2l * 0.14);
        if (att2 < 0.015) { continue; }
        let hPt = normalize(lDir + v);
        let pd1 = dot(t1, hPt);
        let pd2 = dot(t2, hPt);
        let ps1_2 = max(0.0, 1.0 - pd1 * pd1);
        let ps1_4 = ps1_2 * ps1_2; let ps1_8 = ps1_4 * ps1_4; let ps1_16 = ps1_8 * ps1_8;
        let ps2_2 = max(0.0, 1.0 - pd2 * pd2);
        let ps2_4 = ps2_2 * ps2_2;
        let ptB = max(dot(-v, lDir), 0.0);
        let ptTT = (ptB * ptB * ptB) * (0.22 + 0.78 * t);
        let ptSpecCol = mix(alb, vec3f(0.95, 0.88, 0.82), 0.20);
        col += L.col.rgb * (att2 * (0.26 + 0.46 * t)) * (ptSpecCol * (ps1_16 * ps1_8 * ps1_4) * 0.022 + alb * (ps2_4 * ps2_4 * ps2_2) * 0.055 + alb * vec3f(1.12, 0.82, 0.58) * ptTT * 0.045);
      }
    }
  }

  col += vec3f(1.0, 0.32, 0.22) * waveRim(i.wp) * 1.4;
  col = flatFog(col, i.wp, w);
  return vec4f(col, 1.0);
}
