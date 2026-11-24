
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

@group(1) @binding(0) var<storage, read> faces: array<u32>;
struct TV { wp: vec3f, aoD: f32, aoN: f32, dir: u32, edgeMask: u32, mask: u32, matD: u32, matN: u32, du: f32, dv: f32, c: u32 };
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
  t.c = c;
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
  let fl = select(u32(mats[t.matD * 2u].w) | u32(mats[t.matN * 2u].w), u32(mats[select(t.matD, t.matN, WMODE == 1u) * 2u].w), WMODE < 2u);
  var wp = t.wp;
  if ((fl & 4u) != 0u && u32(mats[t.matD * 2u + 1u].w) != 21u) { // foliage sways, window glass does not
    let tt = F.cam.w;
    wp.x += sin(tt * 1.3 + wp.z * 0.45 + wp.y * 0.3) * 0.035;
    wp.z += cos(tt * 1.1 + wp.x * 0.4) * 0.03;
  }
  var o: TOut;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.wp = wp;
  o.ao = vec4f(t.aoD, t.aoN, textureSampleLevel(noise3, repSmp, wp * vec3f(0.016, 0.04, 0.016), 0.0).r,
    textureSampleLevel(noise3, repSmp, wp * vec3f(0.07, 0.1, 0.07) + vec3f(0.37), 0.0).r);
  o.info = vec4u(t.dir | (t.edgeMask << 3u) | (u32(t.du) << 8u) | (u32(t.dv) << 16u), t.mask, t.matD, t.matN);
  o.quadUV = vec2f(cuOf(t.c) * t.du, cvOf(t.c) * t.dv);
  return o;
}
// water: corner offsets from the mesher make ramps at steps; ao.x carries the foam amount
@vertex fn vsWater(@builtin(vertex_index) vi: u32) -> TOut {
  let fi = vi / 6u;
  let k = vi - fi * 6u;
  let w0 = faces[fi * 3u]; let w1 = faces[fi * 3u + 1u]; let w2 = faces[fi * 3u + 2u];
  let dir = (w0 >> 15u) & 7u;
  let mask = (w0 >> 18u) & 3u;
  let matD = (w1 >> 16u) & 255u;
  let matN = (w1 >> 24u) & 255u;
  let c = quadCorner(k);
  var lp = vec3f(f32(w0 & 31u), f32((w0 >> 5u) & 31u), f32((w0 >> 10u) & 31u)) + faceOffset(dir, c, 1.0, 1.0);
  let f = (w1 >> (c * 2u)) & 3u;
  if (matD == 15u) {
    if (f == 1u) { lp.y -= 0.5; } else if (f == 2u) { lp.y += 0.5; }
  }
  var wp = (chunkOrg[w2 & 0xffffu].xyz + lp) * 0.125;
  var o: TOut;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.wp = wp;
  // subtle foam at the foot of each little fall
  o.ao = vec4f(select(0.0, 0.42, matD == 15u && f == 2u && dir == 2u), 0.0, 0.5, 0.5);
  o.info = vec4u(dir, mask, matD, matN);
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
// Analytical screen-space band-limited groove filter:
// Evaluates line distance in exact screen pixels (dPx = d / fw) with a constant-minimum pixel kernel (>= 0.80 px half-width)
// and energy conservation, eliminating thick/thin Vernier phase oscillation and oblique-angle Moiré twisting.
fn aaLine(coord: f32, fwIn: f32, physWidth: f32) -> f32 {
  let fw = max(fwIn, 1e-5);
  let nyq = 1.0 - smoothstep(0.18, 0.38, fw);
  if (nyq <= 0.001) { return 0.0; }
  let d = abs(fract(coord + 0.5) - 0.5);
  let dPx = d / fw;
  let wPx = physWidth / fw;
  let halfPx = clamp(wPx * 0.5, 0.80, 2.4);
  let cov = 1.0 - smoothstep(halfPx - 0.68, halfPx + 0.88, dPx);
  let energy = clamp((wPx * 0.5) / halfPx, 0.36, 1.0);
  return cov * energy * nyq;
}
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
  let dist = distance(i.wp, F.cam.xyz);
  let pat = u32(m1.w);
  let ax = dir >> 1u;
  let dwpDx = dpdx(i.wp);
  let dwpDy = dpdy(i.wp);
  let lx = length(dwpDx);
  let ly = length(dwpDy);
  let voxFoot = max(lx, ly) * 8.0;
  let voxAA = 1.0 / (1.0 + voxFoot * voxFoot * 8.0);
  // Architectural surfaces (planks, plaster, brick, roof, tile, parquet, concrete, paint, slate) use continuous surface
  // shading rather than per-voxel 12.5cm checkerboard brightness jumps that fight with structural board/brick lines
  let isArch = pat == 7u || pat == 8u || pat == 9u || pat == 10u || pat == 13u || pat == 21u || pat == 22u || pat == 23u || pat == 24u || pat >= 26u;
  // Natural terrain slope steps (both horizontal treads ax==1 and vertical risers up to 8 voxels / 1.0m) shade as one continuous hillside so 3D elevation contours never form circular Moiré rings
  let vertH = select(dvF, duF, dir == 0u || dir == 5u);
  let isSlopeStep = !isArch && (ax == 1u || vertH <= 8.0);
  if (isSlopeStep && ax != 1u) {
    let upBlend = mix(0.38, 0.78, smoothstep(6.0, 18.0, dist));
    n = normalize(mix(baseN, vec3f(0.0, 1.0, 0.0), upBlend));
  }
  let natFade = voxAA * (1.0 - smoothstep(4.5, 9.0, dist));
  let voxVarScale = select(natFade * 0.22, 0.12 * voxAA, isArch);
  let vk = 1.0 + (h - 0.5) * 0.45 * m1.y * voxVarScale;
  // ─── Discrete per-cube solid brightness step (faded out on slopes/distance to prevent staircase Moiré) ───
  let vStyle = u32(F.grass.w + 0.5);
  let vClusterH = hash3i(vec3i(blockCoord.x >> 2, blockCoord.y >> 2, blockCoord.z >> 2));
  let voxQuantShade = mix(1.0, 0.92 + floor(h * 5.0) * 0.038, voxVarScale);
  let clusterShade = mix(1.0, 0.96 + floor(vClusterH * 3.0) * 0.035, select(natFade * 0.25, 0.25 * voxAA, isArch));

  // ─── Per-voxel UV inside merged or single quads ───
  let uQuad = fract(i.quadUV.x);
  let vQuad = fract(i.quadUV.y);
  let voxelEdge = min(min(uQuad, 1.0 - uQuad), min(vQuad, 1.0 - vQuad));
  let nearFade = select((1.0 - smoothstep(3.5, 7.5, dist)) * natFade, 0.0, isArch || isSlopeStep);

  // Subtle physical edge bevel for close vertical cliffs only (disabled on slope steps and architecture to prevent grid/ring Moiré)
  var cubeOcc = 1.0;
  var cubeRidge = 1.0;
  let edgeSpan = max(0.11, voxFoot * 0.95);
  if (voxelEdge < edgeSpan && nearFade > 0.01) {
    let edgeT = smoothstep(edgeSpan, 0.0, voxelEdge) * nearFade;
    cubeOcc *= mix(1.0, 0.96, edgeT);
  }

  // Solid albedo per physical voxel; slight riser darkening gives hillside steps 3D relief
  let cubeCol = m0.rgb * (1.0 + (h - 0.5) * 0.08 * voxVarScale);
  var albedo = cubeCol * vk * clusterShade * voxQuantShade * cubeRidge;
  if (isSlopeStep && ax != 1u) {
    albedo *= mix(0.84, 0.94, smoothstep(4.0, 14.0, dist));
  }

  // Step Edge Shading along macro 90-degree block turns (disabled on natural terrain slope steps so step lips never glow or band)
  var stepEdgeDist = 1.0;
  if ((edgeMask & 1u) != 0u) { stepEdgeDist = min(stepEdgeDist, i.quadUV.x); }
  if ((edgeMask & 2u) != 0u) { stepEdgeDist = min(stepEdgeDist, max(0.0, duF - i.quadUV.x)); }
  if ((edgeMask & 4u) != 0u) { stepEdgeDist = min(stepEdgeDist, i.quadUV.y); }
  if ((edgeMask & 8u) != 0u) { stepEdgeDist = min(stepEdgeDist, max(0.0, dvF - i.quadUV.y)); }
  if (!isSlopeStep) {
    let stepSpan = max(0.14, voxFoot * 1.25);
    let edgeDarken = mix(0.97, 1.0, smoothstep(0.0, stepSpan, stepEdgeDist));
    albedo *= mix(1.0, edgeDarken, voxAA);
  }

  // On tall vertical cliff cuts of grass (> 6 voxels high), show underlying soil tone
  if (ax != 1u && !isSlopeStep && (pat == 1u || pat == 14u || pat == 17u)) {
    let soilShade = 0.90 + floor(h * 4.0) * 0.05;
    albedo = mix(albedo, vec3f(0.30, 0.20, 0.12) * soilShade, 0.22 * natFade);
  }

  // Smooth macro-biome tint + multi-scale world-space botanical variation (zero periodic tiling; skip 3D noise fetches on indoor/arch surfaces)
  let n1 = i.ao.z;
  let n2 = i.ao.w;
  let rawAoInit = select(i.ao.x, i.ao.y, night);
  var wNoiseMacro = 0.5;
  var wNoiseMeso = 0.5;
  if (!isArch) {
    if (dist < 22.0) {
      wNoiseMeso = textureSampleLevel(noise3, repSmp, i.wp * 0.34 + vec3f(0.37, 0.19, 0.71), 0.0).r;
    }
    if (pat == 1u || pat == 14u || pat == 6u || pat == 16u || pat == 17u || pat == 2u || pat == 3u || pat == 15u) {
      wNoiseMacro = textureSampleLevel(noise3, repSmp, i.wp * 0.085, 0.0).r;
    }
  }
  if (pat == 1u || pat == 14u || pat == 6u || pat == 16u || pat == 17u) {
    var mWaveA = wNoiseMacro;
    var mWaveB = wNoiseMeso;
    if (dist < 18.0) {
      mWaveA = 0.5 + 0.5 * sin(i.wp.x * 0.42 + cos(i.wp.z * 0.37) * 1.8) * cos(i.wp.z * 0.39 - sin(i.wp.x * 0.29) * 1.4);
      mWaveB = 0.5 + 0.5 * sin(i.wp.x * 1.35 - i.wp.z * 1.12 + sin(i.wp.z * 0.85) * 1.6);
    }
    let meadowTint = mix(vec3f(0.76, 0.98, 0.72), vec3f(1.12, 1.10, 0.82), mix(mWaveA, wNoiseMacro, 0.45));
    let cloverTint = mix(vec3f(0.84, 0.98, 0.82), vec3f(1.10, 1.06, 0.90), mix(mWaveB, wNoiseMeso, 0.50));
    let sunLush = mix(vec3f(0.92, 0.99, 0.95), vec3f(1.10, 1.04, 0.86), smoothstep(0.42, 0.78, wNoiseMacro) * smoothstep(0.65, 0.95, rawAoInit));
    albedo *= mix(vec3f(1.06, 1.02, 0.86), vec3f(0.80, 1.04, 0.88), smoothstep(0.25, 0.75, n1)) * meadowTint * cloverTint * sunLush * (0.86 + n2 * 0.16 + (wNoiseMeso - 0.5) * 0.18);
  } else if (!isArch) {
    albedo *= mix(vec3f(1.05, 1.01, 0.94), vec3f(0.92, 0.98, 1.04), n1) * (0.86 + n2 * 0.18 + (wNoiseMeso - 0.5) * 0.16);
  } else {
    albedo *= mix(vec3f(1.03, 1.0, 0.95), vec3f(0.94, 0.98, 1.02), n1) * (0.92 + n2 * 0.16);
  }

  // ─── Vertical Cliff Risers (only on tall non-slope faces > 0.75m, band-limited by natFade) ───
  if (ax != 1u && !isSlopeStep) {
    let voxRow = u32(blockCoord.y) & 7u;
    let colShift = u32(vClusterH * 2.0);
    if (pat == 1u || pat == 14u || pat == 17u) {
      if (voxRow >= 5u + (colShift & 1u)) {
        albedo *= mix(1.0, 1.01, natFade);
      } else if (voxRow >= 2u) {
        albedo *= mix(vec3f(1.0), vec3f(0.97, 0.94, 0.90), natFade);
      } else {
        let pebble = select(0.96, 1.05, h > 0.72);
        albedo *= mix(vec3f(1.0), vec3f(0.94, 0.92, 0.90) * pebble, natFade);
      }
    } else if (pat == 2u || pat == 12u || pat == 11u) {
      if (voxRow >= 6u) {
        albedo *= mix(vec3f(1.0), vec3f(0.95, 0.93, 0.90), natFade);
      } else if (voxRow < 2u) {
        let pebble = select(0.95, 1.05, h > 0.68);
        albedo *= mix(vec3f(1.0), vec3f(0.94, 0.92, 0.90) * pebble, natFade);
      }
    } else if (pat == 3u || pat == 15u || pat == 18u) {
      let strataIdx = (blockCoord.y >> 1) + i32((vClusterH - 0.5) * 2.0);
      let strataHash = f32(hashu(bitcast<u32>(strataIdx) * 747796405u) & 1023u) / 1023.0;
      let strataTint = mix(vec3f(0.93, 0.91, 0.88), vec3f(1.06, 1.04, 1.01), strataHash);
      albedo *= mix(vec3f(1.0), strataTint, 0.26 * natFade);
    } else if (pat == 4u || pat == 5u) {
      let horizCoord = select(i.wp.x, i.wp.z, ax == 0u);
      let fiberIdx = bitcast<u32>(i32(floor(horizCoord * 16.0)));
      let yIdx = bitcast<u32>(i32(floor(i.wp.y * 4.0)));
      let fiberHash = f32(hashu((fiberIdx * 37u) ^ (yIdx * 19349663u)) & 1023u) / 1023.0;
      albedo *= mix(1.0, mix(0.95, 1.03, fiberHash), voxAA);
    }
  }

  // ─── Blast Scorch & Soot Voxels on Fractured Crater Surfaces ───
  if (pat == 18u) {
    let soot = 0.56 + 0.44 * floor(h * 4.0) / 3.0;
    albedo *= vec3f(soot * 0.78, soot * 0.73, soot * 0.70);
  }

  // Smooth moss patches & humus soil variation across natural terrain (grass, dirt, stone, cliff)
  var worldMossMask = 0.0;
  if ((pat == 1u || pat == 2u || pat == 3u || pat == 14u || pat == 15u || pat == 16u || pat == 17u) && (baseN.y > 0.45 || isSlopeStep)) {
    worldMossMask = smoothstep(0.55, 0.78, wNoiseMacro * 0.65 + (1.0 - wNoiseMeso) * 0.35) * smoothstep(0.95, 0.58, rawAoInit);
    if (pat == 3u || pat == 15u) {
      let mossPatch = smoothstep(0.54, 0.74, max(n1, worldMossMask));
      albedo = mix(albedo, vec3f(0.11, 0.22, 0.06) * voxQuantShade, mossPatch * 0.68);
    } else if (pat != 16u) {
      albedo = mix(albedo, vec3f(0.085, 0.20, 0.055) * voxQuantShade, worldMossMask * 0.38);
    }
  }
  // Procedural world-space relief stones & embedded pebbles on ground/paths/grass margins
  var worldStoneMask = 0.0;
  var worldStoneRim = 0.0;
  var worldStoneTone = 0.5;
  var worldStoneGrad = vec2f(0.0);
  if (!isArch && dist < 14.0 && (ax == 1u || isSlopeStep) && (pat == 1u || pat == 2u || pat == 11u || pat == 12u || pat == 14u)) {
    let pCellF = i.wp.xz * 2.25;
    let pCell = vec2i(floor(pCellF));
    let pSeed = (bitcast<u32>(pCell.x) * 73856093u) ^ (bitcast<u32>(pCell.y) * 19349663u);
    let hPresence = f32(hashu(pSeed) & 1023u) / 1023.0;
    let stoneChance = select(0.26, 0.58, pat == 2u || pat == 11u || pat == 12u);
    if (hPresence < stoneChance) {
      let ox = 0.28 + 0.44 * (f32(hashu(pSeed + 17u) & 1023u) / 1023.0);
      let oz = 0.28 + 0.44 * (f32(hashu(pSeed + 31u) & 1023u) / 1023.0);
      let dp = fract(pCellF) - vec2f(ox, oz);
      let aspect = 0.85 + 0.35 * (f32(hashu(pSeed + 47u) & 1023u) / 1023.0);
      let dpScaled = vec2f(dp.x * aspect, dp.y);
      let rMax = 0.11 + 0.14 * (f32(hashu(pSeed + 61u) & 1023u) / 1023.0);
      let rNorm = length(dpScaled) / rMax;
      if (rNorm < 1.15) {
        worldStoneRim = smoothstep(0.85, 1.02, rNorm) * (1.0 - smoothstep(1.02, 1.15, rNorm));
        worldStoneMask = 1.0 - smoothstep(0.82, 1.02, rNorm);
        worldStoneTone = f32(hashu(pSeed + 79u) & 1023u) / 1023.0;
        worldStoneGrad = (-dpScaled / max(rMax * rMax, 0.005)) * worldStoneMask * 0.16;
      }
    }
  }
  let flags = u32(m0.w);
  // Strong natural & architectural ambient occlusion (multi-scale horizon + vertex AO)
  let aoStrength = select(mix(0.84, 0.52, smoothstep(8.0, 28.0, dist)), 0.94, isArch);
  let rawAo = mix(1.0, rawAoInit, aoStrength);
  let cAo = clamp(rawAo, 0.03, 1.0);
  let macroAo = mix(rawAo, cAo * sqrt(cAo), select(0.78, 0.90, vStyle == 2u));
  var ao = clamp(macroAo * cubeOcc, 0.04, 1.0);
  // ─── PBR surface: material values, refined near the camera by the atlas + real-time heightmap normal relief ───
  var rough = m1.z;
  var metal = f32((flags >> 8u) & 15u) / 15.0;
  var wetMask = 0.5;
  // Crisp nearest-neighbor pixel art at close range (m0u == 0) + smooth linear minification at mid/far (m0u >= 1):
  // eliminates growing/shrinking square mip blocks on house roofs/walls AND halves distant atlas fetches (4 -> 2)!
  let fw = max(lx, ly) * 2.0 * ATILEF;
  let mipF = clamp(log2(max(fw, 1.0)), 0.0, 4.0);
  let m0u = u32(floor(mipF));
  let mipBlend = fract(mipF);
  let detail = select((1.0 - smoothstep(18.0, 38.0, dist)) * 0.98, 1.0 - smoothstep(24.0, 42.0, dist), isArch) / (1.0 + max(0.0, fw - 1.8) * 0.10);
  if (detail > 0.01) {
    let lv = i.wp * 2.0;
    var st = lv.xy;
    var ua = vec3f(1.0, 0.0, 0.0);
    var va = vec3f(0.0, 1.0, 0.0);
    if (ax == 1u || isSlopeStep) {
      st = select(lv.xz + baseN.xz * fract(lv.y), lv.xz, ax == 1u);
      ua = vec3f(1.0, 0.0, 0.0);
      va = vec3f(0.0, 0.0, 1.0);
    } else if (ax == 0u) { st = lv.zy; ua = vec3f(0.0, 0.0, 1.0); }
    let uvTile = vec2f(fract(st.x), 1.0 - fract(st.y));
    let fcl = select(select(1u, select(2u, 0u, dir == 2u), ax == 1u), 0u, isSlopeStep);
    let vrPos = select(lv - baseN * 0.02, vec3f(lv.x, 0.0, lv.z), isSlopeStep);
    var vr = u32(hash3i(vec3i(floor(vrPos))) * 4.0) & 3u;
    if (!isArch) {
      let tCell = vec2i(floor(st));
      let tHash = hashu((bitcast<u32>(tCell.x) * 73856093u) ^ (bitcast<u32>(tCell.y) * 19349663u) ^ (mat * 83492791u));
      vr = tHash & 3u;
    }
    let org = vec2u((fcl * 4u + vr) * ATILE, mat * ATILE);
    let tilePx0 = f32(ATILE >> m0u);
    let invAt0 = 1.0 / vec2f(12.0 * tilePx0, 112.0 * tilePx0);
    let loc0 = clamp(uvTile * tilePx0, vec2f(0.5), vec2f(tilePx0 - 0.5));
    let uv0 = (vec2f(org >> vec2u(m0u)) + loc0) * invAt0;
    var tx = vec4f(0.25, 0.25, 0.25, 0.5);
    var pb = vec4f(rough, metal, 1.0, 0.5);
    if (m0u == 0u) {
      tx = textureSampleLevel(atlas, repSmp, uv0, f32(m0u));
      pb = textureSampleLevel(atlasPbr, repSmp, uv0, f32(m0u));
      if (mipBlend > 0.45) {
        let tB = smoothstep(0.45, 1.0, mipBlend);
        let tilePx1 = f32(ATILE >> 1u);
        let invAt1 = 1.0 / vec2f(12.0 * tilePx1, 112.0 * tilePx1);
        let loc1 = clamp(uvTile * tilePx1, vec2f(0.5), vec2f(tilePx1 - 0.5));
        let uv1 = (vec2f(org >> vec2u(1u)) + loc1) * invAt1;
        tx = mix(tx, textureSampleLevel(atlas, linSmp, uv1, 1.0), tB);
        pb = mix(pb, textureSampleLevel(atlasPbr, linSmp, uv1, 1.0), tB);
      }
    } else {
      tx = textureSampleLevel(atlas, linSmp, uv0, f32(m0u));
      pb = textureSampleLevel(atlasPbr, linSmp, uv0, f32(m0u));
      if (m0u < 4u && mipBlend > 0.20 && mipBlend < 0.80) {
        let m1u = m0u + 1u;
        let tB = smoothstep(0.20, 0.80, mipBlend);
        let tilePx1 = f32(ATILE >> m1u);
        let invAt1 = 1.0 / vec2f(12.0 * tilePx1, 112.0 * tilePx1);
        let loc1 = clamp(uvTile * tilePx1, vec2f(0.5), vec2f(tilePx1 - 0.5));
        let uv1 = (vec2f(org >> vec2u(m1u)) + loc1) * invAt1;
        tx = mix(tx, textureSampleLevel(atlas, linSmp, uv1, f32(m1u)), tB);
        pb = mix(pb, textureSampleLevel(atlasPbr, linSmp, uv1, f32(m1u)), tB);
      }
    }
    albedo *= mix(vec3f(1.0), tx.rgb * 4.0, detail); // the atlas stores colour / material mean x 0.25
    if (worldStoneMask > 0.01) {
      let stoneTint = mix(vec3f(0.21, 0.20, 0.18), vec3f(0.34, 0.31, 0.27), worldStoneTone);
      albedo = mix(albedo, stoneTint * voxQuantShade, worldStoneMask * 0.85 * detail);
    }
    if (worldStoneRim > 0.01) { albedo *= mix(1.0, 0.74, worldStoneRim * detail); }
    rough = mix(rough, pb.r, detail);
    if (worldMossMask > 0.01) { rough = mix(rough, 0.80, worldMossMask * 0.45 * detail); }
    if (worldStoneMask > 0.01) { rough = mix(rough, 0.56, worldStoneMask * detail); }
    metal = mix(metal, pb.g, detail);
    ao *= mix(1.0, pb.b, detail) * mix(1.0, 0.86, worldStoneMask * 0.35);
    wetMask = pb.a;

    // Real-time tangent-space normal perturbation from the atlas heightmap (tx.a) at close range only (m0u == 0)
    let bumpFade = detail * (1.0 - smoothstep(5.0, 9.0, dist));
    if (bumpFade > 0.02 && m0u == 0u) {
      let loc0R = clamp(loc0 + vec2f(1.0, 0.0), vec2f(0.5), vec2f(tilePx0 - 0.5));
      let loc0U = clamp(loc0 - vec2f(0.0, 1.0), vec2f(0.5), vec2f(tilePx0 - 0.5));
      let hRight = textureSampleLevel(atlas, repSmp, (vec2f(org >> vec2u(m0u)) + loc0R) * invAt0, f32(m0u)).a;
      let hUp = textureSampleLevel(atlas, repSmp, (vec2f(org >> vec2u(m0u)) + loc0U) * invAt0, f32(m0u)).a;
      let bumpStr = select(3.0, 1.75, isArch) * bumpFade;
      let wBump = select(vec3f((wNoiseMeso - 0.5) * 0.24 + worldStoneGrad.x, 0.0, (wNoiseMacro - 0.5) * 0.24 + worldStoneGrad.y), vec3f(0.0), isArch);
      n = normalize(n + (ua * (tx.a - hRight) + va * (tx.a - hUp)) * bumpStr + wBump * bumpFade);
    }

    // ─── Analytical Band-Limited Architectural Seams (constant screen-pixel thickness, zero Moiré twisting) ───
    // Gate seam derivative projections behind architectural seam patterns so natural terrain skips 2 sqrt + 4 dot per pixel
    if (pat == 7u || pat == 22u || pat == 28u || pat == 10u || pat == 30u || pat == 13u || pat == 33u || pat == 9u || pat == 29u || pat == 38u) {
      let fwStX = length(vec2f(dot(dwpDx, ua), dot(dwpDy, ua))) * 2.0;
      let fwStY = length(vec2f(dot(dwpDx, va), dot(dwpDy, va))) * 2.0;
      if (pat == 7u || pat == 22u || pat == 28u) {
        // Wooden boards (PLANK walls/ceilings, FLOOR, DOOR, PAINT): 4 boards per 0.5 m (12.5 cm wide)
        let across = select(st.y, st.x, pat == 22u || ax == 1u);
        let along = select(st.x, st.y, pat == 22u || ax == 1u);
        let fwAcross = select(fwStY, fwStX, pat == 22u || ax == 1u);
        let fwAlong = select(fwStX, fwStY, pat == 22u || ax == 1u);
        let boardCoord = across * 4.0;
        let seamH = aaLine(boardCoord, fwAcross * 4.0, 0.055);
        // Staggered rare butt-joints every 2.0 m (only 1 in 2 boards, integer hash: zero SFU sin)
        let bIdx = bitcast<u32>(i32(floor(boardCoord)));
        let buttShift = f32(hashu((bIdx * 747796405u) ^ (mat * 2891336453u)) & 1023u) / 1023.0;
        let aIdx = bitcast<u32>(i32(floor(along * 0.25 + buttShift)));
        let plankVar = f32(hashu((bIdx * 2654435761u) ^ (aIdx * 1597334677u)) & 1023u) / 1023.0;
        albedo *= 0.94 + plankVar * 0.11;
        rough = clamp(rough + (plankVar - 0.5) * 0.24, 0.16, 0.94);
        let seamV = aaLine(along * 0.25 + buttShift, fwAlong * 0.25, 0.014) * step(0.45, buttShift) * (1.0 - seamH);
        let seam = max(seamH, seamV * 0.65);
        albedo *= mix(1.0, 0.52, seam);
        ao *= mix(1.0, 0.68, seam);
        rough = mix(rough, min(1.0, rough + 0.16), seam);
      } else if (pat == 10u) {
        // Brick courses (BRICK, HEARTH, BRICK_SILICATE): 8 courses per 0.5 m (6.25 cm), staggered stretchers/headers
        let rowCoord = st.y * 8.0;
        let rowIdx = floor(rowCoord);
        let isHeader = (i32(rowIdx) & 1) != 0;
        let colFreq = select(2.0, 4.0, isHeader);
        let colOff = select(0.0, 0.5, (i32(rowIdx) & 2) != 0);
        let mortarH = aaLine(rowCoord, fwStY * 8.0, 0.075);
        let mortarV = aaLine(st.x * colFreq + colOff, fwStX * colFreq, 0.055) * (1.0 - mortarH);
        let mortar = max(mortarH, mortarV);
        let mortarCol = select(vec3f(0.42, 0.39, 0.35), m0.rgb * 0.78, mat == 54u);
        albedo = mix(albedo, mortarCol, mortar * 0.78);
        ao *= mix(1.0, 0.76, mortar);
      } else if (pat == 30u || pat == 13u) {
        // Glazed tiles & mosaic grout
        let grout = max(aaLine(st.x * 4.0, fwStX * 4.0, 0.055), aaLine(st.y * 4.0, fwStY * 4.0, 0.055));
        albedo = mix(albedo, albedo * 0.58, grout);
        ao *= mix(1.0, 0.75, grout);
      } else if (pat == 33u) {
        // Varnished long dark-walnut floorboards (PARQUET): 4 planks per 0.5 m with staggered butt-joints & glossy specular varnish variation
        let boardCoord = st.x * 4.0;
        let bIdx = bitcast<u32>(i32(floor(boardCoord)));
        let buttShift = f32(hashu((bIdx * 747796405u) ^ 7331u) & 1023u) / 1023.0;
        let aIdx = bitcast<u32>(i32(floor(st.y * 0.45 + buttShift)));
        let plankVar = f32(hashu((bIdx * 2654435761u) ^ (aIdx * 1597334677u)) & 1023u) / 1023.0;
        let seamH = aaLine(boardCoord, fwStX * 4.0, 0.055);
        let seamV = aaLine(st.y * 0.45 + buttShift, fwStY * 0.45, 0.016) * (1.0 - seamH);
        let pq = max(seamH, seamV * 0.72);
        albedo *= (0.86 + plankVar * 0.24) * mix(1.0, 0.48, pq);
        ao *= mix(1.0, 0.66, pq);
        rough = mix(clamp(rough * 0.72 + (plankVar - 0.5) * 0.14, 0.13, 0.42), 0.78, pq);
      } else if (pat == 9u || pat == 29u) {
        // Standing-seam roof iron & corrugated slate sheets
        let freqX = select(1.0, 4.0, pat == 29u);
        let seam = max(aaLine(st.x * freqX, fwStX * freqX, 0.045), aaLine(st.y * 1.0, fwStY, 0.035) * 0.7);
        albedo *= mix(1.0, 0.66, seam);
        ao *= mix(1.0, 0.78, seam);
      } else if (pat == 38u) {
        // Wallpaper vertical roll joints (every 0.5m)
        let seamV = aaLine(st.x * 1.0, fwStX, 0.032) * 0.36;
        albedo *= mix(1.0, 0.85, seamV);
        ao *= mix(1.0, 0.88, seamV);
      }
    }
  }
  let por = f32((flags >> 12u) & 15u) / 15.0;
  let wet = F.pbr.x * select(0.4, 1.0, n.y > 0.5);
  let hold = wet * (1.0 - 0.6 * por); // porous ground soaks the water up instead of keeping a film
  if (wet > 0.001) {
    let film = hold * mix(0.3, 1.0, wetMask); // the film stands in the hollows: smooth and level
    albedo *= mix(1.0, 0.6, wet * por);
    rough = mix(rough, 0.08, film);
    n = normalize(mix(n, baseN, film * 0.85));
  } else if (!isArch && i.wp.y < 6.48) {
    // Natural capillary dampness along low stream banks & wet riverbed pebbles
    let shoreDamp = smoothstep(6.48, 6.08, i.wp.y) * (0.55 + 0.45 * wNoiseMeso) * select(0.45, 1.0, n.y > 0.4);
    albedo *= mix(vec3f(1.0), vec3f(0.68, 0.69, 0.70), shoreDamp * 0.62);
    rough = mix(rough, 0.20, shoreDamp * 0.65);
  }
  // Lift shadow sample above 1-voxel step height on natural slopes; skip shadow taps on sun-backfacing opaque walls/ceilings
  let shPos = select(i.wp, i.wp + vec3f(0.0, 0.22 + (1.0 - rawAoInit) * 0.14, 0.0) + F.sunDir.xyz * 0.16, !isArch);
  let shNrm = select(baseN, vec3f(0.0, 1.0, 0.0), isSlopeStep);
  var sh = 0.0;
  if (dot(shNrm, F.sunDir.xyz) > 0.0 || (flags & 4u) != 0u) { sh = shadowSun(shPos, shNrm, false); }
  let msTone = mangaShadow(sh, dot(baseN, F.sunDir.xyz), i.pos.xy);
  var c = shadePBR(i.wp, n, w, sh, Surf(albedo * msTone, rough, metal, ao));
  if (ax == 1u && n.y > 0.5) {
    // Soft grounded floor/soil contact shadow directly beneath the hero's shoes (anchors character indoors & in forest shade)
    let dFoot = length((i.wp.xz - F.player.xz) * vec2f(1.0, 1.35));
    let hAbove = i.wp.y - F.player.y;
    if (dFoot < 0.48 && hAbove > -0.22 && hAbove < 0.22) {
      let footSh = 1.0 - smoothstep(0.44, 0.10, dFoot) * smoothstep(0.22, -0.02, hAbove) * 0.44;
      c *= footSh;
    }
  }
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
// constant-world (WMODE 0/1) or dynamic without discard: early-Z / HSR friendly single-target output
@fragment fn fsTerrain(i: TOut) -> @location(0) vec4f {
  let w = wAt(i.wp);
  let night = w > 0.5;
  let res = terrainColor(i, night, w);
  return vec4f(res.col, 1.0);
}
// foliage: alpha-cut individual leaves from the atlas, both sides lit
@fragment fn fsLeaf(i: TOut, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
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
  return vec4f(res.col, 1.0);
}
@fragment fn fsTerrainMasked(i: TOut) -> @location(0) vec4f {
  let w = worldAt(i.wp);
  let night = w > 0.5;
  if ((i.info.y & select(1u, 2u, night)) == 0u) { discard; }
  let res = terrainColor(i, night, w);
  return vec4f(res.col, 1.0);
}
@fragment fn fsWater(i: TOut, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
  let w = wAt(i.wp);
  let night = w > 0.5;
  let mat = select(i.info.z, i.info.w, night);
  if ((i.info.y & select(1u, 2u, night)) == 0u || mat == 0u) { discard; }
  if (mat == 15u) {
    if (w > 0.5) { discard; }
    let t = F.cam.w;
    let q = i.wp.xz;
    let camVec = F.cam.xyz - i.wp;
    let dist = length(camVec);
    let v = camVec / max(dist, 1e-4);
    // Dual-octave 3D ripple normal field + near-field capillary glitter ripples
    let uvw1 = vec3f(q.x * 0.085 + t * 0.018, t * 0.012, q.y * 0.085 - t * 0.032);
    let uvw2 = vec3f(q.x * 0.24 - t * 0.026, t * 0.020 + 0.37, q.y * 0.22 - t * 0.048);
    let n0 = textureSampleLevel(noise3, repSmp, uvw1, 0.0).r * 0.65 + textureSampleLevel(noise3, repSmp, uvw2, 0.0).r * 0.35;
    let nx = (textureSampleLevel(noise3, repSmp, uvw1 + vec3f(0.016, 0.0, 0.0), 0.0).r - n0) * 0.75
           + (textureSampleLevel(noise3, repSmp, uvw2 + vec3f(0.022, 0.0, 0.0), 0.0).r - n0) * 0.45;
    let nz = (textureSampleLevel(noise3, repSmp, uvw1 + vec3f(0.0, 0.0, 0.016), 0.0).r - n0) * 0.75
           + (textureSampleLevel(noise3, repSmp, uvw2 + vec3f(0.0, 0.0, 0.022), 0.0).r - n0) * 0.45;
    let waveH = sin(q.x * 5.2 + nx * 12.0 + t * 1.4) * cos(q.y * 4.4 - t * 2.8 + nz * 12.0);
    let ripFade = 1.0 - smoothstep(10.0, 34.0, dist);
    let capX = cos((q.x * 1.45 + q.y * 1.90) * 6.0 - t * 3.1 + n0 * 6.5) * 0.028 * ripFade;
    let capZ = sin((q.x * 1.85 - q.y * 1.35) * 6.4 + t * 2.7 + n0 * 6.5) * 0.028 * ripFade;
    var n = normalize(vec3f(-nx * 3.8 + waveH * 0.045 + capX, 1.0, -nz * 3.8 - waveH * 0.045 + capZ));
    let side = (i.info.x & 7u) != 2u;
    if (side) { n = nrmOf(i.info.x & 7u); }
    let nv = max(dot(n, v), 0.001);
    let oneMinusNoV = 1.0 - nv;
    let o2 = oneMinusNoV * oneMinusNoV;
    let fres = clamp(0.032 + 0.94 * (o2 * o2), 0.0, 1.0);
    let sh = shadowSun(i.wp, vec3f(0.0, 1.0, 0.0), false);
    let r = reflect(-v, n);
    let rawRefl = envSpec(vec3f(r.x, abs(r.y), r.z), 0.026, w);
    // Tint grazing reflections with rich overhanging forest canopy emerald-teal so water never looks like grey plastic
    let canopyReflTint = mix(vec3f(0.26, 0.44, 0.34), vec3f(0.78, 0.88, 0.94), clamp(nv * 1.45, 0.0, 1.0));
    let refl = rawRefl * canopyReflTint;
    let spec = specGGX(n, v, F.sunDir.xyz, 0.018, vec3f(0.042)) * sh;
    // Crisp GTA 6 style animated sun-glint diamond sparkle path across ripples
    let rSun = max(dot(r, F.sunDir.xyz), 0.0);
    let glint = (pow(rSun, 360.0) * 3.4 + pow(rSun, 64.0) * 0.22) * sh;
    let shoreRaw = clamp(i.ao.x, 0.0, 1.0);
    let fn1 = textureSampleLevel(noise3, repSmp, vec3f(q.x * 0.32 + t * 0.02, t * 0.03, q.y * 0.32 - t * 0.04), 0.0).r;
    // Soften and warp shore interpolation by world-space noise so 12.5cm voxel triangle diagonals never form sawtooth teeth
    let shore = smoothstep(0.12, 0.92, shoreRaw * (0.68 + fn1 * 0.48));
    let caustic = smoothstep(0.38, 0.76, waveH * 0.45 + fn1 * 0.75) * (0.30 + 0.70 * sh);
    let bedLit = vec3f(0.16, 0.19, 0.11) * (F.skyD.rgb * 1.12 + F.sunD.rgb * (0.45 + 0.55 * sh));
    let depthM = (1.0 - shore) * 1.48 + 0.06;
    let beer = exp(-depthM * vec3f(1.32, 0.44, 0.32));
    let waterScatter = vec3f(0.012, 0.072, 0.078) * (F.skyD.rgb * 1.15 + F.sunD.rgb * 0.28 * sh);
    let deep = bedLit * beer + waterScatter * (vec3f(1.0) - beer) + vec3f(0.14, 0.20, 0.10) * F.sunD.rgb * (caustic * 0.22 * (0.35 + 0.65 * shore));
    let meniscus = smoothstep(0.76, 0.95, shore) * smoothstep(0.45, 0.78, fn1) * (0.35 + 0.65 * sh);
    var col = mix(deep, refl, fres * 0.84) + F.sunD.rgb * (spec + glint) + vec3f(0.80, 0.90, 0.86) * (meniscus * 0.18);
    // Softly fade water alpha to 0.18 at the very edge of the bank so the water feathers organically into the grassy bank
    var a = mix(mix(0.20, 0.76, 1.0 - shore * 0.84), 0.92, fres * 0.86);
    if (side) {
      let fl = 0.5 + 0.5 * sin(i.wp.y * 14.0 + t * 15.0 + fn1 * 4.0);
      col = mix(col, vec3f(0.78, 0.88, 0.92) * (F.skyD.rgb * 1.15 + F.sunD.rgb * 0.3), 0.18 + 0.2 * fl);
      a = 0.65;
    }
    col += vec3f(1.0, 0.32, 0.22) * waveRim(i.wp);
    col = flatFog(col, i.wp, w);
    return vec4f(col * a, a);
  }
  // Translucent reflective glass panes (Dream M.WINDOW & Nightmare M.N_GLASS): draw front face only so 1-voxel panes never double-blend
  if (!ff) { discard; }
  let dir = i.info.x & 7u;
  let n = nrmOf(dir);
  let camVec = F.cam.xyz - i.wp;
  let dist = length(camVec);
  let v = camVec / max(dist, 1e-4);
  let gn = select(-n, n, dot(n, v) > 0.0);
  let nv = abs(dot(n, v));
  let om = 1.0 - nv;
  let om2 = om * om;
  let fres = clamp(0.10 + 0.86 * (om2 * om2), 0.10, 0.96);
  let r = reflect(-v, gn);
  let envR = envSpec(vec3f(r.x, abs(r.y) * 0.8 + 0.15, r.z), 0.04, w);
  let sh = shadowSun(i.wp, n, false);
  let gSpec = specGGX(gn, v, F.sunDir.xyz, 0.028, vec3f(0.06)) * sh;
  let uv = i.quadUV;
  let edgeD = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let paneNoise = textureSampleLevel(noise3, repSmp, i.wp * 1.4, 0.0).r;
  let grime = textureSampleLevel(noise3, repSmp, i.wp * 3.8 + vec3f(0.21), 0.0).r;
  if (night) {
    // Nightmare: dark smoky see-through glass with delicate frost rim and fine crack wisps (never opaque red brick)
    let crack = smoothstep(0.66, 0.78, grime) * 0.22;
    let edgeFrost = (1.0 - smoothstep(0.0, 0.24, edgeD)) * 0.18;
    var gCol = mix(vec3f(0.09, 0.11, 0.14) * (0.45 + 0.55 * paneNoise), envR * vec3f(0.68, 0.76, 0.90), fres * 0.80)
      + F.sunN.rgb * gSpec * 0.75 + vec3f(0.34, 0.25, 0.26) * (crack + edgeFrost);
    let gA = clamp(0.24 + fres * 0.34 + crack + edgeFrost, 0.22, 0.56);
    gCol = flatFog(gCol, i.wp, w);
    return vec4f(gCol * gA, gA);
  }
  // Dream: crystal clear straight-on interior/garden view with rich grazing Fresnel sky reflection & warm sun glint
  let dustRim = (1.0 - smoothstep(0.0, 0.16, edgeD)) * 0.12;
  let diag = 0.5 + 0.5 * sin((i.wp.x + i.wp.y + i.wp.z) * 5.0);
  var gCol = mix(vec3f(0.22, 0.38, 0.44), envR * vec3f(0.92, 0.98, 1.04), 0.56 + fres * 0.42)
    + F.sunD.rgb * gSpec * 1.65 + vec3f(0.40, 0.50, 0.54) * (dustRim + diag * 0.08 + paneNoise * 0.04);
  let gA = clamp(0.16 + fres * 0.54 + dustRim, 0.16, 0.72);
  gCol = flatFog(gCol, i.wp, w);
  return vec4f(gCol * gA, gA);
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
struct POut { pos: vec4f, wp: vec3f, n: vec3f, wn: vec3f, col: vec3f, ao: f32, mask: u32, fl: u32, lv: vec3f, quv: vec4f, vsz: f32, tu: vec3f, tv: vec3f, rgb: u32, extra: f32 };
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
  @location(7) wn: vec3f,
};
fn pk10(v: vec3f) -> u32 { let q = vec3u(clamp(v * 0.5 + 0.5, vec3f(0.0), vec3f(1.0)) * 1023.0 + 0.5); return q.x | (q.y << 10u) | (q.z << 20u); }
fn uk10(p: u32) -> vec3f { return vec3f(f32(p & 1023u), f32((p >> 10u) & 1023u), f32((p >> 20u) & 1023u)) * (2.0 / 1023.0) - 1.0; }
fn decodeOct9(pk: u32) -> vec3f {
  let ox = f32(pk & 511u) * (2.0 / 511.0) - 1.0;
  let oy = f32((pk >> 9u) & 511u) * (2.0 / 511.0) - 1.0;
  var n = vec3f(ox, oy, 1.0 - abs(ox) - abs(oy));
  if (n.z < 0.0) {
    let sx = select(-1.0, 1.0, n.x >= 0.0);
    let sy = select(-1.0, 1.0, n.y >= 0.0);
    n = vec3f((1.0 - abs(n.y)) * sx, (1.0 - abs(n.x)) * sy, n.z);
  }
  return safeNorm(n, vec3f(0.0, 1.0, 0.0));
}
fn safeNorm(v: vec3f, fb: vec3f) -> vec3f {
  let l2 = dot(v, v);
  return select(fb, v * inverseSqrt(max(l2, 1e-8)), l2 > 1e-8);
}
fn packP(o: POut) -> PV {
  var v: PV;
  v.pos = o.pos; v.wp = o.wp; v.lv = o.lv; v.quv = o.quv; v.ao = o.ao;
  v.info = vec4u(o.fl, o.mask, o.rgb, bitcast<u32>(o.vsz));
  v.frame = vec3u(pk10(safeNorm(o.n, vec3f(0.0, 1.0, 0.0))), pk10(o.tu), pk10(o.tv));
  v.extra = o.extra;
  v.wn = o.wn;
  return v;
}
fn unpackP(v: PV) -> POut {
  var o: POut;
  o.pos = v.pos; o.wp = v.wp; o.lv = v.lv; o.quv = v.quv; o.ao = v.ao;
  o.fl = v.info.x; o.mask = v.info.y; o.rgb = v.info.z; o.vsz = bitcast<f32>(v.info.w);
  let rgb = vec3f(f32((o.rgb >> 16u) & 255u), f32((o.rgb >> 8u) & 255u), f32(o.rgb & 255u)) / 255.0;
  let c2 = rgb * rgb;
  o.col = c2 * (0.8 + 0.2 * rgb);
  o.n = uk10(v.frame.x); o.tu = uk10(v.frame.y); o.tv = uk10(v.frame.z);
  o.wn = v.wn;
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
@vertex fn vsPropShadowOpaque(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> @builtin(position) vec4f {
  let o = propOut(vi, ii);
  return F.shadowMat * vec4f(o.wp, 1.0);
}
fn propOut(vi: u32, ii: u32) -> POut {
  let mi = minfo[D.x];
  let instIdx = vis[mi.visBase + ii];
  let inst = insts[instIdx];
  // v1: 2 words; v2: 3 words; lowpoly: 6 words; smooth: 10 words (+ 4x oct9 normal & Dual-Bone LBS weights)
  let v2 = (mi.flags & 256u) != 0u;
  let isLowPoly = (mi.flags & 2048u) != 0u;
  let isSmooth = (mi.flags & 4096u) != 0u;
  let isSkinned = (mi.flags & 8192u) != 0u;
  let stride = select(select(select(2u, 3u, v2), 6u, isLowPoly), 10u, isSmooth);
  // indexed quads (vertex index = quad * 4 + corner)
  let fo = mi.faceStart + (vi >> 2u) * stride;
  let w0 = mfaces[fo];
  let w1 = mfaces[fo + 1u];
  var dir = (w0 >> 24u) & 7u;
  var part = (w0 >> 27u) & 15u;
  var em = w0 >> 31u;
  var vpos = vec3f(f32(w0 & 255u), f32((w0 >> 8u) & 255u), f32((w0 >> 16u) & 255u));
  var du = 1.0; var dv = 1.0;
  var edgeMask = 15u;
  var cardMeta = 0u;
  var texPat = 0u;
  var colWord = w1;
  if (v2 && !isLowPoly) {
    let w2 = mfaces[fo + 2u];
    vpos = vec3f(f32(w0 & 1023u), f32((w0 >> 10u) & 4095u), f32((w0 >> 22u) & 1023u));
    dir = w2 & 7u; part = (w2 >> 3u) & 15u; em = (w2 >> 7u) & 1u;
    du = f32(((w2 >> 8u) & 255u) + 1u); dv = f32(((w2 >> 16u) & 255u) + 1u);
    cardMeta = (w2 >> 24u) & 255u;
    edgeMask = cardMeta & 15u;
  }
  if (isLowPoly) {
    colWord = mfaces[fo + 4u];
  }
  // Full 8-bit 4-corner Voxel Cavity AO preserved for v1, v2, and low-poly meshes
  let aow = colWord >> 24u;
  let flip = !isLowPoly && ((aow & 3u) + ((aow >> 4u) & 3u) > ((aow >> 2u) & 3u) + ((aow >> 6u) & 3u));
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
  var nrm = nrmOf(dir);
  var smoothN = nrm;
  var skWord = 0u;
  var clothByte = 0u;
  if (isLowPoly) {
    let w2 = mfaces[fo + 2u];
    let w3 = mfaces[fo + 3u];
    let w5 = mfaces[fo + 5u];
    let p0 = vec3f(f32(w0 & 1023u), f32((w0 >> 10u) & 4095u), f32((w0 >> 22u) & 1023u)) * 0.0625;
    let p1 = vec3f(f32(w1 & 1023u), f32((w1 >> 10u) & 4095u), f32((w1 >> 22u) & 1023u)) * 0.0625;
    let p2 = vec3f(f32(w2 & 1023u), f32((w2 >> 10u) & 4095u), f32((w2 >> 22u) & 1023u)) * 0.0625;
    let p3 = vec3f(f32(w3 & 1023u), f32((w3 >> 10u) & 4095u), f32((w3 >> 22u) & 1023u)) * 0.0625;
    lp = select(select(p0, p1, c == 1u), select(p2, p3, c == 3u), c >= 2u);
    part = w5 & 15u;
    em = (w5 >> 4u) & 1u;
    texPat = (w5 >> 5u) & 7u;
    du = f32(((w5 >> 8u) & 255u) + 1u) * 0.25;
    dv = f32(((w5 >> 16u) & 255u) + 1u) * 0.25;
    clothByte = (w5 >> 24u) & 255u;
    quv = vec4f(cu * du, cv * dv, du, dv);
    let eU = (p1 - p0) + (p2 - p3);
    let eV = (p3 - p0) + (p2 - p1);
    ua = normalize(select(vec3f(1.0, 0.0, 0.0), eU, length(eU) > 1e-4));
    va = normalize(select(vec3f(0.0, 1.0, 0.0), eV, length(eV) > 1e-4));
    let fnRaw = cross(p2 - p0, p3 - p1);
    nrm = normalize(select(vec3f(0.0, 1.0, 0.0), fnRaw, length(fnRaw) > 1e-5));
    if (isSmooth) {
      skWord = mfaces[fo + 6u + c];
      smoothN = decodeOct9(skWord);
    } else {
      smoothN = nrm;
    }
  }
  if (part == 15u) {
    // keep thin branches face-connected with subpixel anti-aliasing from (ku, kv); no inward center-shrinking gaps
    part = 11u; // shaded as wood
  }
  var flexS = 0.0;
  var flexT = 0.0;
  var radDir = vec3f(1.0, 0.0, 0.0);
  var sideDir = vec3f(0.0, 0.0, 1.0);
  if (part == 10u && v2 && !isLowPoly && cardMeta > 0u) {
    // Curved botanical foliage surface: wingMode 0 = single full arched quad (6x faster!), 1..6 = 3x2 segments, 7 = cross-volume sheet
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
    if (wingMode == 0u) {
      latSpan = du * 0.5 * (0.86 + 0.24 * flexT);
      yWing = -du * 0.10 * flexT;
    } else if (wingMode == 7u) {
      let bank = select(-0.34, 0.34, (azIdx & 1u) == 0u);
      latSpan = du * 0.5;
      yWing = flexS * du * bank - 0.12 * dv * flexT * flexT;
    }
    lp = vpos + radDir * radReach + sideDir * (flexS * latSpan) + vec3f(0.0, yLong + yWing, 0.0);
    quv = vec4f(uUV * du, vUV * dv, du, dv);
    ua = sideDir;
    va = normalize(radDir + vec3f(0.0, slope0 - 2.0 * archDrop * flexT, 0.0));
  }
  var p = (lp - mi.pivot.xyz) * mi.pivot.w;
  if (part == 10u && v2 && !isLowPoly && cardMeta > 0u) {
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
  let pBind = p;
  let rawB1 = (skWord >> 22u) & 15u;
  let vMob = f32((skWord >> 26u) & 63u) / 63.0;
  let headBaseY = select(-0.04, 1.328, pBind.y > 0.85);
  let eyeC = vec3f(select(-0.035, 0.035, pBind.x >= 0.0), headBaseY + 0.235, 0.078);
  let lvox = select(lp, select(pBind, pBind - eyeC, isSmooth && rawB1 == 11u), isLowPoly);
  if (isSmooth && rawB1 >= 11u && rawB1 <= 13u) {
    // Organic living facial micro-animation: saccade eye rotation (11), asymmetric blinking eyelids/lashes (12), subtle jaw/tongue breathing (13)
    let yawEye = sin(t * 0.72 + inst.phase) * 0.13 + sin(t * 2.35 + inst.phase * 1.7) * 0.045;
    let pitchEye = cos(t * 0.55 + inst.phase) * 0.065 - 0.015;
    if (rawB1 == 11u) {
      let cy = cos(yawEye); let sy = sin(yawEye);
      let cp = cos(pitchEye); let sp = sin(pitchEye);
      let de = p - eyeC;
      let deY = vec3f(de.x, de.y * cp - de.z * sp, de.y * sp + de.z * cp);
      p = eyeC + vec3f(deY.x * cy + deY.z * sy, deY.y, -deY.x * sy + deY.z * cy);
      let nY = vec3f(nrm.x, nrm.y * cp - nrm.z * sp, nrm.y * sp + nrm.z * cp);
      nrm = vec3f(nY.x * cy + nY.z * sy, nY.y, -nY.x * sy + nY.z * cy);
      let sY = vec3f(smoothN.x, smoothN.y * cp - smoothN.z * sp, smoothN.y * sp + smoothN.z * cp);
      smoothN = vec3f(sY.x * cy + sY.z * sy, sY.y, -sY.x * sy + sY.z * cy);
      let uY = vec3f(ua.x, ua.y * cp - ua.z * sp, ua.y * sp + ua.z * cp);
      ua = vec3f(uY.x * cy + uY.z * sy, uY.y, -uY.x * sy + uY.z * cy);
      let vY = vec3f(va.x, va.y * cp - va.z * sp, va.y * sp + va.z * cp);
      va = vec3f(vY.x * cy + vY.z * sy, vY.y, -vY.x * sy + vY.z * cy);
    } else if (rawB1 == 12u) {
      let bCycle = fract(t * 0.24 + inst.phase * 0.13);
      let bPulse = smoothstep(0.0, 0.028, bCycle) * (1.0 - smoothstep(0.028, 0.084, bCycle));
      let isUpper = pBind.y >= eyeC.y - 0.002;
      let lidAng = select(
        (-bPulse * 0.14 - pitchEye * 0.25) * vMob,
        (bPulse * 0.88 - pitchEye * 0.38) * vMob,
        isUpper
      );
      let cl = cos(lidAng); let sl = sin(lidAng);
      let dl = p - eyeC;
      p = eyeC + vec3f(dl.x, dl.y * cl - dl.z * sl, dl.y * sl + dl.z * cl);
      nrm = vec3f(nrm.x, nrm.y * cl - nrm.z * sl, nrm.y * sl + nrm.z * cl);
      smoothN = vec3f(smoothN.x, smoothN.y * cl - smoothN.z * sl, smoothN.y * sl + smoothN.z * cl);
    } else {
      let breath = 0.5 + 0.5 * sin(t * 1.38 + inst.phase);
      let microTalk = max(0.0, sin(t * 0.41 + inst.phase) * sin(t * 2.85));
      let jawAng = (0.012 + breath * 0.018 + microTalk * 0.024) * vMob;
      let cj = cos(jawAng); let sj = sin(jawAng);
      let jawPiv = vec3f(0.0, headBaseY + 0.185, 0.028);
      let dj = p - jawPiv;
      p = jawPiv + vec3f(dj.x, dj.y * cj - dj.z * sj, dj.y * sj + dj.z * cj);
      nrm = vec3f(nrm.x, nrm.y * cj - nrm.z * sj, nrm.y * sj + nrm.z * cj);
      smoothN = vec3f(smoothN.x, smoothN.y * cj - smoothN.z * sj, smoothN.y * sj + smoothN.z * cj);
    }
  }
  if (isSkinned && isSmooth && rawB1 == 15u) {
    // Camera strap & rangefinder walking pendulum (pivots smoothly from upper collarbone)
    let damp = clamp((1.31 - p.y) / 0.14, 0.0, 1.0);
    if (damp > 0.001) {
      let camInst = insts[instIdx + 3u];
      let cPh = camInst.phase;
      let amp = camInst.extra;
      let roll = sin(cPh) * 0.15 * amp * damp;
      let pitch = (0.042 + 0.085 * abs(cos(cPh)) - 0.055 * cos(cPh * 2.0 - 0.5)) * amp * damp;
      let cp = cos(pitch); let sp = sin(pitch);
      let cr = cos(roll); let sr = sin(roll);
      let piv = vec3f(0.0, 1.31, 0.082);
      let d0 = p - piv;
      let dx1 = d0.x * cr - d0.y * sr;
      let dy1 = d0.x * sr + d0.y * cr;
      p = piv + vec3f(dx1, dy1 * cp + d0.z * sp, -dy1 * sp + d0.z * cp);
      let ny0 = nrm.x * sr + nrm.y * cr;
      nrm = vec3f(nrm.x * cr - nrm.y * sr, ny0 * cp + nrm.z * sp, -ny0 * sp + nrm.z * cp);
      let sy0 = smoothN.x * sr + smoothN.y * cr;
      smoothN = vec3f(smoothN.x * cr - smoothN.y * sr, sy0 * cp + smoothN.z * sp, -sy0 * sp + smoothN.z * cp);
      let uy0 = ua.x * sr + ua.y * cr;
      ua = vec3f(ua.x * cr - ua.y * sr, uy0 * cp + ua.z * sp, -uy0 * sp + ua.z * cp);
      let vy0 = va.x * sr + va.y * cr;
      va = vec3f(va.x * cr - va.y * sr, vy0 * cp + va.z * sp, -vy0 * sp + va.z * cp);
    }
  }
  let clothZone = clothByte & 15u;
  if (isLowPoly && isSmooth && clothZone > 0u) {
    // Tear-free GPU cloth physics solver: inertial spring lag + centrifugal turn sway + wind flutter + dynamic crease normals
    let waCloth = windAt(vec2f(inst.m0.w, inst.m2.w));
    let rootScale = max(length(inst.m0.xyz), 1e-4);
    let wndVec = vec3f(waCloth.x, 0.0, waCloth.y);
    let lwX = dot(vec3f(inst.m0.x, inst.m1.x, inst.m2.x), wndVec) / rootScale;
    let lwZ = dot(vec3f(inst.m0.z, inst.m1.z, inst.m2.z), wndVec) / rootScale;
    let rXZLen = length(pBind.xz);
    let radXZ = select(vec2f(0.0, 1.0), pBind.xz / rXZLen, rXZLen > 1e-4);
    var cDP = vec3f(0.0);
    var cMob = 0.0;
    var foldRipple = 0.0;
    if (isSkinned) {
      let cB0 = insts[instIdx + 1u];
      let cB1 = insts[instIdx + 2u];
      let lagFwd = cB0.phase + lwZ * 0.0085;
      let lagLat = cB0.extra + lwX * 0.0085;
      let bounce = cB1.phase;
      let act = cB1.extra;
      if (clothZone == 1u) {
        // Jacket torso, pockets & bottom ribbed hem (pinned at shoulders/collar >= 1.25m, free hem down to 0.86m)
        cMob = smoothstep(1.25, 0.86, pBind.y);
        let hemFlare = (abs(lagFwd) * 0.28 + abs(lagLat) * 0.28 + act * 0.0032) * cMob;
        let wArg = t * (5.2 + act * 4.8) + pBind.x * 24.0 + pBind.y * 15.0 + inst.phase;
        let wave = sin(wArg) * (0.0020 + act * 0.0036) * cMob;
        foldRipple = cos(wArg) * (0.09 + act * 0.06) * cMob;
        cDP = vec3f(lagLat * 0.82 * cMob + radXZ.x * (hemFlare + wave), bounce * 0.44 * cMob - abs(wave) * 0.25, lagFwd * 0.82 * cMob + radXZ.y * (hemFlare + wave));
      } else if (clothZone == 2u) {
        // Draped 3D hood behind neck collar: bounces out-of-phase on footstep impact & trails in motion/wind
        cMob = smoothstep(-0.025, -0.105, pBind.z) * smoothstep(1.375, 1.16, pBind.y);
        let wArg = t * (5.8 + act * 5.0) + pBind.x * 26.0 - pBind.y * 14.0;
        let wave = sin(wArg) * (0.0022 + act * 0.0040) * cMob;
        foldRipple = cos(wArg) * (0.10 + act * 0.06) * cMob;
        cDP = vec3f(lagLat * 1.12 * cMob + wave * 0.45, bounce * 1.32 * cMob - abs(lagFwd) * 0.14 * cMob, lagFwd * 1.08 * cMob - abs(wave));
      } else if (clothZone == 3u) {
        // Hollow sleeves & cuffs: underside gravity sag, arm-swing inertia & longitudinal sleeve folds
        cMob = smoothstep(1.28, 0.78, pBind.y);
        let armSide = select(-1.0, 1.0, pBind.x >= 0.0);
        let armCtrX = armSide * (0.175 + 0.025 * smoothstep(1.28, 0.78, pBind.y));
        let armOff = vec2f(pBind.x - armCtrX, pBind.z);
        let armRLen = length(armOff);
        let armRad = select(vec2f(armSide, 0.0), armOff / armRLen, armRLen > 1e-4);
        let wArg = t * (6.0 + act * 5.2) + pBind.y * 28.0 + armSide * 1.4;
        let wave = sin(wArg) * (0.0016 + act * 0.0030) * cMob;
        foldRipple = cos(wArg) * (0.08 + act * 0.05) * cMob;
        let flare = (0.0014 + abs(wave) * 0.45 + act * 0.0018) * cMob;
        cDP = vec3f(lagLat * 0.36 * cMob + armRad.x * (flare + wave), -0.0024 * cMob + bounce * 0.32 * cMob, lagFwd * 0.36 * cMob + armRad.y * (flare + wave));
      } else if (clothZone == 4u) {
        // Hood drawstrings & metal aglets: free collar pendulums (outward bias avoids chest clipping)
        cMob = smoothstep(1.345, 1.285, pBind.y);
        let wArg = t * (4.2 + act * 4.5) + pBind.x * 45.0 + inst.phase;
        let cSwing = sin(wArg) * (0.0028 + act * 0.0055) * cMob;
        cDP = vec3f(lagLat * 1.35 * cMob + cSwing, bounce * 0.80 * cMob, max(-0.001, lagFwd * 0.45 * cMob) + abs(cSwing) * 0.65);
      } else if (clothZone == 5u) {
        // Denim trouser legs & open ankle cuffs: stride cloth ripple & calf/cuff flutter
        cMob = smoothstep(0.76, 0.11, pBind.y);
        let legSide = select(-1.0, 1.0, pBind.x >= 0.0);
        let legOff = vec2f(pBind.x - legSide * 0.0936, pBind.z);
        let legRLen = length(legOff);
        let legRad = select(vec2f(legSide, 0.0), legOff / legRLen, legRLen > 1e-4);
        let wArg = t * (6.2 + act * 5.4) + pBind.y * 22.0 + legSide * 1.5;
        let wave = sin(wArg) * (0.0014 + act * 0.0028) * cMob;
        foldRipple = cos(wArg) * (0.07 + act * 0.05) * cMob;
        let flare = (0.0012 + abs(lagFwd) * 0.14 + act * 0.0020) * cMob;
        cDP = vec3f(lagLat * 0.32 * cMob + legRad.x * (flare + wave), bounce * 0.24 * cMob, lagFwd * 0.36 * cMob + legRad.y * (flare + wave));
        let lDot = dot(cDP.xz, legRad);
        if (lDot < -0.0010) { cDP = vec3f(cDP.x - legRad.x * (lDot + 0.0010), cDP.y, cDP.z - legRad.y * (lDot + 0.0010)); }
      } else if (clothZone == 6u) {
        // Undershirt crewneck T-shirt: subtle chest breathing expansion
        cMob = smoothstep(0.90, 1.28, pBind.y);
        let breath = sin(t * 1.6 + inst.phase) * 0.0012 * cMob;
        cDP = vec3f(radXZ.x * breath, 0.0, radXZ.y * breath);
      }
      if (clothZone == 1u) {
        let rDot = dot(cDP.xz, radXZ);
        if (rDot < -0.0012) { cDP = vec3f(cDP.x - radXZ.x * (rDot + 0.0012), cDP.y, cDP.z - radXZ.y * (rDot + 0.0012)); }
      } else if (clothZone == 2u) {
        cDP.z = min(cDP.z, 0.0012);
      } else if (clothZone == 3u) {
        let armSideC = select(-1.0, 1.0, pBind.x >= 0.0);
        let armCtrXC = armSideC * (0.175 + 0.025 * smoothstep(1.28, 0.78, pBind.y));
        let armOffC = vec2f(pBind.x - armCtrXC, pBind.z);
        let armRLenC = length(armOffC);
        let armRadC = select(vec2f(armSideC, 0.0), armOffC / armRLenC, armRLenC > 1e-4);
        let aDot = dot(cDP.xz, armRadC);
        if (aDot < -0.0010) { cDP = vec3f(cDP.x - armRadC.x * (aDot + 0.0010), cDP.y, cDP.z - armRadC.y * (aDot + 0.0010)); }
      }
    } else {
      // Static/patrolling NPC outer garments (skirts, coats, sweaters, scarves, aprons) flutter smoothly in world breeze
      cMob = select(smoothstep(0.96, 0.40, pBind.y), smoothstep(1.24, 0.72, pBind.y), clothZone == 1u || clothZone == 3u);
      let wMag = length(waCloth.xy);
      let wArg = t * (2.6 + wMag * 2.2) + pBind.x * 16.0 + pBind.y * 12.0 + inst.phase;
      let wave = sin(wArg) * (0.0028 + wMag * 0.0075) * cMob;
      foldRipple = cos(wArg) * (0.08 + wMag * 0.05) * cMob;
      cDP = vec3f(lwX * 0.018 * cMob + radXZ.x * (wave + abs(lwZ) * 0.005 * cMob), -abs(wave) * 0.2, lwZ * 0.018 * cMob + radXZ.y * (wave + abs(lwX) * 0.005 * cMob));
      let nDot = dot(cDP.xz, radXZ);
      if (nDot < -0.0010) { cDP = vec3f(cDP.x - radXZ.x * (nDot + 0.0010), cDP.y, cDP.z - radXZ.y * (nDot + 0.0010)); }
    }
    p += cDP;
    if (abs(foldRipple) > 1e-4) {
      nrm = safeNorm(nrm + va * foldRipple, nrm);
      smoothN = safeNorm(smoothN + va * foldRipple, smoothN);
    }
  }
  let lp4 = vec4f(p, 1.0);
  var m0 = inst.m0;
  var m1 = inst.m1;
  var m2 = inst.m2;
  if (isSkinned && isSmooth) {
    let b0 = min((skWord >> 18u) & 15u, 10u);
    let b1 = select(min(rawB1, 10u), b0, rawB1 >= 11u);
    let w0b = select(vMob, 1.0, rawB1 >= 11u);
    let sm0 = insts[instIdx + 1u + b0];
    let sm1 = insts[instIdx + 1u + b1];
    if (dot(sm0.m0.xyz, sm0.m0.xyz) > 1e-6 && dot(sm1.m0.xyz, sm1.m0.xyz) > 1e-6) {
      m0 = mix(sm1.m0, sm0.m0, w0b);
      m1 = mix(sm1.m1, sm0.m1, w0b);
      m2 = mix(sm1.m2, sm0.m2, w0b);
    }
  }
  var wp = vec3f(dot(m0, lp4), dot(m1, lp4), dot(m2, lp4));
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
  o.n = safeNorm(vec3f(dot(m0.xyz, nrm), dot(m1.xyz, nrm), dot(m2.xyz, nrm)), vec3f(0.0, 1.0, 0.0));
  o.wn = safeNorm(vec3f(dot(m0.xyz, smoothN), dot(m1.xyz, smoothN), dot(m2.xyz, smoothN)), o.n);
  o.tu = safeNorm(vec3f(dot(m0.xyz, ua), dot(m1.xyz, ua), dot(m2.xyz, ua)), vec3f(1.0, 0.0, 0.0));
  o.tv = safeNorm(vec3f(dot(m0.xyz, va), dot(m1.xyz, va), dot(m2.xyz, va)), vec3f(0.0, 1.0, 0.0));
  o.rgb = colWord & 0xffffffu;
  o.ao = f32((aow >> (c * 2u)) & 3u) / 3.0;
  o.mask = inst.mask;
  let isEyeballBit = select(0u, 1u << 17u, isLowPoly && isSmooth && rawB1 == 11u);
  o.fl = part | (em << 4u) | (dir << 5u) | (((mi.flags >> 4u) & 3u) << 8u) | (select(0u, 1u, mi.pivot.w > 0.1) << 10u) | (select(0u, 1u, isLowPoly) << 11u) | (select(0u, 1u, isSmooth) << 22u) | isEyeballBit;
  o.lv = lvox;
  o.quv = select(quv, vec4f(smoothN, vMob), isLowPoly);
  let metaBits = select(select(edgeMask, cardMeta, part == 10u), texPat, isLowPoly);
  o.fl = o.fl | (select(0u, colWord & 3u, (mi.flags & 512u) != 0u) << 12u) | (metaBits << 14u);
  o.vsz = mi.pivot.w;
  o.extra = inst.extra;
  return o;
}
// Pixel-art foliage cluster texture evaluated on curved 2D bough surfaces (4cm pixel scale matching grass & characters).
// Shapes each curved surface into a lush scalloped cloud of overlapping pixel-art leaves/needles with dappled sky pinholes.
fn foliageCardTex(quv: vec4f, fl: u32, vsz: f32) -> vec4f {
  let shape = (fl >> 8u) & 3u; // 0: broadleaf, 1: conifer needle frond, 2: blossom, 3: weeping birch/willow
  let cardMeta = (fl >> 14u) & 255u;
  let physScale = clamp(vsz / 0.04, 1.6, 3.6);
  let totalPix = max(vec2f(6.0), floor(quv.zw * physScale));
  let uvRaw = clamp(quv.xy / max(quv.zw, vec2f(0.001)), vec2f(0.0), vec2f(0.9999));
  let pixF = floor(uvRaw * totalPix);
  let pix = vec2i(pixF);
  let uv = (pixF + 0.5) / totalPix;
  let s = (uv.x - 0.5) * 2.0;
  let t = uv.y;
  let seed = i32(cardMeta) * 19 + i32(shape) * 73;
  let hPix = f32(hashu((bitcast<u32>(pix.x) * 73856093u) ^ (bitcast<u32>(pix.y) * 19349663u) ^ u32(seed + 41)) & 255u) / 255.0;

  var strandCoord3 = 0.0;
  // 1. Cohesive, multi-lobed pixel-art cluster silhouette (zero SFU atan2/sin/cos: pure algebraic Chebyshev harmonics!)
  if (shape == 1u) {
    // Conifer drooping needle fan: solid mid-frond tapering into serrated needle fingers at the rim
    let dy = (t - 0.46) / 0.52;
    let r2 = s * s * (0.74 + 0.30 * t) + dy * dy;
    let invR = inverseSqrt(max(r2, 1e-5));
    let r = r2 * invR;
    let cx = s * invR;
    let sy = dy * invR;
    let c2 = cx * cx - sy * sy;
    let s2 = 2.0 * cx * sy;
    let c4 = c2 * c2 - s2 * s2;
    let s4 = 2.0 * c2 * s2;
    let finger = (c4 * cx - s4 * sy) * 0.11 + (c4 * c2 + s4 * s2) * 0.08;
    let hBundle = f32(hashu((bitcast<u32>(pix.x / 3) * 73856093u) ^ (bitcast<u32>(pix.y / 3) * 19349663u) ^ u32(seed + 5)) & 255u) / 255.0;
    let rLimit = 0.90 + finger + (hBundle - 0.5) * 0.16;
    if (r > rLimit) { return vec4f(0.0); }
  } else if (shape == 3u) {
    // Weeping willow / birch: slender cascading leafy strands & graceful scalloped tips
    let strandCoord = uv.x * 5.0 + (t * (1.0 - t) * 4.0 - 0.5) * 0.22;
    strandCoord3 = strandCoord;
    let stIdx = floor(strandCoord);
    let stOff = abs(fract(strandCoord) - 0.5) * 2.0;
    let hSt = f32(hashu((bitcast<u32>(i32(stIdx)) * 73856093u) ^ u32(seed + 13)) & 255u) / 255.0;
    let tipEnd = 0.08 + hSt * 0.26;
    let envW = 1.0 - abs(s) * 0.24;
    let strandHalf = mix(0.28, 0.92, smoothstep(tipEnd, 0.85, t)) * envW;
    if (t < tipEnd || stOff > strandHalf) { return vec4f(0.0); }
  } else {
    // Broadleaf & blossom billowing multi-lobed pixel bouquet
    let dy = (t - 0.48) / 0.50;
    let r2 = s * s * 0.84 + dy * dy;
    let invR = inverseSqrt(max(r2, 1e-5));
    let r = r2 * invR;
    let cx = s * invR;
    let sy = dy * invR;
    let c2 = cx * cx - sy * sy;
    let s2 = 2.0 * cx * sy;
    let c4 = c2 * c2 - s2 * s2;
    let s4 = 2.0 * c2 * s2;
    let lobes = (c4 * cx - s4 * sy) * 0.13 + (c4 * c4 - s4 * s4) * 0.08;
    let stagX = pix.x + (pix.y / 3) * 2;
    let hTuft = f32(hashu((bitcast<u32>(stagX / 3) * 73856093u) ^ (bitcast<u32>(pix.y / 3) * 19349663u) ^ u32(seed + 19)) & 255u) / 255.0;
    let rLimit = 0.90 + lobes + (hTuft - 0.5) * 0.18;
    if (r > rLimit) { return vec4f(0.0); }
  }

  // 2. Volumetric pixel-art leaf bouquet shading: deep occluded base/interior -> sunlit upper/outer lobes
  let boughGrad = 0.58 + 0.52 * smoothstep(0.0, 0.88, t) + 0.12 * (1.0 - s * s);
  let bqCell = vec2i(pix.x / 5, pix.y / 5);
  let bqLocal = vec2f(f32(pix.x % 5) - 2.0, f32(pix.y % 5) - 2.0) / 2.5;
  let bqDome = clamp(1.0 - dot(bqLocal, bqLocal) * 0.38 + bqLocal.y * 0.35, 0.0, 1.35);
  let bqMound = 0.78 + 0.34 * bqDome;
  let hBq = hash3i(vec3i(bqCell.x, bqCell.y, seed + 101));

  var leafTone = 1.0;
  var warmTip = vec3f(1.0);
  if (shape == 1u) {
    // Crisp ribbed conifer needle bundles with deep shadow grooves
    let nStripe = (pix.x + pix.y * 2) % 3;
    let hNeedle = hash3i(vec3i(pix.x / 2, pix.y / 3, seed + 71));
    if (nStripe == 0) {
      leafTone = 0.58 + hNeedle * 0.14;
    } else if (nStripe == 1) {
      leafTone = 0.92 + hNeedle * 0.14;
    } else {
      leafTone = 1.18 + hNeedle * 0.16;
      warmTip = vec3f(1.05, 1.06, 0.88);
    }
  } else if (shape == 3u) {
    // Graceful paired lanceolate leaves along drooping willow/birch strands
    let strandU = fract(strandCoord3) - 0.5;
    let leafChevron = (pix.y + i32(abs(strandU) * 6.0)) & 3;
    let hPair = hash3i(vec3i(i32(uv.x * 5.0), pix.y / 3, seed + 59));
    if (abs(strandU) < 0.08) {
      leafTone = 0.62 + hPair * 0.12;
      warmTip = vec3f(0.92, 0.95, 0.78);
    } else if (leafChevron == 0) {
      leafTone = 0.58 + hPair * 0.14;
      warmTip = vec3f(0.84, 0.96, 0.98);
    } else if (leafChevron == 2) {
      leafTone = 1.24 + hPair * 0.16;
      warmTip = vec3f(1.10, 1.12, 0.82);
    } else {
      leafTone = 0.94 + hPair * 0.16 + (hPix - 0.5) * 0.08;
    }
  } else {
    // Staggered 4x4 overlapping pixel-art leaf clusters with directional light-dark leaf volume
    let shiftX = pix.x + (pix.y >> 2) * 2;
    let lx = shiftX & 3;
    let ly = pix.y & 3;
    let leafCell = vec2i(shiftX >> 2, pix.y >> 2);
    let hLeaf = hash3i(vec3i(leafCell.x, leafCell.y, seed + 83));
    if (ly == 0 || (ly == 1 && lx == 0)) {
      // Deep occluded cool shadow crease under the overlapping leaf cluster
      leafTone = 0.52 + hLeaf * 0.12;
      warmTip = select(vec3f(0.84, 0.96, 1.05), vec3f(0.88, 0.84, 0.98), shape == 2u);
    } else if (ly == 3 && (lx == 1 || lx == 2)) {
      // Sunlit outer leaf blade tip
      leafTone = 1.24 + hLeaf * 0.16;
      warmTip = select(vec3f(1.10, 1.08, 0.82), vec3f(1.22, 1.06, 1.14), shape == 2u);
    } else if (ly == 3) {
      // Shadow notch between adjacent leaf tips
      leafTone = 0.66 + hLeaf * 0.10;
    } else {
      // Rich midtone leaf blade with subtle midrib vein
      let midrib = select(1.0, 0.84, lx == 1 && ly == 2);
      leafTone = (0.94 + hLeaf * 0.18 + (hPix - 0.5) * 0.06) * midrib;
    }
  }

  let tint = warmTip * (leafTone * bqMound * boughGrad * (0.92 + hBq * 0.16));
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

// Hardware-trilinear 32x32x32 3D value noise fetch (replaces 8-corner software hash3i ALU with 1 texture op)
fn snoise3(p: vec3f) -> f32 {
  return textureSampleLevel(noise3, repSmp, p * 0.03125, 0.0).r;
}

fn sq(x: f32) -> f32 { return x * x; }
fn facetNormal(i: POut, nrmIn: vec3f) -> vec3f {
  return nrmIn;
}
// Surface-aligned 2D texture of props, furniture, buildings, vehicles, characters and tree bark (band-limited with screen-space derivatives)
fn propPixelTex(i: POut, n: vec3f) -> vec4f {
  let part = i.fl & 15u;
  let isLowPoly = (i.fl & 2048u) != 0u;
  let cardMeta = (i.fl >> 12u) & 255u;
  if (part == 10u && !isLowPoly && cardMeta > 0u) {
    return vec4f(1.0, 1.0, 1.0, 0.5);
  }

  let pixSize = select(select(clamp(i.vsz * 0.48, 0.014, 0.028), 0.032, part == 11u), 0.0044, isLowPoly);
  let uMeters = i.quv.x * i.vsz;
  let vMeters = i.quv.y * i.vsz;
  let uvPix = vec2f(uMeters, vMeters) / pixSize;
  let camVec = F.cam.xyz - i.wp;
  let camDist = length(camVec);
  let vCamDir = camVec / max(camDist, 1e-4);
  let grazing = clamp(abs(dot(n, vCamDir)), 0.22, 1.0);
  let fwPix = camDist / max(F.opt.x * pixSize * grazing, 1e-3);
  let fineAA = 1.0 / (1.0 + fwPix * fwPix * select(2.5, 0.16, isLowPoly));
  let midAA = 1.0 / (1.0 + fwPix * fwPix * select(0.8, 0.045, isLowPoly));
  if (midAA < 0.015 && !isLowPoly) {
    return vec4f(1.0, 1.0, 1.0, 0.5);
  }
  let pix = vec2i(floor(uvPix));
  let seed = i32((i.rgb * 2654435761u) >> 18u);
  let hPix = mix(0.5, hash3i(vec3i(pix.x, pix.y, seed)), fineAA);
  let h2x2 = mix(0.5, hash3i(vec3i(pix.x >> 1, pix.y >> 1, seed + 19)), midAA);

  if (isLowPoly) {
    // 1. Living 3D Rotating Eyeball Shader with anterior-chamber corneal refraction & pixel-art crisp iris crypts
    if ((i.fl & (1u << 17u)) != 0u) {
      let ed = safeNorm(i.lv, vec3f(0.0, 0.0, 1.0));
      let scleraBase = vec3f(0.95, 0.92, 0.89);
      // Warm inner/outer caruncle flush, wet tear-meniscus & delicate capillary vessels
      let cornerT = smoothstep(0.54, 0.94, abs(ed.x));
      let veinW = sin(ed.y * 44.0 + snoise3(ed * 15.0) * 3.8) * sin(abs(ed.x) * 30.0 + ed.y * 12.0);
      let vein = smoothstep(0.68, 0.94, veinW) * cornerT;
      let upperLidSh = smoothstep(0.24, 0.72, ed.y) * 0.22;
      var eyeC = mix(scleraBase, vec3f(0.90, 0.62, 0.58), cornerT * 0.48);
      eyeC = mix(eyeC, vec3f(0.72, 0.20, 0.20), vein * 0.34) * (1.0 - upperLidSh);

      if (ed.z > 0.20) {
        // Subtle corneal parallax refraction shifts apparent iris depth inward relative to view ray
        let parX = clamp(dot(vCamDir, i.tu), -0.65, 0.65) * 0.036;
        let parY = clamp(dot(vCamDir, i.tv), -0.65, 0.65) * 0.036;
        let irisXY = ed.xy - vec2f(parX, parY);
        let ir = length(irisXY);
        let ang = atan2(irisXY.y, irisXY.x);
        // Crisp pixel-art quantized iris fiber wedges blended cleanly via fineAA
        let angQ = floor(ang * 22.0) / 22.0;
        let irQ = floor(ir * 58.0) / 58.0;
        let angMix = mix(ang, angQ, 0.45 * fineAA);
        let irMix = mix(ir, irQ, 0.32 * fineAA);
        // Captivating emerald-slate iris with warm golden-amber central collarette heterochromia & crisp radial crypts
        let irisRich = clamp(i.col * 2.55, vec3f(0.08), vec3f(0.86));
        let fiber = 0.5 + 0.5 * sin(angMix * 44.0 + snoise3(ed * 22.0) * 2.8);
        let fiberFine = 0.5 + 0.5 * cos(angMix * 88.0 - snoise3(ed * 38.0) * 2.2);
        let collarette = exp(-sq((irMix - 0.215) / 0.044));
        let radialSh = mix(irisRich * 0.52, irisRich * 1.68, fiber * 0.64 + fiberFine * 0.36);
        var irisCol = mix(radialSh, vec3f(0.76, 0.58, 0.26) + irisRich * 0.35, collarette * 0.72);
        // Subtle upper eyelid corneal shadow + deep sapphire-charcoal limbal ring + luminous lower caustic crescent
        let lowerCaustic = smoothstep(-0.02, -0.34, irisXY.y) * (1.0 - smoothstep(0.32, 0.43, ir)) * 0.38;
        let crypt = smoothstep(0.42, 0.78, ir / 0.425);
        let limbal = smoothstep(0.352, 0.422, ir) * (1.0 - smoothstep(0.422, 0.456, ir));
        irisCol = mix(irisCol, irisCol * 0.40, crypt * 0.54) * (1.0 - upperLidSh * 0.85) + irisRich * lowerCaustic;
        irisCol = mix(irisCol, vec3f(0.032, 0.052, 0.092), limbal * 0.94);
        // Crisp outer sclera-to-limbus blend (readable at low pixel-art resolution!)
        let inIris = 1.0 - smoothstep(0.46, 0.50, ir);
        eyeC = mix(eyeC, irisCol, inIris);
        // Deep optical pupil + bright upper-left catchlight sparkle so eyes read unmistakably at 378x608
        let inPupil = 1.0 - smoothstep(0.20, 0.235, ir);
        eyeC = mix(eyeC, vec3f(0.005, 0.007, 0.011), inPupil);
        let catchlight = 1.0 - smoothstep(0.075, 0.115, length(irisXY - vec2f(-0.15, 0.15)));
        eyeC = mix(eyeC, vec3f(0.98, 0.97, 0.94), catchlight * 0.92);
      }
      let corneaBump = 0.52 + 0.18 * (1.0 - smoothstep(0.16, 0.45, length(ed.xy))) * select(0.0, 1.0, ed.z > 0.20);
      return vec4f(eyeC / max(i.col, vec3f(0.02)), corneaBump);
    }

    if (midAA < 0.02) {
      return vec4f(1.0, 1.0, 1.0, 0.5);
    }
    // 2. Seamless Continuous 3D Object-Space Multi-Scale Pixel-Art PBR Projection (zero quad-boundary UV jumps!)
    let bm = i.lv;
    let nObj = safeNorm(i.quv.xyz, vec3f(0.0, 1.0, 0.0));
    let nObj2 = nObj * nObj;
    let bwRaw = nObj2 * nObj2;
    let bw = bwRaw / max(bwRaw.x + bwRaw.y + bwRaw.z, 1e-4);
    // Unified world texel size: 0.0078125 m (0.78 cm = 1/128 m), matching atlas TILE=64 per 0.50 m tile
    let uvT = (bm.zy * bw.x + bm.xz * bw.y + bm.xy * bw.z) / 0.0078;
    let tPix = vec2i(floor(uvT));
    let hTPix = mix(0.5, hash3i(vec3i(tPix.x, tPix.y, seed + 17)), fineAA);
    let texPat = (i.fl >> 14u) & 7u;
    // Lazy snoise3: evaluate nMacro only for patterns that consume it (skips 8-corner hash on hair-cap & skin/face!)
    var nMacro = 0.5;
    if (texPat != 3u && texPat != 4u) { nMacro = snoise3(bm / 0.022); }

    var lpShade = 1.0;
    var lpHeight = 0.5;
    var lpTint = vec3f(1.0);
    switch (texPat) {
      case 1u: {
        // Photorealistic Pixel-Art PBR Heavy Cotton Canvas Jacket: unified 0.78 cm pixel weave, yoke & armhole seams
        var nMid = 0.5;
        if (fineAA > 0.025) { nMid = snoise3(bm / 0.0095); }
        let uC = (bm.z * bw.x + bm.x * bw.z + bm.x * bw.y) / 0.0078;
        let vC = (bm.y * (bw.x + bw.z) + bm.z * bw.y) / 0.0078;
        let cPx = vec2i(floor(vec2f(uC, vC)));
        let checker = select(-1.0, 1.0, ((cPx.x + cPx.y) & 1) == 0);
        let hYarn = hash3i(vec3i(cPx.x, cPx.y, seed + 23)) - 0.5;
        let warpLine = cos(uC * 3.141593) * 0.45;
        let weftLine = cos(vC * 3.141593) * 0.45;
        let basket = checker * 0.50 + (warpLine + weftLine) * 0.34;
        let slub = (nMid - 0.5) * 0.18;

        // Macro garment tailoring & natural cloth drape folds (clearly visible on mobile & desktop)
        let isTorsoY = smoothstep(0.84, 0.90, bm.y) * (1.0 - smoothstep(1.34, 1.38, bm.y));
        let isSleeve = smoothstep(0.185, 0.215, abs(bm.x)) * smoothstep(0.76, 0.82, bm.y) * (1.0 - smoothstep(1.30, 1.34, bm.y));
        let chestTension = sin((abs(bm.x) * 26.0 - bm.y * 22.0) + nMacro * 2.2) * 0.075 * isTorsoY * (1.0 - isSleeve);
        let waistGather = sin(bm.x * 58.0 + nMacro * 2.6) * 0.085 * exp(-sq((bm.y - 0.93) / 0.065)) * (1.0 - isSleeve);
        let elbowCrease = sin((bm.y - 1.02) * 86.0 + nMacro * 2.4) * 0.095 * exp(-sq((bm.y - 1.02) / 0.075)) * isSleeve;
        let armholeAO = exp(-sq((abs(bm.x) - 0.185) / 0.022)) * smoothstep(1.06, 1.24, bm.y) * 0.16;
        let yokeSeam = exp(-sq((bm.y - 1.235) / 0.0045)) * smoothstep(0.03, 0.06, abs(bm.x)) * (1.0 - isSleeve);
        let yokeDash = select(0.0, 1.0, (i32(floor(bm.x / 0.0040)) & 1) == 0);
        let yokeStitch = exp(-sq((bm.y - 1.241) / 0.0022)) * yokeDash * smoothstep(0.03, 0.06, abs(bm.x)) * (1.0 - isSleeve);

        // Pixel-art vertical double-needle placket topstitching along jacket zipper edge
        let onPlacket = smoothstep(0.055, 0.085, bm.z) * smoothstep(0.86, 0.90, bm.y) * (1.0 - smoothstep(1.30, 1.34, bm.y));
        let stDist = abs(abs(bm.x) - 0.021);
        let stDash = select(0.0, 1.0, (i32(floor(bm.y / 0.0036)) & 1) == 0);
        let topStitch = (1.0 - smoothstep(0.0014, 0.0034, stDist)) * stDash * onPlacket;
        let macroFolds = (chestTension + waistGather + elbowCrease + (nMacro - 0.5) * 0.15 - armholeAO - yokeSeam * 0.15) * midAA;
        let cordWale = cos(uC * 2.094395) * 0.055 * fineAA;
        let microTex = (basket * 0.175 + cordWale + hYarn * 0.115 + slub) * fineAA;
        lpShade = 1.0 + macroFolds + microTex + (topStitch * 0.20 + yokeStitch * 0.14) * fineAA;
        lpTint = mix(vec3f(0.90, 0.93, 1.04), vec3f(1.08, 1.04, 0.94), clamp(nMacro * 0.75 + basket * 0.25 + 0.12, 0.0, 1.0));
        lpTint = mix(lpTint, vec3f(1.22, 1.16, 1.04), clamp(topStitch * 0.75 + yokeStitch * 0.55, 0.0, 1.0) * fineAA);
        lpHeight = 0.50 + (basket * 0.36 + cordWale * 2.2 + hYarn * 0.18 + slub * 0.42 + (topStitch + yokeStitch) * 0.28) * fineAA + (chestTension + waistGather + elbowCrease - yokeSeam * 0.18) * 1.45 * midAA;
      }
      case 2u: {
        // Seamless Triplanar Indigo 3x1 Denim Twill on unified 0.78 cm pixel grid
        let dU = (bm.z * bw.x + bm.x * bw.z + bm.x * bw.y) / 0.0078;
        let dV = (bm.y * (bw.x + bw.z) + bm.z * bw.y) / 0.0078;
        let dPx = vec2i(floor(vec2f(dU, dV)));
        let twillMod = (dPx.x + dPx.y) & 3;
        let isWeftDot = select(0.0, 1.0, twillMod == 0);
        let dX = cos((bm.z + bm.y * 1.32) / 0.0078 * 1.5708);
        let dZ = cos((bm.x + bm.y * 1.32) / 0.0078 * 1.5708);
        let dY = cos((bm.x + bm.z * 1.32) / 0.0078 * 1.5708);
        let twill = (dX * bw.x + dZ * bw.z + dY * bw.y) * 0.62 + (isWeftDot - 0.25) * 0.78;
        var slub = 0.0;
        if (fineAA > 0.025) { slub = (snoise3(vec3f(bm.x * 125.0, bm.y * 46.0, bm.z * 125.0)) - 0.5) * 0.17; }
        // Macro denim wear: hip whiskering, thigh/knee wash fade, behind-knee honeycombs, inner crotch/leg seam AO
        let wMask = smoothstep(0.60, 0.84, bm.y) * smoothstep(0.02, 0.07, bm.z);
        var whisker = 0.0;
        if (wMask > 0.002) { whisker = sin(bm.y * 48.0 + abs(bm.x) * 18.0 + snoise3(bm * 26.0) * 2.4) * 0.068 * wMask; }
        let thighWash = exp(-sq((abs(bm.x) - 0.095) / 0.055)) * smoothstep(0.42, 0.72, bm.y) * (1.0 - smoothstep(0.76, 0.86, bm.y)) * smoothstep(0.02, 0.07, bm.z) * 0.11;
        let kneeFade = exp(-sq((bm.y - 0.45) / 0.11)) * smoothstep(0.02, 0.07, bm.z) * 0.13;
        let backHoneycomb = sin(bm.y * 74.0 + nMacro * 2.5) * 0.065 * exp(-sq((bm.y - 0.45) / 0.08)) * smoothstep(-0.02, -0.06, bm.z);
        let crotchAO = exp(-sq(bm.x / 0.042)) * exp(-sq((bm.y - 0.73) / 0.075)) * 0.14;
        let outSeam = smoothstep(0.11, 0.15, abs(bm.x)) * (1.0 - smoothstep(0.006, 0.015, abs(bm.z))) * smoothstep(0.12, 0.16, bm.y) * (1.0 - smoothstep(0.84, 0.88, bm.y));
        let seamDash = select(0.0, 1.0, (i32(floor(bm.y / 0.0040)) & 1) == 0);
        let denimStitch = outSeam * seamDash;
        let macroDenim = (whisker + thighWash + kneeFade + backHoneycomb + (nMacro - 0.5) * 0.12 - crotchAO) * midAA;
        lpShade = 1.0 + macroDenim + (twill * 0.145 + slub) * fineAA;
        lpTint = mix(vec3f(0.88, 0.93, 1.08), vec3f(1.11, 1.08, 1.00), clamp(twill * 0.45 + 0.44 + (kneeFade + thighWash) * 2.1, 0.0, 1.0));
        lpTint = mix(lpTint, vec3f(1.48, 1.12, 0.62), denimStitch * 0.82 * fineAA);
        lpHeight = 0.50 + (twill * 0.30 + slub * 0.38 + denimStitch * 0.28) * fineAA + (whisker + backHoneycomb) * 1.4 * midAA;
      }
      case 3u: {
        // Textured Matte Chestnut Hair Under-Cap & Eyebrows: blends seamlessly with 3D hair ribbons (zero shiny dark bald scalp!)
        let headBaseY = select(-0.04, 1.328, bm.y > 0.85);
        let hRel = vec3f(bm.x, bm.y - headBaseY, bm.z);
        let crownW = smoothstep(0.45, 0.85, abs(nObj.y));
        let ang01 = atan2(hRel.x, hRel.z) * 0.15915494 + 0.5;
        let strandSide = (ang01 + sin(hRel.y * 42.0) * 0.003) * 180.0;
        let strandTop = (hRel.z + sin(hRel.x * 38.0) * 0.002) / 0.0018;
        let sCoord = mix(strandSide, strandTop, crownW);
        let fIdx = i32(floor(sCoord));
        let hFil = f32(hashu((bitcast<u32>(fIdx) * 73856093u) ^ u32(seed + 47)) & 255u) / 255.0;
        let groove = smoothstep(0.24, 0.50, abs(fract(sCoord) - 0.5));
        let rootGrad = mix(0.84, 1.08, smoothstep(0.16, 0.34, hRel.y));
        lpShade = rootGrad * (0.94 + (hFil - 0.5) * 0.24 - groove * 0.14);
        lpTint = mix(vec3f(1.08, 0.84, 0.68), vec3f(1.42, 1.12, 0.88), hFil);
        lpHeight = 0.50 + (0.4 - groove * 0.6) * 0.25;
      }
      case 4u: {
        // Photorealistic Pixel-Art PBR Living Skin: continuous anatomical shading, dermal pore texels, vascular warmth, beard stubble, moles, blemish & moist lips
        let uvSkin = (bm.zy * bw.x + bm.xz * bw.y + bm.xy * bw.z) / 0.0028;
        let skinPx = vec2i(floor(uvSkin));
        let hSkin = hash3i(vec3i(skinPx.x, skinPx.y, seed + 71)) - 0.5;
        var poreFine = 0.0;
        var poreMed = 0.0;
        if (fineAA > 0.02) {
          poreFine = snoise3(bm / 0.0020) - 0.5;
          poreMed = snoise3(bm / 0.0052) - 0.5;
        }
        let mottle = snoise3(bm / 0.020) - 0.5;
        var sShade = 1.0 + (hSkin * 0.062 + poreFine * 0.036 + poreMed * 0.044) * fineAA + mottle * 0.040 * midAA;
        var sTint = vec3f(1.008, 0.996, 0.986) + vec3f(0.024, -0.008, -0.016) * mottle;
        var sHeight = 0.50 + (hSkin * 0.12 + poreFine * 0.10 + poreMed * 0.06) * fineAA;

        let isHeadZone = bm.y < 0.52 || bm.y > 1.32;
        if (isHeadZone) {
          let headBaseY = select(-0.04, 1.328, bm.y > 0.85);
          let hRel = vec3f(bm.x, bm.y - headBaseY, bm.z);

          // 1. Continuous soft anatomical vascular warmth: broad natural malar cheek blush (zero quad edges!), nasal tip/alae, earlobes & brow glow
          let cheekV = vec3f((abs(hRel.x) - 0.048) * 0.92, (hRel.y - 0.196) * 1.15, (hRel.z - 0.084) * 1.25);
          let cheekFlush = exp(-dot(cheekV, cheekV) * 1050.0);
          let noseV = hRel - vec3f(0.0, 0.190, 0.118);
          let noseFlush = exp(-dot(noseV, noseV) * 2800.0);
          let earFlush = smoothstep(0.084, 0.104, abs(hRel.x)) * exp(-sq((hRel.y - 0.205) / 0.036));
          sTint += vec3f(0.062, -0.024, -0.030) * (cheekFlush * 0.50 + noseFlush * 0.58 + earFlush * 0.48);

          // 2. Smooth anatomical 3D facial contour shading (youthful smooth cheeks + poetic tired under-eye shadows + sculpted nose/lips)
          let lidV = vec3f((abs(hRel.x) - 0.035) * 0.85, (hRel.y - 0.252) * 3.8, (hRel.z - 0.092) * 1.6);
          let lidCrease = exp(-dot(lidV, lidV) * 3400.0);
          let uEyeV = vec3f((abs(hRel.x) - 0.035) * 0.88, (hRel.y - 0.213) * 2.4, (hRel.z - 0.094) * 1.5);
          let underEye = exp(-dot(uEyeV, uEyeV) * 3400.0);
          let alarCrease = exp(-sq((abs(hRel.x) - 0.0185) / 0.0042) - sq((hRel.y - 0.184) / 0.010)) * smoothstep(0.088, 0.104, hRel.z);
          let cupidRoll = exp(-sq(hRel.x / 0.016) - sq((hRel.y - 0.153) / 0.0032)) * smoothstep(0.092, 0.104, hRel.z);
          let nasoLine = exp(-sq((abs(hRel.x) - (0.018 + (0.202 - hRel.y) * 0.42)) / 0.0085)) * smoothstep(0.132, 0.155, hRel.y) * (1.0 - smoothstep(0.188, 0.205, hRel.y)) * smoothstep(0.072, 0.092, hRel.z);
          let philtrum = exp(-sq(hRel.x / 0.0065) - sq((hRel.y - 0.166) / 0.012)) * smoothstep(0.085, 0.100, hRel.z);
          let mentoLabial = exp(-sq(hRel.x / 0.024) - sq((hRel.y - 0.118) / 0.0085)) * smoothstep(0.075, 0.095, hRel.z);
          let underJawAO = smoothstep(0.115, 0.078, hRel.y) * smoothstep(0.010, 0.055, hRel.z) * (1.0 - smoothstep(0.070, 0.095, abs(hRel.x)));
          let neckSCM = exp(-sq((abs(hRel.x) - 0.034) / 0.015)) * smoothstep(0.088, 0.055, hRel.y) * smoothstep(0.005, 0.045, hRel.y);
          let sternalNotch = exp(-sq(hRel.x / 0.016) - sq((hRel.y - 0.020) / 0.014)) * smoothstep(0.036, 0.058, hRel.z);
          let foreheadHi = exp(-sq(hRel.x / 0.055) - sq((hRel.y - 0.292) / 0.030)) * smoothstep(0.070, 0.092, hRel.z);
          let cheekHi = exp(-sq((abs(hRel.x) - 0.046) / 0.022) - sq((hRel.y - 0.206) / 0.018)) * smoothstep(0.078, 0.096, hRel.z);
          sShade *= 1.0 - (lidCrease * 0.12 + underEye * 0.135 + alarCrease * 0.11 + nasoLine * 0.038 + philtrum * 0.07 + mentoLabial * 0.07 + underJawAO * 0.14 + neckSCM * 0.075 + sternalNotch * 0.11);
          sShade *= 1.0 + (foreheadHi * 0.045 + cheekHi * 0.050 + cupidRoll * 0.068);
          sTint = mix(sTint, sTint * vec3f(0.86, 0.80, 0.88), underEye * 0.48);
          sHeight -= (lidCrease * 0.14 + alarCrease * 0.14 + nasoLine * 0.05 + philtrum * 0.10 + mentoLabial * 0.10) * midAA;
          sHeight += cupidRoll * 0.14 * midAA;

          // 3. Lips vermilion vertical micro-creases & natural warm lip color blend + youthful smooth jawline
          let inLipZone = smoothstep(0.030, 0.018, abs(hRel.x)) * smoothstep(0.126, 0.134, hRel.y) * (1.0 - smoothstep(0.154, 0.162, hRel.y)) * smoothstep(0.086, 0.096, hRel.z);
          if (inLipZone > 0.01) {
            let lipCrease = 0.5 - 0.5 * cos(hRel.x * 1950.0 + sin(hRel.y * 520.0) * 1.5);
            sShade *= mix(1.0, 0.92 + lipCrease * 0.14, inLipZone * fineAA);
            sTint = mix(sTint, sTint * vec3f(1.06, 0.90, 0.90), inLipZone * 0.38);
            sHeight += (lipCrease - 0.5) * 0.20 * inLipZone * fineAA;
          } else if (hRel.y < 0.184 && hRel.z > 0.018 && hRel.y > 0.082) {
            // Very subtle youthful peach-fuzz skin texture on chin & jaw (no heavy mature beard shadow)
            let jawMask = smoothstep(0.184, 0.155, hRel.y) * smoothstep(0.082, 0.112, hRel.y) * smoothstep(0.018, 0.048, hRel.z);
            var folDot = 0.0;
            if (fineAA > 0.02 && jawMask > 0.002) {
              let folPx = vec3i(floor(hRel / 0.0020));
              let folHash = hash3i(folPx + vec3i(seed & 255, 13, 37));
              folDot = smoothstep(0.72, 0.92, folHash * 0.65 + snoise3(hRel / 0.0016) * 0.35);
            }
            sShade *= 1.0 - (0.008 * midAA + folDot * 0.022 * fineAA) * jawMask;
            sTint = mix(sTint, sTint * vec3f(0.97, 0.96, 0.98), jawMask * 0.10);
            sHeight += folDot * 0.02 * jawMask * fineAA;
          }

          // 4-7. Sub-millimeter dermal details (moles, blemish, freckles, brow scar): gated when sub-pixel at far distance
          if (fineAA > 0.06) {
            let dMole1 = length(hRel - vec3f(0.048, 0.206, 0.092));
            let dMole2 = length(hRel - vec3f(-0.056, 0.148, 0.060));
            let dMole3 = length(hRel - vec3f(0.070, 0.268, 0.070));
            let moleMask = max(
              1.0 - smoothstep(0.0012, 0.0021, dMole1),
              max(1.0 - smoothstep(0.0010, 0.0018, dMole2), 1.0 - smoothstep(0.0009, 0.0016, dMole3))
            );
            sTint = mix(sTint, vec3f(0.28, 0.17, 0.12), moleMask * 0.88);
            sHeight += moleMask * 0.20 * fineAA;

            let blemV = hRel - vec3f(-0.038, 0.158, 0.088);
            let dBlem2 = dot(blemV, blemV);
            if (dBlem2 < 0.00004) {
              let blemHalo = exp(-dBlem2 * 260000.0);
              let blemCore = 1.0 - smoothstep(0.0007, 0.0014, sqrt(dBlem2));
              sTint = mix(sTint, vec3f(1.06, 0.72, 0.66), blemHalo * 0.56);
              sTint = mix(sTint, vec3f(0.88, 0.52, 0.46), blemCore * 0.42);
              sHeight += blemHalo * 0.16 * fineAA;
            }

            let freckZone = exp(-sq((abs(hRel.x) - 0.024) / 0.028) - sq((hRel.y - 0.206) / 0.019)) * smoothstep(0.076, 0.096, hRel.z);
            if (freckZone > 0.004) {
              let freckSpot = smoothstep(0.75, 0.89, snoise3(hRel / 0.0022)) * freckZone;
              sTint = mix(sTint, vec3f(0.74, 0.56, 0.42), freckSpot * 0.38);
            }

            let scarU = (hRel.x - 0.053) * 0.86 + (hRel.y - 0.274) * 0.50;
            let scarV = -(hRel.x - 0.053) * 0.50 + (hRel.y - 0.274) * 0.86;
            let browScar = exp(-sq(scarU / 0.0016)) * (1.0 - smoothstep(0.008, 0.014, abs(scarV))) * smoothstep(0.076, 0.094, hRel.z);
            sTint = mix(sTint, vec3f(1.12, 0.96, 0.92), browScar * 0.58);
            sHeight -= browScar * 0.24 * midAA;
          }
        } else {
          // Subtle warm knuckle & fingertip flush + fine dorsal joint micro-creases on sculpted hands
          let handWarm = smoothstep(0.84, 0.70, bm.y) * smoothstep(0.18, 0.24, abs(bm.x));
          if (handWarm > 0.002) {
            var knuckCrease = 0.0;
            if (fineAA > 0.02) {
              knuckCrease = sin(bm.y * 540.0 + snoise3(bm * 85.0) * 1.8) * 0.045 * exp(-sq((bm.y - 0.655) / 0.024)) * handWarm * fineAA;
            }
            sShade *= 1.0 - knuckCrease;
            sTint += vec3f(0.052, -0.020, -0.024) * handWarm;
            sHeight -= knuckCrease * 1.4;
          }
        }
        lpShade = sShade;
        lpTint = sTint;
        lpHeight = sHeight;
      }
      case 5u: {
        // Pixel-Art PBR Velvety Cognac Suede Nap / Pebble Camera Vulcanite Leather / Brushed Chrome & Antique Brass
        var nFine = 0.5;
        if (fineAA > 0.06) { nFine = snoise3(bm / 0.0078); }
        let isWarmSuede = part != 13u && i.col.r > i.col.b * 1.45 && i.col.r > 0.14;
        if (part == 13u) {
          let brushPx = vec2i(floor(vec2f(uvT.x * 0.65, uvT.y * 1.5)));
          let hBrush = hash3i(vec3i(brushPx.x, brushPx.y, seed + 61)) - 0.5;
          lpShade = 1.0 + (hBrush * 0.16 + (nFine - 0.5) * 0.07) * fineAA;
          lpTint = mix(vec3f(0.95, 0.96, 0.99), vec3f(1.05, 1.04, 1.01), clamp(hBrush + 0.5, 0.0, 1.0));
          lpHeight = 0.50 + hBrush * 0.24 * fineAA;
        } else if (isWarmSuede) {
          // Velvety fine-napped suede grain on unified 0.78 cm pixel grid
          let sPx = vec2i(floor(uvT));
          let hNap = hash3i(vec3i(sPx.x, sPx.y, seed + 53)) - 0.5;
          let napSweep = (snoise3(vec3f(bm.x * 28.0, bm.y * 52.0, bm.z * 28.0)) - 0.5) * 0.22;
          lpShade = 1.0 + (hNap * 0.14 + (nFine - 0.5) * 0.09) * fineAA + napSweep * midAA;
          lpTint = mix(vec3f(0.90, 0.88, 0.86), vec3f(1.10, 1.04, 0.96), clamp(napSweep * 2.2 + hNap * 0.45 + 0.5, 0.0, 1.0));
          lpHeight = 0.50 + (hNap * 0.22 + (nFine - 0.5) * 0.16) * fineAA + napSweep * 0.45 * midAA;
        } else {
          let pPx = vec2i(floor(uvT));
          let hPeb = hash3i(vec3i(pPx.x, pPx.y, seed + 59)) - 0.5;
          var peb = hPeb * 0.65;
          if (fineAA > 0.02) { peb += (snoise3(bm / 0.0078) - 0.5) * 1.15; }
          lpShade = 1.0 + (peb * 0.18 + (nFine - 0.5) * 0.08) * fineAA + (nMacro - 0.5) * 0.08 * midAA;
          lpTint = mix(vec3f(0.93, 0.92, 0.91), vec3f(1.06, 1.04, 1.02), clamp(peb * 0.5 + 0.5, 0.0, 1.0));
          lpHeight = 0.50 + (peb * 0.30 + hPeb * 0.18) * fineAA;
        }
      }
      case 6u: {
        // Pixel-Art Herringbone Tweed / Overcoat
        let zig = abs(fract(uvT.x * 0.125) - 0.5) * 8.0;
        let herr = cos((zig + uvT.y) * 1.570796) * 0.5;
        lpShade = 1.0 + (herr * 0.18 + (hTPix - 0.5) * 0.10) * fineAA + (nMacro - 0.5) * 0.10 * midAA;
        lpHeight = 0.50 + (herr * 0.28 + (hTPix - 0.5) * 0.10) * fineAA;
      }
      case 7u: {
        // Pixel-Art 2x2 Ribbed Knit Trim (Cuffs, Collar, Waistband Hem, Scarf) on unified 0.78 cm grid
        let rU = (bm.z * bw.x + bm.x * bw.z + (bm.x + bm.z) * bw.y) / 0.0078;
        let rV = bm.y / 0.0078;
        let rPx = vec2i(floor(vec2f(rU, rV)));
        let rBar = select(-0.58, 0.58, (rPx.x & 1) == 0);
        let rLoop = (hash3i(vec3i(rPx.x, rPx.y, seed + 83)) - 0.5) * 0.42;
        let rib = rBar * 0.66 + cos(rU * 3.141593) * 0.34;
        lpShade = 1.0 + (rib * 0.25 + rLoop * 0.16) * fineAA + (nMacro - 0.5) * 0.08 * midAA;
        lpTint = mix(vec3f(0.92, 0.95, 1.04), vec3f(1.06, 1.04, 0.98), clamp(rib * 0.5 + 0.5, 0.0, 1.0));
        lpHeight = 0.50 + (rib * 0.38 + rLoop * 0.20) * fineAA;
      }
      default: {
        // Oral cavity / tongue papillae / pearlescent enamel teeth & brushed metallic camera/zipper detail
        var nFine = 0.5;
        if (fineAA > 0.06) { nFine = snoise3(bm / 0.0078); }
        let inOral = bm.y > 1.38 && bm.y < 1.52 && bm.z > 0.035 && abs(bm.x) < 0.045;
        let isTongue = inOral && i.col.r > i.col.b * 1.25;
        let isEnamel = inOral && min(i.col.r, min(i.col.g, i.col.b)) > 0.60;
        if (isTongue) {
          let papPx = vec2i(floor(vec2f(bm.x, bm.z) / 0.0014));
          let papilla = (hash3i(vec3i(papPx.x, papPx.y, seed + 97)) - 0.5) * 1.4;
          let sulcus = exp(-sq(bm.x / 0.0035));
          lpShade = (1.0 - sulcus * 0.16) * (1.0 + papilla * 0.11 * fineAA);
          lpTint = mix(vec3f(1.02, 0.94, 0.95), vec3f(0.92, 0.80, 0.82), sulcus * 0.55);
          lpHeight = 0.50 + (papilla * 0.26 - sulcus * 0.20) * fineAA;
        } else if (isEnamel) {
          let toothRidge = sin(bm.x * 950.0) * 0.035;
          lpShade = 1.0 + (toothRidge + (nFine - 0.5) * 0.03) * fineAA;
          lpTint = vec3f(1.01, 1.005, 0.985);
          lpHeight = 0.52 + toothRidge * 0.45 * fineAA;
        } else if (part == 13u) {
          let brushPx = vec2i(floor(vec2f(uvT.x * 0.45, uvT.y * 2.2)));
          let hBrush = hash3i(vec3i(brushPx.x, brushPx.y, seed + 67)) - 0.5;
          lpShade = 1.0 + (hBrush * 0.16 + (nFine - 0.5) * 0.06) * fineAA;
          lpHeight = 0.50 + hBrush * 0.22 * fineAA;
        } else {
          lpShade = 1.0 + ((hTPix - 0.5) * 0.095 + (nFine - 0.5) * 0.07) * fineAA + (nMacro - 0.5) * 0.06 * midAA;
          lpHeight = 0.50 + ((hTPix - 0.5) * 0.12 + (nFine - 0.5) * 0.09) * fineAA;
        }
      }
    }
    return vec4f(lpTint * lpShade, lpHeight);
  }

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
    // Tree Bark: smooth band-limited vertical bark ridges
    let plateX = pix.x / 2;
    let shiftY = pix.y + (plateX & 1) * 2;
    let plateY = shiftY / 5;
    let hPlate = hash3i(vec3i(plateX, plateY, seed + 31));
    let isBirch = maxC > 0.52 && sat < 0.22;
    if (isBirch) {
      let lenticel = hash3i(vec3i(0, pix.y / 2, seed + 41)) < 0.22 && ((pix.x + pix.y * 3) % 6 < 3);
      shade = mix(1.0, select(0.96 + (h2x2 - 0.5) * 0.08, 0.42, lenticel), fineAA);
      height = mix(0.50, select(0.56, 0.28, lenticel), fineAA);
    } else {
      let barkWave = 0.5 + 0.5 * cos(uvPix.x * 3.141593);
      shade = mix(1.0, (0.88 + hPlate * 0.22) * (0.90 + 0.16 * barkWave), fineAA);
      height = mix(0.50, 0.36 + 0.28 * barkWave, fineAA);
    }
  } else if (isWarmWood) {
    // Wood Planks & Furniture Grain: analytical screen-space anti-aliased board seam (aaLine) + smooth wood fiber
    let plankCoord = uvPix.x * 0.2;
    let plankIdx = i32(floor(plankCoord));
    let hBoard = hash3i(vec3i(plankIdx, 0, seed + 53));
    let hFiber = hash3i(vec3i(pix.x, pix.y / 4, seed + 61));
    let seam = select(0.0, aaLine(plankCoord, fwPix * 0.2, 0.07), i.quv.z >= 3.0);
    let boardTone = 1.0 + ((hBoard - 0.5) * 0.12 + (hFiber - 0.5) * 0.08) * fineAA;
    shade = boardTone * mix(1.0, 0.74, seam);
    height = mix(0.50 + (hFiber - 0.5) * 0.12 * fineAA, 0.26, seam);
  } else if (isFabric) {
    let weaveWave = 0.5 + 0.5 * cos((uvPix.x + uvPix.y) * 3.141593);
    shade = 1.0 + ((weaveWave - 0.5) * 0.07 + (h2x2 - 0.5) * 0.06) * fineAA;
    height = 0.50 + (weaveWave - 0.5) * 0.10 * fineAA;
  } else if (isMetal) {
    let hBrush = hash3i(vec3i(pix.x / 4, pix.y, seed + 73));
    shade = 1.0 + (hBrush - 0.5) * 0.10 * fineAA;
    height = 0.50 + (hBrush - 0.5) * 0.10 * fineAA;
  } else if (isStone) {
    // Dressed Stone & Mineral Facets: analytical screen-space mortar lines
    let rowCoord = uvPix.y * 0.25;
    let row = i32(floor(rowCoord));
    let colCoord = (uvPix.x + f32(row & 1) * 3.0) / 6.0;
    let col = i32(floor(colCoord));
    let hStone = hash3i(vec3i(col, row, seed + 89));
    let joint = select(0.0, max(aaLine(rowCoord, fwPix * 0.25, 0.08), aaLine(colCoord, fwPix / 6.0, 0.06)), i.quv.z >= 3.0);
    let stoneTone = 1.0 + (hStone - 0.5) * 0.14 * fineAA;
    shade = stoneTone * mix(1.0, 0.78, joint);
    height = mix(0.50 + (hStone - 0.5) * 0.14 * fineAA, 0.28, joint);
  } else {
    shade = 1.0 + (h2x2 - 0.5) * 0.06 * fineAA;
    height = 0.50 + (h2x2 - 0.5) * 0.06 * fineAA;
  }

  return vec4f(tint * shade, height);
}


// rgb = colour, a = 1 for a reflective surface (roughness < 0.3)
fn propColorSh(i: POut, w: f32, night: bool, n: vec3f, sh: f32, dist: f32) -> vec4f {
  let isLowPoly = (i.fl & 2048u) != 0u;
  let v = (F.cam.xyz - i.wp) / max(dist, 1e-4);
  let grazing = clamp(abs(dot(n, v)), 0.25, 1.0);
  // Keep procedural pixel textures visible at all viewing angles while smoothly attenuating sub-pixel weave aliasing
  let maxD0 = select(26.0, 38.0, isLowPoly);
  let maxD1 = select(48.0, 62.0, isLowPoly);
  let pixFoot = dist / max(F.opt.x * select(0.025, 0.011, isLowPoly) * grazing, 1e-3);
  let aaFade = 1.0 / (1.0 + pixFoot * pixFoot * select(0.28, 0.04, isLowPoly));
  let texFade = (1.0 - smoothstep(maxD0, maxD1, dist)) * mix(0.84, 1.0, grazing) * aaFade;
  var pTex = vec4f(1.0, 1.0, 1.0, 0.5);
  if (texFade > 0.005) { pTex = propPixelTex(i, n); }
  let ao = clamp(i.ao * mix(1.0, clamp(0.72 + pTex.w * 0.56, 0.64, 1.14), texFade), 0.05, 1.0);
  let hv = select(hash3i(vec3i(floor(i.lv))), 0.5, isLowPoly);
  var alb = i.col * mix(vec3f(0.85 + hv * 0.3), pTex.rgb, texFade);
  let part = i.fl & 15u;
  // PBR class of the voxel (PART in models/vox.js): 13 metal, 14 smooth dielectric (glass, enamel, lacquer), 10 leaf, 11 wood
  var rough = 0.72;
  var metal = 0.0;
  if (part == 13u) { metal = 1.0; rough = 0.30; } else if (part == 14u) { rough = 0.14; } else if (part == 10u) { rough = 0.55; } else if (part == 11u) { rough = 0.86; }
  let matCode = (i.fl >> 12u) & 3u;
  let texPat = (i.fl >> 14u) & 7u;
  let isEyeball = (i.fl & (1u << 17u)) != 0u;
  if (isLowPoly && part < 13u) {
    if (matCode == 1u) { rough = select(0.84, 0.88, texPat == 2u); }
    else if (matCode == 2u) {
      rough = select(0.58, 0.88, texPat == 2u);
      // Moist lips & natural dermal T-zone (nose/forehead) satin specular variation
      if (texPat == 4u && (i.lv.y < 0.52 || i.lv.y > 1.32)) {
        let hBase = select(-0.04, 1.328, i.lv.y > 0.85);
        let hyL = i.lv.y - hBase;
        let inLip = smoothstep(0.030, 0.018, abs(i.lv.x)) * smoothstep(0.126, 0.134, hyL) * (1.0 - smoothstep(0.154, 0.162, hyL)) * smoothstep(0.086, 0.096, i.lv.z);
        let tZone = exp(-sq(i.lv.x / 0.026)) * smoothstep(0.175, 0.215, hyL) * (1.0 - smoothstep(0.285, 0.315, hyL)) * smoothstep(0.078, 0.098, i.lv.z);
        rough = mix(rough, 0.44, tZone * 0.65);
        rough = mix(rough, 0.26, inLip);
      }
    }
    else if (texPat == 5u) { rough = 0.42; }
    else if (texPat == 3u) { rough = 0.94; }
  }
  if (isLowPoly && texPat == 0u && i.lv.y > 1.38 && i.lv.y < 1.52 && i.lv.z > 0.035 && abs(i.lv.x) < 0.045) {
    // Wet saliva gloss on tongue & pearlescent enamel polish on teeth
    if (i.col.r > i.col.b * 1.25) { rough = 0.16; }
    else if (min(i.col.r, min(i.col.g, i.col.b)) > 0.60) { rough = 0.10; }
  }
  if (isEyeball) { rough = 0.030; metal = 0.0; }
  rough = clamp(rough + (hv - 0.5) * 0.10 + (0.5 - pTex.w) * 0.28 * texFade, 0.03, 1.0);
  let wet = F.pbr.x * (0.4 + 0.6 * max(n.y, 0.0));
  alb *= 1.0 - wet * 0.22 * (1.0 - metal);
  rough = mix(rough, 0.12, wet * 0.7);
  // Crisp tactile micro-relief normal perturbation from multi-scale pixel-art heightfield (pTex.w)
  let reliefStr = select(0.14, select(0.50, 0.28, texPat == 4u), isLowPoly);
  let relief = (pTex.w - 0.5) * texFade * reliefStr;
  let reliefV = sin((i.lv.x + i.lv.z) * 195.0 - i.lv.y * 165.0) * relief * 0.42;
  let nSh = safeNorm(n + i.tu * relief + i.tv * (-relief * 0.62 + reliefV), n);
  let msTone = select(mangaShadow(sh, dot(n, F.sunDir.xyz), i.pos.xy), 1.0, isEyeball);
  var c = shadePBR(i.wp, nSh, w, sh, Surf(alb * msTone, rough, metal, ao));
  if (part == 14u || isEyeball) {
    // Automotive enamel / porcelain / wet cornea clearcoat micro-fresnel polish & crisp dual catchlight
    let om4 = 1.0 - max(dot(nSh, v), 0.0);
    let om42 = om4 * om4;
    let clearF = (om42 * om42) * select(0.45, 0.82, isEyeball) * i.ao;
    c += envSpec(reflect(-v, nSh), 0.03, w) * clearF * (F.pbr.y * (0.4 + 0.6 * sh));
    if (isEyeball) {
      let hCornea = normalize(F.sunDir.xyz + v);
      let glint = pow(max(dot(nSh, hCornea), 0.0), 220.0);
      let hSky = normalize(vec3f(0.15, 0.85, 0.35) + v);
      let skyGlint = pow(max(dot(nSh, hSky), 0.0), 92.0);
      let hWin = normalize(vec3f(-0.32, 0.52, 0.78) + v);
      let winGlint = pow(max(dot(nSh, hWin), 0.0), 140.0);
      c += sunCol(w) * glint * 1.65 * (0.28 + 0.72 * sh) + skyCol(w) * (skyGlint * 0.52 + winGlint * 0.34) + vec3f(0.96, 0.93, 0.88) * pow(max(dot(nSh, v), 0.0), 120.0) * 0.24;
    }
  }
  if (isLowPoly && !night && part < 13u) {
    let sunC = sunCol(w);
    let om = 1.0 - max(dot(nSh, v), 0.0);
    let fres = om * om * om;
    if (matCode == 1u || texPat == 1u || texPat == 2u || texPat == 6u || texPat == 7u) {
      let fuzzGate = mix(0.36, 1.0, F.pbr.y);
      let fuzzAmt = select(0.14, 0.10, texPat == 2u);
      c += alb * fres * fuzzAmt * fuzzGate * (skyCol(w) * 0.85 + sunC * (0.24 + 0.76 * sh));
    } else if (matCode == 2u && texPat == 5u) {
      let suedeGate = mix(0.42, 1.0, F.pbr.y);
      c += (alb * vec3f(1.22, 1.06, 0.88)) * fres * 0.22 * suedeGate * (skyCol(w) * 0.75 + sunC * (0.28 + 0.72 * sh));
    } else if (matCode == 2u && texPat == 4u) {
      let wrapL = max(0.0, dot(nSh, F.sunDir.xyz) * 0.5 + 0.5);
      let bDot = max(dot(-v, F.sunDir.xyz), 0.0);
      let backScatter = (bDot * bDot * bDot * sqrt(bDot)) * fres * (0.22 + 0.78 * sh) * F.pbr.y;
      let indoorSkinWarm = (1.0 - F.pbr.y) * (0.14 + fres * 0.16);
      c += alb * vec3f(0.28, 0.10, 0.048) * (sunC * (wrapL * (0.25 + 0.75 * sh) * 0.36 + backScatter * 0.55) + skyCol(w) * (fres * 0.18) + vec3f(1.0, 0.84, 0.68) * indoorSkinWarm);
    }
  }
  if (((i.fl >> 4u) & 1u) == 1u) {
    var k = 1.4;
    if (part == 5u) { k = 1.0 + sin(F.cam.w * 3.5) * 0.8; }
    c += alb * k;
  }
  if (part == 6u) {
    let oneMinus = 1.0 - abs(dot(n, v));
    let rim = oneMinus * oneMinus;
    c += vec3f(1.0, 0.85, 0.55) * (0.12 + rim * 0.7) * (0.6 + 0.4 * sin(F.cam.w * 3.5));
  }
  c += vec3f(1.0, 0.32, 0.22) * waveRim(i.wp) * 1.4;
  return vec4f(c, select(0.0, 1.0, rough < 0.3));
}
fn propColor(i: POut, w: f32, night: bool) -> vec4f {
  let nRaw = select(i.n, i.wn, (i.fl & (1u << 22u)) != 0u);
  let n = facetNormal(i, normalize(nRaw));
  let dist = distance(i.wp, F.cam.xyz);
  var sh = 1.0;
  if ((i.mask & 16u) == 0u) {
    // Skip 8-tap PCF/PCSS shadow lookup on sun-backfacing rigid props (keep for low-poly characters with wrap SSS)
    if ((i.fl & 2048u) != 0u || dot(n, F.sunDir.xyz) > 0.0) { sh = shadowSun(i.wp, n, dist < 12.0); }
    else { sh = 0.0; }
  }
  return propColorSh(i, w, night, n, sh, dist);
}

@fragment fn fsTree(pv: PV) -> @location(0) vec4f {
  var i = unpackP(pv);
  // the only discard: the leaf shapes of the foliage cards (the trees are drawn after the other models)
  let w = wAt(i.wp);
  let night = w > 0.5;
  if (WMODE == 2u && (i.mask & select(1u, 2u, night)) == 0u) { discard; }
  let part = i.fl & 15u;
  if (part == 7u) {
    let eyeCol = treeEyeShade(i, w);
    return vec4f(eyeCol, 1.0);
  }
  let isLeaf = part == 10u;
  var k = 1.0;
  var leafTip = 0.5;
  if (isLeaf) {
    let cardMeta = (i.fl >> 14u) & 255u;
    if (cardMeta == 0u) {
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
      i.lv = vec3f(f32(cardMeta) * 0.13, f32(wingMode) * 0.29, 0.5);
    }
    k = 0.68 + 0.36 * leafTip;
    i.ao = clamp(i.ao * (0.55 + 0.45 * leafTip), 0.14, 1.0);
  } else {
    k = 0.76 + 0.24 * clamp(i.lv.y * i.vsz * 0.55, 0.0, 1.0);
  }
  let nrm = normalize(i.n);
  let dist = distance(i.wp, F.cam.xyz);
  var sh0 = 0.0;
  if (isLeaf || dot(nrm, F.sunDir.xyz) > 0.0) { sh0 = shadowSun(i.wp, nrm, false); }
  let sh = select(sh0, 0.08 + 0.92 * sh0, isLeaf);
  var c = vec4f(0.0);
  if (isLeaf) {
    let skyVis = 0.28 + 0.72 * smoothstep(-0.55, 0.88, nrm.y);
    let ao = clamp(i.ao * skyVis, 0.05, 1.0);
    let hb = f32(hashu(((((i.fl >> 14u) & 255u) * 73856093u) ^ (bitcast<u32>(i32(floor(i.wp.y * 1.3))) * 19349663u))) & 255u) / 255.0;
    let wet = F.pbr.x * (0.4 + 0.6 * max(nrm.y, 0.0));
    let ndl = max(dot(nrm, F.sunDir.xyz) * 0.60 + 0.40, 0.0) * 0.96;
    let msL = mangaShadow(sh, ndl, i.pos.xy);
    let alb = i.col * vec3f(0.90 + hb * 0.16, 0.92 + hb * 0.18, 0.86 + hb * 0.10) * (1.0 - wet * 0.22) * msL;
    let sunC = sunCol(w);
    c = vec4f(alb * (sunC * (ndl * sh) + envIrr(nrm, w) * (F.pbr.y * (0.16 + 0.84 * ao))) + vec3f(1.0, 0.32, 0.22) * waveRim(i.wp) * 1.4, 0.0);
  } else if (dist > 18.0) {
    // Ultra-light distant tree bark shading: skips propPixelTex & 8-light PBR loop (5x faster distant forest trunks)
    let ndlB = max(dot(nrm, F.sunDir.xyz), 0.0);
    let msB = mangaShadow(sh, ndlB, i.pos.xy);
    let sunC = sunCol(w);
    c = vec4f(i.col * msB * (sunC * (ndlB * sh) + envIrr(nrm, w) * (F.pbr.y * (0.18 + 0.82 * i.ao))), 0.0);
  } else {
    c = propColorSh(i, w, night, nrm, sh, dist);
  }
  var tr = vec3f(0.0);
  if (isLeaf && sh > 0.05 && dist < 36.0) {
    let sunBack = max(dot(-nrm, F.sunDir.xyz), 0.0);
    let sunC = sunCol(w);
    let transmitTint = select(vec3f(1.24, 1.36, 0.64), vec3f(1.4, 0.35, 0.45), night);
    tr = i.col * transmitTint * sunC * (sunBack * 0.42 + 0.05) * (0.14 + 0.86 * sh);
  }
  var outCol = c.rgb * k + tr;
  outCol = flatFog(outCol, i.wp, w);
  return vec4f(outCol, 1.0);
}
@fragment fn fsPropMasked(pv: PV) -> @location(0) vec4f {
  let i = unpackP(pv);
  if (i.extra > 0.001 && i.extra < 0.999) {
    let dither = fract(sin(dot(floor(i.wp * 16.0), vec3f(12.9898, 78.233, 37.719))) * 43758.5453);
    if (dither > i.extra) { discard; }
  }
  let w = worldAt(i.wp);
  let night = w > 0.5;
  if ((i.mask & select(1u, 2u, night)) == 0u) { discard; }
  let c = propColor(i, w, night);
  return vec4f(c.rgb, 1.0);
}
// stable world: the cull pass already filtered instances by world mask -> no discard
@fragment fn fsProp(pv: PV) -> @location(0) vec4f {
  let i = unpackP(pv);
  let w = wAt(i.wp);
  let c = propColor(i, w, w > 0.5);
  return vec4f(c.rgb, 1.0);
}

struct GOut { @builtin(position) pos: vec4f, @location(0) col: vec3f, @location(1) uv: vec2f, @location(2) seed: f32, @location(3) varBot: vec4f };
fn grassShadow(p: vec3f) -> f32 { return shadowSun(p, vec3f(0.0, 1.0, 0.0), false); }
// What grows in a 0.5 m cell. Kinds are assigned by src/world/grassmap.js:
// 1 meadow, 2 tall grass in ear, 3 dry autumn grass, 4 mown, 5 roadside, 6 sedge, 7 moss, 8 forest shade,
// 9 stubble, 10 dead (nightmare). Each quad is a lush 5-blade pixel-art grass tuft (wid ~ 0.11..0.14m).
struct GKind { dens: f32, h0: f32, h1: f32, wid: f32, ears: f32, sway: f32, tipA: vec3f, tipB: vec3f, root: vec3f };
fn grassKind(k: u32) -> GKind {
  switch (k) {
    case 1u: { return GKind(1.0, 0.15, 0.32, 0.115, 0.05, 0.85, vec3f(0.14, 0.34, 0.07), vec3f(0.10, 0.27, 0.05), vec3f(0.045, 0.12, 0.026)); }
    case 2u: { return GKind(1.0, 0.20, 0.42, 0.130, 0.14, 1.0, vec3f(0.15, 0.35, 0.07), vec3f(0.10, 0.27, 0.05), vec3f(0.045, 0.12, 0.026)); }
    case 3u: { return GKind(0.95, 0.17, 0.35, 0.115, 0.22, 0.95, vec3f(0.32, 0.31, 0.11), vec3f(0.22, 0.25, 0.08), vec3f(0.075, 0.10, 0.034)); }
    case 4u: { return GKind(1.0, 0.11, 0.22, 0.105, 0.02, 0.55, vec3f(0.14, 0.32, 0.07), vec3f(0.10, 0.25, 0.05), vec3f(0.045, 0.12, 0.026)); }
    case 5u: { return GKind(0.95, 0.12, 0.25, 0.110, 0.04, 0.65, vec3f(0.17, 0.30, 0.07), vec3f(0.13, 0.24, 0.06), vec3f(0.055, 0.12, 0.028)); }
    case 6u: { return GKind(1.0, 0.22, 0.45, 0.135, 0.08, 0.75, vec3f(0.11, 0.30, 0.07), vec3f(0.08, 0.23, 0.055), vec3f(0.040, 0.11, 0.026)); }
    case 7u: { return GKind(1.0, 0.10, 0.20, 0.110, 0.0, 0.35, vec3f(0.13, 0.31, 0.07), vec3f(0.09, 0.24, 0.05), vec3f(0.045, 0.11, 0.025)); }
    case 8u: { return GKind(1.0, 0.14, 0.29, 0.118, 0.03, 0.75, vec3f(0.12, 0.28, 0.06), vec3f(0.08, 0.21, 0.045), vec3f(0.040, 0.10, 0.024)); }
    case 9u: { return GKind(0.85, 0.10, 0.20, 0.100, 0.0, 0.25, vec3f(0.46, 0.40, 0.17), vec3f(0.38, 0.33, 0.14), vec3f(0.16, 0.14, 0.065)); }
    case 10u: { return GKind(0.85, 0.12, 0.25, 0.105, 0.0, 0.0, vec3f(0.12, 0.11, 0.09), vec3f(0.09, 0.085, 0.075), vec3f(0.05, 0.045, 0.038)); }
    default: { return GKind(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0)); }
  }
}
@vertex fn vsGrass(@builtin(vertex_index) vi: u32) -> GOut {
  let BB = max(u32(F.grass.y), 1u);
  let ii = (vi >> 2u) / BB; // the 0.5 m cell
  var o: GOut;
  o.pos = vec4f(2.0, 2.0, 2.0, 1.0);
  o.col = vec3f(0.0);
  o.uv = vec2f(0.0);
  o.seed = 0.0;
  o.varBot = vec4f(0.0);
  // the 0.5 m cell grid sits in front of the camera (nothing is generated behind or outside view cone)
  let N = u32(F.grass.x);
  let fwd = normalize(vec2f(F.camRight.z, -F.camRight.x));
  let gf = fwd * F.grass.z * 0.42 + F.cam.xz;
  let cx = i32(ii % N) - i32(N / 2u) + i32(floor(gf.x * 2.0));
  let cz = i32(ii / N) - i32(N / 2u) + i32(floor(gf.y * 2.0));
  if (cx < 1 || cz < 1 || cx >= 383 || cz >= 639) { return o; }
  let cc = vec2f((f32(cx) + 0.5) * 0.5, (f32(cz) + 0.5) * 0.5);
  let toC = cc - F.cam.xz;
  let d2C = dot(toC, toC);
  let R = F.grass.z;
  if (d2C > R * R) { return o; }
  let dist = sqrt(d2C);
  if (dist > 4.5 && dot(toC, fwd) < -0.12 * dist) { return o; }
  // Fast horizontal view-cone cull before gcol/wind/shadow lookups (~50% fewer off-screen grass vertices)
  if (dist > 3.5 && abs(dot(toC, F.camRight.xz)) > dist * 1.15 + 1.4) { return o; }
  let cell = gcol[983040u + u32(cx) + u32(cz) * 384u];
  if ((cell & 255u) == 0u) { return o; }
  // the tuft and the voxel column it stands on (exact ground level, no grass on paving)
  let b = (vi >> 2u) % BB; // indexed: (cell * blades + blade) * 4 + corner
  let hb = hashu((u32(cx) * 73856093u) ^ (u32(cz) * 19349663u) ^ (b * 83492791u));
  let r1 = f32(hb & 1023u) / 1023.0; let r2 = f32((hb >> 10u) & 1023u) / 1023.0; let r3 = f32((hb >> 20u) & 1023u) / 1023.0;
  let r4 = f32(hashu(hb ^ 0x9e3779b9u) & 1023u) / 1023.0;
  // Stratified 4x4 sub-cell layout (plus extra jittered fill) prevents clumping & bare patches
  let subSlot = (b + ((u32(cx) + u32(cz) * 3u) & 15u)) & 15u;
  let sgx = f32(subSlot & 3u);
  let sgz = f32(subSlot >> 2u);
  let bx = cc.x - 0.24 + (sgx + 0.15 + r1 * 0.70) * 0.12;
  let bz = cc.y - 0.24 + (sgz + 0.15 + r2 * 0.70) * 0.12;
  let ci = u32(bx * 8.0) + u32(bz * 8.0) * 1536u;
  var lv = (gcol[ci >> 2u] >> ((ci & 3u) * 8u)) & 255u;
  if (lv == 0u) {
    // Fallback to nearest neighboring voxel column inside this valid grassy 0.5m cell so stream banks & paths have zero bald strips
    let ccx = clamp(i32(cc.x * 8.0), 1, 1534);
    let ccz = clamp(i32(cc.y * 8.0), 1, 2558);
    let ciCenter = u32(ccx) + u32(ccz) * 1536u;
    lv = (gcol[ciCenter >> 2u] >> ((ciCenter & 3u) * 8u)) & 255u;
    if (lv == 0u) { return o; }
  }
  let yD = f32(lv) * 0.125;
  let w = worldAt(vec3f(bx, yD + 0.3, bz));
  let night = w > 0.5;
  let kind = select(cell & 15u, (cell >> 4u) & 15u, night);
  if (kind == 0u) { return o; }
  let K = grassKind(kind);
  let y = select(yD, select(f32((cell >> 8u) & 127u) * 0.125, yD, ((cell >> 15u) & 1u) == 1u), night);
  // Smooth distance LOD + height fade to 0 at R so grass melts invisibly into the green turf with zero cutoff line
  let fade = 1.0 - smoothstep(R * 0.56, R, dist);
  let lod = mix(1.0, 0.52, smoothstep(R * 0.22, R * 0.88, dist)) * (0.48 + 0.52 * fade);
  if (f32(b) >= F.grass.y * K.dens * (f32((cell >> 20u) & 15u) / 15.0) * lod) { return o; }
  let ear = r4 < K.ears && !night; // a stalk carrying a seed head
  let hv = 0.78 + f32((cell >> 16u) & 15u) / 15.0 * 0.46;
  let h = mix(K.h0, K.h1, r3 * (0.45 + 0.55 * r3)) * hv * smoothstep(0.0, 1.0, fade) * select(1.0, 1.14, ear);
  let base = vec3f(bx, y - 0.02, bz);
  // 3D cross-angled tufts around Y: each tuft rotates around camera-facing plane so blades form rich 3D volume without gaps
  let camSide = normalize(vec3f(base.z - F.cam.z, 0.0, F.cam.x - base.x));
  let camFwd = vec3f(-camSide.z, 0.0, camSide.x);
  let angOff = (r4 - 0.5) * 1.45;
  let side = camSide * cos(angOff) + camFwd * sin(angOff);
  let c = vi & 3u;
  let u = cuOf(c); let v = cvOf(c);
  o.uv = vec2f(u, v);
  o.seed = r1 * 37.0 + r2 * 13.0 + r3 * 7.0;
  let minPixW = 1.15 * dist / max(F.opt.x, 400.0);
  let wb = max(K.wid * 1.15 / sqrt(max(lod, 0.48)), minPixW * 3.2);
  let wv = wb * mix(0.92, 1.08, v);
  var p = base + side * (u - 0.5) * wv;
  // bend: every tuft leans its own way, gusts roll over the field, only immediate sneakers push blades gently aside
  let t = F.cam.w;
  let wa = windAt(base.xz); // the same wind as the plants and the trees
  var bend = vec2f(r1 - 0.5, r2 - 0.5) * h * 0.42;
  bend += (wa.xy * 0.34 + wa.zw * 0.16) * h * K.sway;
  if (night) { bend = vec2f(r1 - 0.5, r2 - 0.5) * h * 0.85; }
  let away = base.xz - F.player.xz;
  let ad = length(away);
  if (ad < 0.28) { bend += away / max(ad, 0.01) * (0.28 - ad) * h * 1.4; }
  p += vec3f(bend.x, 0.0, bend.y) * v * v;
  p.y += h * v;
  o.pos = F.viewProj * vec4f(p, 1.0);
  // palette gradient: dark root-matched base -> lush green / sunlit translucent tip
  let pch = 0.5 + 0.5 * sin(f32(cx) * 0.11 + sin(f32(cz) * 0.07) * 2.0) * cos(f32(cz) * 0.09);
  var tip = mix(K.tipA, K.tipB, pch) * (0.90 + r3 * 0.22);
  if (ear) { tip = mix(tip, vec3f(0.24, 0.32, 0.09), 0.55) * (0.92 + r1 * 0.16); }
  else if (r1 > 0.985 && kind <= 2u) { tip = vec3f(0.68, 0.62, 0.20); }
  let alb = mix(K.root * 0.82, tip, smoothstep(0.0, 0.85, v) * (0.35 + 0.65 * fade));
  let sh = grassShadow(base + vec3f(0.0, 0.12, 0.0));
  let sun = sunCol(w);
  let sky = skyCol(w);
  let litAO = 0.32 + 0.68 * v;
  let vDotS = max(dot(normalize(p - F.cam.xyz), F.sunDir.xyz), 0.0);
  let sss = vDotS * vDotS * 0.44 * v;
  let tipTint = select(vec3f(1.18, 1.22, 0.74), vec3f(1.2, 0.4, 0.4), night);
  var colOut = alb * (sun * (0.28 + 0.72 * v) * sh + sky * litAO * 0.88) + alb * tipTint * sun * (0.22 * v + sss) * sh;
  o.col = flatFog(colOut, p, w);
  let vs2 = vDotS * vDotS;
  let vs4 = vs2 * vs2;
  let dewGlint = (vs4 * vs4 * vs4 * vs2) * sh * select(0.55, 0.0, night) * fade;
  o.varBot = vec4f(f32(kind), dewGlint, select(0.0, 1.0, night), fade);
  return o;
}
@fragment fn fsGrass(i: GOut) -> @location(0) vec4f {
  // Multi-species pixel-art grass tuft: cuts 5 diverse curved blades (integer hash: zero SFU sin per pixel)
  let u = clamp(i.uv.x, 0.0, 1.0);
  let v = clamp(i.uv.y, 0.0, 1.0);
  let bScaled = u * 5.0;
  let bIdx = floor(min(bScaled, 4.0));
  let bu = (bScaled - bIdx) * 2.0 - 1.0;
  let gH = hashu((u32(i.seed * 64.0) * 747796405u) ^ (u32(bIdx) * 2891336453u));
  let bhHash = f32(gH & 1023u) / 1023.0;
  let bLeanHash = f32((gH >> 10u) & 1023u) / 1023.0;
  let spHash = f32((gH >> 20u) & 1023u) / 1023.0;
  let gKind = i.varBot.x;
  let isNight = i.varBot.z > 0.5;
  let isCloverMoss = !isNight && (gKind == 7.0 || spHash < 0.14);
  let isDryStraw = !isNight && !isCloverMoss && (spHash > select(0.76, 0.62, gKind == 3.0 || gKind == 5.0) && spHash < 0.90);
  let isWildflower = !isNight && spHash >= 0.91 && (gKind == 1.0 || gKind == 2.0 || gKind == 5.0);
  let bladeH = select(0.60 + 0.40 * bhHash, 0.44 + 0.24 * bhHash, isCloverMoss);
  let bv = v / bladeH;
  if (bv > 1.0) { discard; }
  let bvPix = floor(bv * 9.0) / 9.0;
  let archCurve = (bLeanHash - 0.5) * 0.64 * bvPix * bvPix;
  let splay = (bLeanHash - 0.5) * 0.22 * bvPix + archCurve;
  var halfW = mix(1.06, 0.14, bv * bv);
  if (isCloverMoss) {
    halfW = mix(0.86, 0.58, bv) * (1.0 - smoothstep(0.82, 1.0, bv));
  } else if (isWildflower && bv > 0.72) {
    halfW = mix(0.55, 0.88, sin(clamp((bv - 0.72) / 0.28, 0.0, 1.0) * 3.14159265));
  }
  let dBlade = abs(bu - splay);
  if (dBlade > halfW) { discard; }
  // Pixel-art stepped vertical banding + cylindrical cross-blade midrib + deep root grounding AO + dew cuticle glint
  let vStep = floor(i.uv.y * 7.0) / 7.0;
  let rootAO = mix(0.28, 1.15, smoothstep(0.0, 0.60, bvPix + vStep * 0.01));
  let crossShade = 0.86 + 0.22 * sin(clamp(i.uv.x, 0.0, 1.0) * 3.14159265);
  let midrib = select(1.0, 0.90, dBlade < halfW * 0.22 && !isWildflower);
  let bladeRidge = (0.86 + 0.24 * (1.0 - dBlade / max(halfW, 0.05))) * midrib;
  let bladeVar = 0.88 + 0.24 * bhHash;
  var speciesTint = select(vec3f(1.04, 1.04, 0.88), vec3f(0.84, 1.04, 0.92), bhHash > 0.5);
  if (isCloverMoss) {
    speciesTint = vec3f(0.76, 1.02, 0.66);
  } else if (isDryStraw) {
    speciesTint = vec3f(1.36, 1.22, 0.72);
  } else if (isWildflower && bv > 0.74) {
    let fCol = select(vec3f(1.52, 1.48, 1.32), select(vec3f(1.46, 1.30, 0.54), vec3f(0.92, 1.04, 1.42), bLeanHash > 0.66), bLeanHash > 0.33);
    speciesTint = mix(fCol, vec3f(1.52, 1.34, 0.42), select(0.0, 0.65, dBlade < halfW * 0.28 && bv > 0.80 && bv < 0.92));
  }
  let dewSpec = i.varBot.y * smoothstep(0.45, 0.95, bv) * (1.0 - dBlade / max(halfW, 0.05));
  return vec4f(i.col * speciesTint * (rootAO * crossShade * bladeRidge * bladeVar + dewSpec), 1.0);
}

struct PtOut { @builtin(position) pos: vec4f, @location(0) uv: vec2f, @location(1) col: vec4f, @location(2) @interpolate(flat) shape: f32 };
@vertex fn vsPart(@builtin(vertex_index) vi: u32) -> PtOut {
  let ii = vi >> 2u; // indexed: particle * 4 + corner
  let pt = parts[ii];
  var o: PtOut;
  o.pos = vec4f(2.0, 2.0, 2.0, 1.0);
  o.uv = vec2f(0.0);
  o.col = vec4f(0.0);
  o.shape = 0.0;
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
      // Crisp square pixel-art dust motes illuminated by BOTH outdoor sunbeams AND indoor golden tungsten lamps
      o.shape = 1.0;
      let sh = shadowSun(wp, vec3f(0.0, 1.0, 0.0), false);
      let indoorAmt = 1.0 - smoothstep(0.30, 0.70, F.pbr.y);
      let sunGate = smoothstep(0.18, 0.65, sh) * smoothstep(0.55, 0.95, F.pbr.y);
      let sunC = sunCol(w);
      var ptLit = vec3f(0.0);
      let nL = min(F.counts.z, 12u);
      for (var li = 0u; li < nL; li++) {
        let lp = F.lights[li].pos.xyz;
        let rad = max(F.lights[li].pos.w, 0.1);
        let dL = distance(wp, lp);
        if (dL < rad) {
          let att = (1.0 - dL / rad);
          ptLit += F.lights[li].col.rgb * (att * att * 0.68);
        }
      }
      let shimmer = 0.62 + 0.38 * sin(t * (1.4 + fract(seed * 9.3) * 1.6) + seed * 29.0);
      let indoorFill = vec3f(0.95, 0.68, 0.28) * (0.20 * indoorAmt * select(1.0, 0.25, night));
      let base = select(vec3f(1.0, 0.94, 0.78), vec3f(1.0, 0.80, 0.40), ty == 3u || indoorAmt > 0.35);
      size = select(0.0055, 0.0092, ty == 3u || indoorAmt > 0.35) * (0.72 + fract(seed * 17.3) * 0.56);
      col = vec4f(base * (sunC * 0.38 * sunGate + (ptLit + indoorFill) * (0.55 + 0.45 * indoorAmt)) * shimmer, 0.0);
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
  // nothing floats right at the lens (it would be a huge soft blob): fade out near the camera, closer indoors for room dust
  let isIndoorDust = (ty == 2u || ty == 3u) && F.pbr.y < 0.6;
  let nearMin = select(select(0.5, 2.4, ty == 2u || ty == 3u), 0.75, isIndoorDust);
  let nearMax = select(select(1.4, 4.2, ty == 2u || ty == 3u), 1.65, isIndoorDust);
  col = col * smoothstep(nearMin, nearMax, distance(wp, F.cam.xyz));
  wp = wp + (r * q.x + u * q.y) * size;
  o.pos = F.viewProj * vec4f(wp, 1.0);
  o.uv = q;
  o.col = col;
  return o;
}
@fragment fn fsPart(i: PtOut) -> @location(0) vec4f {
  if (i.shape > 0.5) {
    // Crisp square pixel-art dust mote (matching reference corridor & lamp beam motes)
    if (max(abs(i.uv.x), abs(i.uv.y)) > 0.86) { discard; }
    return vec4f(i.col.rgb * 0.92, 0.92);
  }
  let r2 = dot(i.uv, i.uv);
  if (r2 > 1.0) { discard; }
  let t = 1.0 - r2;
  var a = t * t * t;
  if (i.col.a >= 0.999) { a = 1.0 - smoothstep(0.55, 1.0, r2); }
  return vec4f(i.col.rgb * a, a);
}
