
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

@group(0) @binding(0) var<uniform> F: Frame;
@group(0) @binding(1) var sceneTex: texture_2d<f32>;
@group(0) @binding(3) var depthTex: texture_depth_2d;
@group(0) @binding(4) var linSmp: sampler;
@group(0) @binding(10) var colorLUT: texture_3d<f32>;

fn hgPhase(c: f32, g: f32) -> f32 {
  let g2 = g * g;
  let denom = max(1.0 + g2 - 2.0 * g * c, 0.0001);
  return (1.0 - g2) / (12.566 * denom * sqrt(denom));
}

fn pixelWorldWp(depth: f32, p: vec3f) -> f32 {
  if (F.misc.x > 0.5) { return 1.0; }
  if (F.waveP.z < 0.5) { return F.sunDir.w; }
  if (depth >= 1.0) {
    let tn = smoothstep(3.0, 70.0, F.wave.w);
    var f = tn;
    if (F.wave2.w > 0.0) { f = 1.0 - smoothstep(3.0, 70.0, F.wave2.w) * (1.0 - tn); }
    return mix(F.waveP.x, F.waveP.y, f);
  }
  let inside = distance(p, F.wave.xyz) < F.wave.w || (F.wave2.w > 0.0 && distance(p, F.wave2.xyz) > F.wave2.w);
  return select(F.waveP.x, F.waveP.y, inside);
}

fn pixelWorld(uv: vec2f, depth: f32) -> f32 {
  if (F.misc.x > 0.5) { return 1.0; }
  if (F.waveP.z < 0.5) { return F.sunDir.w; }
  if (depth >= 1.0) { return pixelWorldWp(depth, vec3f(0.0)); }
  let wp4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
  return pixelWorldWp(depth, wp4.xyz / wp4.w);
}

// Fast analytical sky + crisp sun disc & Mie corona + 3D sun-lit cumulus & cirrus clouds + multi-layer mountain vistas
fn skyColor(rd: vec3f, w: f32) -> vec3f {
  let d = normalize(vec3f(rd.x, max(rd.y, 0.0), rd.z));
  let s = max(dot(rd, F.sunDir.xyz), 0.0);
  let s2 = s * s; let s4 = s2 * s2; let s8 = s4 * s4;
  let s14 = s8 * s4 * s2;
  let s32 = s8 * s8 * s8 * s8;
  let s96 = s32 * s32 * s32;
  let sunG = mix(F.skyPD[3].rgb, F.skyPN[3].rgb, w);
  let disc = smoothstep(0.99935, 0.99972, s) * 16.0;
  let corona = s96 * 0.75 + s14 * 0.18;
  var c = skyDome(d, w) + sunG * (disc + corona);

  // Drifting 3D-lit stylized cumulus + high wispy cirrus clouds with bright silver-gold linings
  let t = F.cam.w;
  let isDark = clamp(F.fx2.y + w * 0.85, 0.0, 1.0);
  if (rd.y > 0.015 && isDark < 0.92) {
    let clProj = rd.xz / (rd.y + 0.15);
    let sunXZ = F.sunDir.xz / max(length(F.sunDir.xz), 0.01);
    let drift = F.wind.xy * (t * 0.18) + vec2f(t * 0.018, t * 0.008);
    let cp1 = vec3f((clProj + drift) * 1.10, t * 0.004);
    let cp2 = vec3f((clProj * 2.25 - drift * 0.55) + vec2f(17.3, 9.1), 1.7);
    let fbm = vnoise3(cp1) * 0.60 + vnoise3(cp2) * 0.40;
    // Directional self-shadow tap toward the sun gives billowing sunlit upper rims & cool blue bases
    let fbmSun = vnoise3(cp1 + vec3f(sunXZ * 0.22, 0.0)) * 0.62 + vnoise3(cp2 + vec3f(sunXZ * 0.35, 0.0)) * 0.38;
    let lightSlope = clamp((fbm - fbmSun) * 2.4 + 0.56, 0.0, 1.0);
    let horizonFade = smoothstep(0.015, 0.18, rd.y);
    let clDens = smoothstep(0.49, 0.78, fbm) * horizonFade;
    let sunFwd = s8 * 0.85 + s2 * 0.15;
    let silverRim = (1.0 - smoothstep(0.55, 0.80, fbm)) * (s4 * s) * 0.85;
    let clLit = mix(vec3f(0.95, 0.97, 1.02), sunG * 1.45 + vec3f(0.55, 0.50, 0.44), sunFwd) + sunG * silverRim;
    let clShad = mix(F.skyPD[0].rgb * 0.78 + vec3f(0.10, 0.14, 0.24), F.fogD.rgb * 0.72, 0.45);
    let clCol = mix(clShad, clLit, lightSlope * 0.75 + sunFwd * 0.25) * (1.0 - isDark * 0.85);
    c = mix(c, clCol, clDens * 0.72 * (1.0 - isDark * 0.7));

    // High-altitude wispy cirrus streaks catching warm morning sunlight
    let ciProj = rd.xz / (rd.y + 0.35);
    let cirrus = smoothstep(0.58, 0.82, vnoise3(vec3f(ciProj.x * 0.75 + drift.x * 0.4, ciProj.y * 2.4 + drift.y * 0.3, 4.2)));
    c += mix(vec3f(0.65, 0.76, 0.92), sunG * 0.95 + vec3f(0.42), s2 * 0.65) * (cirrus * 0.20 * smoothstep(0.06, 0.32, rd.y) * (1.0 - isDark));
  }

  // Stars at dusk / night
  let st = mix(F.skyX[0].w, F.skyX[1].w, w);
  if (st > 0.01 && rd.y > 0.02) {
    let h = hash3i(vec3i(floor(d * 230.0)));
    c += vec3f(0.85, 0.92, 1.0) * (step(0.9968, h) * st * (0.7 + 0.3 * sin(t * (1.3 + h * 2.0) + h * 400.0)) * smoothstep(0.02, 0.22, rd.y) * 0.5);
  }

  // TES 6 style multi-layered distant mountain ridges & forested highland silhouettes
  if (rd.y > -0.025 && rd.y < 0.14) {
    let az = atan2(rd.z, rd.x);
    let fogC = fogCol(w);
    let farH = 0.042 + 0.032 * sin(az * 3.0 + 1.1) + 0.018 * cos(az * 7.0 - 0.5) + 0.008 * sin(az * 19.0 + 0.3);
    let farMask = (1.0 - smoothstep(farH - 0.004, farH + 0.004, rd.y)) * smoothstep(-0.025, 0.002, rd.y);
    let farCol = mix(fogC * vec3f(0.70, 0.80, 0.98), sunG * 0.42 + fogC * 0.65, (s2 * s) * 0.65);
    c = mix(c, farCol, farMask * 0.70 * (1.0 - w * 0.45));

    let ridgeH = 0.020 + 0.016 * sin(az * 5.0 + 0.7) + 0.009 * cos(az * 13.0 - 1.2) + 0.005 * sin(az * 43.0) + 0.0025 * cos(az * 97.0);
    let ridgeMask = (1.0 - smoothstep(ridgeH - 0.0025, ridgeH + 0.0025, rd.y)) * smoothstep(-0.02, 0.002, rd.y);
    let valleyFog = smoothstep(ridgeH, -0.005, rd.y) * 0.32;
    let ridgeBase = mix(fogC * vec3f(0.36, 0.46, 0.62), sunG * 0.32 + fogC * 0.52, s4 * 0.68);
    let ridgeCol = mix(ridgeBase, fogC * 0.92 + sunG * 0.18 * s2, valleyFog);
    c = mix(c, ridgeCol, ridgeMask * 0.88);
  }
  return c;
}

// Exact per-pixel analytical exponential height + Mie atmospheric fog (zero quarter-res grids, zero stepping noise)
fn applyAnalyticFogWp(d: f32, wp: vec3f, baseIn: vec3f, w: f32) -> vec3f {
  let sky = d >= 1.0;
  let ro = F.cam.xyz;
  let rdVec = wp - ro;
  var dist = length(rdVec);
  let rd = rdVec / max(dist, 0.0001);
  var col = baseIn;
  if (sky) {
    col = select(skyColor(rd, w), vec3f(0.0), F.misc.x > 0.5);
    if (F.counts.z == 0u) {
      return mix(col, fogCol(w), 0.25);
    }
    dist = F.fogP.w * 0.38;
  }
  if (F.counts.z == 0u) { return col; }
  let rawDist = min(dist, F.fogP.w);
  let fogDist = select(max(0.0, rawDist - select(24.0, 5.0, w > 0.5)), rawDist, sky);
  if (!sky && fogDist <= 0.0001) { return col; }
  let baseDens = mix(F.fogD.w, F.fogN.w, w);
  let k = max(F.fogP.y, 0.0001);
  let h0 = max(ro.y - F.fogP.x, 0.0);
  let h1 = max(ro.y + rd.y * rawDist - F.fogP.x, 0.0);
  let kd = k * (h1 - h0);
  let factor = select((1.0 - exp(-kd)) / kd, 1.0 - 0.5 * kd + kd * kd * 0.166667, abs(kd) < 1e-3);
  let tau = baseDens * fogDist * exp(-k * h0) * factor;
  var T = exp(-tau);
  if (sky) {
    let skyClear = smoothstep(0.015, 0.25, max(rd.y, 0.0));
    T = max(T, mix(0.68, 0.97, skyClear));
  } else {
    let minObjT = 0.38;
    T = max(T, minObjT);
  }
  let cosT = dot(rd, F.sunDir.xyz);
  let ph = min(mix(hgPhase(cosT, 0.68), 0.0796, 0.22) * 3.6, 1.8);
  let sunShare = select(0.08, 0.22, F.counts.w != 0u);
  let fogC = fogCol(w);
  let sunC = sunCol(w);
  let Li = fogC * mix(0.72, 0.88, smoothstep(-0.2, 0.8, cosT)) + sunC * (ph * sunShare);
  var outCol = col * T + Li * (1.0 - T);
  if (!sky && w < 0.85) {
    // Soft sunlit meadow mist hugging low river valleys beyond 26m for aerial perspective
    let endY = ro.y + rd.y * rawDist;
    let valley = smoothstep(26.0, 68.0, rawDist) * smoothstep(8.2, 5.2, endY) * 0.18 * (1.0 - w);
    let mistCol = fogC * 0.84 + sunC * (ph * sunShare * 1.25);
    outCol = mix(outCol, mistCol, valley);
  }
  return outCol;
}

fn applyAnalyticFog(uv: vec2f, d: f32, baseIn: vec3f, w: f32) -> vec3f {
  let wp4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, select(d, 1.0, d >= 1.0), 1.0);
  return applyAnalyticFogWp(d, wp4.xyz / wp4.w, baseIn, w);
}

// Fast 4-tap dithered screen-space crepuscular sun shafts (strictly gated when looking toward sun outdoors)
fn sunShafts(ip: vec2i, dd: vec2i, uv: vec2f, w: f32) -> vec3f {
  let outShaft = smoothstep(0.56, 0.95, F.pbr.y);
  if (F.misc.x > 0.5 || F.counts.z == 0u || F.sunDir.y < 0.02 || w > 0.85 || outShaft <= 0.005) { return vec3f(0.0); }
  let camFwd = normalize(vec3f(-F.camRight.z, 0.0, F.camRight.x));
  let lookAlign = smoothstep(0.14, 0.72, dot(camFwd, F.sunDir.xyz));
  if (lookAlign <= 0.005) { return vec3f(0.0); }
  let sunClip = F.viewProj * vec4f(F.cam.xyz + F.sunDir.xyz * 80.0, 1.0);
  if (sunClip.w <= 0.05) { return vec3f(0.0); }
  let sunNdc = sunClip.xy / sunClip.w;
  let sunUV = vec2f(sunNdc.x * 0.5 + 0.5, 0.5 - sunNdc.y * 0.5);
  let ray = sunUV - uv;
  let rayLen = length(ray);
  let sunDistAtt = smoothstep(1.25, 0.05, rayLen);
  if (sunDistAtt <= 0.005) { return vec3f(0.0); }
  let jitter = f32(hashu(u32(ip.x) * 1973u + u32(ip.y) * 9277u + 17u) & 255u) / 255.0;
  let stepUV = ray * min(rayLen, 0.50) / (max(rayLen, 1e-4) * 4.0);
  var curUV = uv + stepUV * jitter;
  var illum = 1.0;
  var shaft = 0.0;
  for (var s = 0; s < 4; s++) {
    if (curUV.x >= 0.0 && curUV.x <= 1.0 && curUV.y >= 0.0 && curUV.y <= 1.0) {
      let sp = clamp(vec2i(curUV * vec2f(dd)), vec2i(0), dd - vec2i(1));
      if (textureLoad(depthTex, sp, 0) >= 0.999) { shaft += illum; }
    }
    illum *= 0.78;
    curUV += stepUV;
  }
  return sunCol(w) * (shaft * 0.36 * sunDistAtt * lookAlign * 0.14 * (1.0 - w) * outShaft);
}

fn wpFromDepth(uv: vec2f, dz: f32) -> vec3f {
  let wp4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, dz, 1.0);
  return wp4.xyz / wp4.w;
}

// Fast 2-step close foreground contact shadow raymarch along F.sunDir (strictly gated <= 9m outdoors)
fn contactShadowSun(dd: vec2i, dz: f32, dc: f32, wp: vec3f) -> f32 {
  let outCS = smoothstep(0.60, 0.92, F.pbr.y);
  if (dz >= 1.0 || dc > 9.0 || F.counts.w == 0u || F.sunDir.y < 0.06 || outCS <= 0.01) { return 1.0; }
  let ddMax = dd - vec2i(1);
  let ddF = vec2f(dd);
  let stepV = F.sunDir.xyz * clamp(0.075 + dc * 0.006, 0.075, 0.13);
  let bias = 0.022 + dc * 0.004;
  let maxThick = 0.24;
  let clip0 = F.viewProj * vec4f(wp, 1.0);
  let clipStep = F.viewProj * vec4f(stepV, 0.0);
  var occ = 0.0;
  for (var k = 1; k <= 2; k++) {
    let clip = clip0 + clipStep * f32(k);
    if (clip.w <= 0.001) { continue; }
    let ndc = clip.xyz / clip.w;
    let suv = vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (suv.x <= 0.002 || suv.x >= 0.998 || suv.y <= 0.002 || suv.y >= 0.998) { continue; }
    let sd = textureLoad(depthTex, clamp(vec2i(suv * ddF), vec2i(0), ddMax), 0);
    if (sd >= 1.0) { continue; }
    let delta = viewZ(ndc.z) - viewZ(sd);
    if (delta > bias && delta < maxThick) {
      occ = max(occ, smoothstep(bias, bias * 2.2, delta) * (1.0 - smoothstep(0.14, maxThick, delta)));
    }
  }
  return 1.0 - occ * 0.34 * (1.0 - smoothstep(6.5, 9.0, dc)) * outCS;
}

// Ultra-fast 1-tap checkerboard HDR optical bloom (0 extra depthTex loads -> 3x less post-process VRAM bandwidth)
fn opticalBloom(ip: vec2i, uv: vec2f, dd: vec2i, dzCenter: f32, zc: f32) -> vec3f {
  let texel = F.outRes.zw;
  let expScale = max(F.grade.x * F.pbr.w, 0.5);
  let bloomKnee = mix(2.90, 2.40, smoothstep(0.55, 0.95, F.pbr.y));
  let offs = array<vec2f, 4>(
    vec2f(1.75, 0.75), vec2f(-1.75, -0.75), vec2f(-0.75, 1.75), vec2f(0.75, -1.75)
  );
  let tapIdx = ((ip.x & 1) | ((ip.y & 1) << 1)) & 3;
  let tapUV = clamp(uv + offs[tapIdx] * texel, vec2f(0.001), vec2f(0.999));
  let s = textureSampleLevel(sceneTex, linSmp, tapUV, 0.0).rgb;
  let l = dot(s, vec3f(0.2126, 0.7152, 0.0722)) * expScale;
  let exc = l - bloomKnee;
  if (exc <= 0.0) { return vec3f(0.0); }
  return s * (exc / (l + 0.95));
}

fn fn_reinhardW(c: vec3f) -> f32 {
  return 1.0 / (1.0 + max(dot(c, vec3f(0.2126, 0.7152, 0.0722)), 0.0));
}

// Spatial silhouette-only AA rejecting bright distant background bleed onto close foreground heads/characters
fn smoothSilhouetteEdge(ip: vec2i, dims: vec2i, dz: f32, cur: vec3f) -> vec3f {
  let zc = select(viewZ(dz), 500.0, dz >= 1.0);
  let lumW = vec3f(0.2126, 0.7152, 0.0722);
  let curLum = max(dot(cur, lumW), 0.0);
  let curTone = cur * fn_reinhardW(cur);
  var maxRel = 0.0;
  var zxp = zc; var zxm = zc; var zyp = zc; var zym = zc;
  var txp = curTone; var txm = curTone; var typ = curTone; var tym = curTone;
  for (var k = 0; k < 4; k++) {
    var o = vec2i(1, 0);
    if (k == 1) { o = vec2i(-1, 0); } else if (k == 2) { o = vec2i(0, 1); } else if (k == 3) { o = vec2i(0, -1); }
    let np = clamp(ip + o, vec2i(0), dims - vec2i(1));
    let dn = textureLoad(depthTex, np, 0);
    let zn = select(viewZ(dn), 500.0, dn >= 1.0);
    maxRel = max(maxRel, abs(zn - zc) / max(min(zn, zc), 0.35));
    let cn = textureLoad(sceneTex, np, 0).rgb;
    let rejectHalo = (zn > zc * 1.25 && dot(cn, lumW) > curLum * 1.35 + 0.15);
    let rej = rejectHalo || (zn > zc * 1.20 && zc < 6.0 && dot(cn, lumW) > curLum + 0.035);
    let tn = select(cn * fn_reinhardW(cn), curTone, rej);
    if (k == 0) { zxp = zn; txp = tn; }
    else if (k == 1) { zxm = zn; txm = tn; }
    else if (k == 2) { zyp = zn; typ = tn; }
    else { zym = zn; tym = tn; }
  }
  if (maxRel < 0.16) { return cur; }
  let gx = (zxp - zxm) / max(zc, 0.35);
  let gy = (zyp - zym) / max(zc, 0.35);
  let gLen = max(length(vec2f(gx, gy)), 1e-4);
  let tang = vec2f(-gy, gx) / gLen;
  var diagAcc = vec3f(0.0);
  var diagW = 0.0;
  for (var d = 0; d < 4; d++) {
    let doff = vec2i(select(-1, 1, (d & 1) == 0), select(-1, 1, (d & 2) == 0));
    let np = clamp(ip + doff, vec2i(0), dims - vec2i(1));
    let dn = textureLoad(depthTex, np, 0);
    let zn = select(viewZ(dn), 500.0, dn >= 1.0);
    let align = 0.35 + 0.65 * abs(dot(normalize(vec2f(doff)), tang));
    let dcCol = textureLoad(sceneTex, np, 0).rgb;
    let rejectHalo = (zn > zc * 1.25 && dot(dcCol, lumW) > curLum * 1.35 + 0.15);
    let rejD = rejectHalo || (zn > zc * 1.20 && zc < 6.0 && dot(dcCol, lumW) > curLum + 0.035);
    diagAcc += select(dcCol * fn_reinhardW(dcCol), curTone, rejD) * align;
    diagW += align;
  }
  let cardTone = (txp * (0.4 + 0.6 * abs(tang.x)) + txm * (0.4 + 0.6 * abs(tang.x)) + typ * (0.4 + 0.6 * abs(tang.y)) + tym * (0.4 + 0.6 * abs(tang.y))) / (1.6 + 1.2 * (abs(tang.x) + abs(tang.y)));
  let neighTone = mix(cardTone, diagAcc / max(diagW, 1e-4), 0.38);
  let wEdge = smoothstep(0.16, 0.50, maxRel) * select(0.40, 0.24, zc < 2.6);
  let blendedTone = mix(curTone, neighTone, wEdge);
  return blendedTone / max(1.0 - dot(blendedTone, lumW), 0.18);
}

// Single-pass 4-tap depth crease & grounding AO (cuts depthTex bandwidth in half: 8 -> 4 loads, skips past 16m)
fn applyDepthCrease(p: vec2i, dd: vec2i, dz: f32, dc: f32, col: vec3f) -> vec3f {
  if (dz >= 1.0 || dc > 16.0) { return col; }
  let ddMax = dd - vec2i(1);
  let stepPx = select(2, 1, dc > 9.0);
  let zxp = viewZ(textureLoad(depthTex, clamp(p + vec2i(stepPx, 0), vec2i(0), ddMax), 0));
  let zxm = viewZ(textureLoad(depthTex, clamp(p + vec2i(-stepPx, 0), vec2i(0), ddMax), 0));
  let zyp = viewZ(textureLoad(depthTex, clamp(p + vec2i(0, stepPx), vec2i(0), ddMax), 0));
  let zym = viewZ(textureLoad(depthTex, clamp(p + vec2i(0, -stepPx), vec2i(0), ddMax), 0));
  let invDc = 1.0 / max(dc, 0.4);
  let maxJump = max(max(abs(zxp - dc), abs(zxm - dc)), max(abs(zyp - dc), abs(zym - dc))) * invDc;
  if (maxJump >= 0.18) { return col; }
  let lap = max(0.0, (dc * 4.0 - (zxp + zxm + zyp + zym)) * invDc);
  let distFade = 1.0 - smoothstep(11.0, 16.0, dc);
  let aoDark = smoothstep(0.018, 0.085, lap) * 0.34 * distFade;
  return mix(col, col * vec3f(0.42, 0.44, 0.50), aoDark);
}

// AgX tone curve (minimal fit): scene-linear in, display-linear out
fn agxCurve(x: vec3f) -> vec3f {
  let x2 = x * x;
  let x4 = x2 * x2;
  return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}
fn agx(c: vec3f) -> vec3f {
  let toAgx = mat3x3f(0.842479062253094, 0.0423282422610123, 0.0423756549057051, 0.0784335999999992, 0.878468636469772, 0.0784336, 0.0792237451477643, 0.0791661274605434, 0.879142973793104);
  let fromAgx = mat3x3f(1.19687900512017, -0.0528968517574562, -0.0529716355144438, -0.0980208811401368, 1.15190312990417, -0.0980434501171241, -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
  var v = toAgx * max(c, vec3f(0.0));
  v = clamp((log2(max(v, vec3f(1e-10))) + 12.47393) / 16.5, vec3f(0.0), vec3f(1.0));
  v = agxCurve(v);
  let l = dot(v, vec3f(0.2126, 0.7152, 0.0722));
  let vp = max(v, vec3f(0.0));
  v = vp * mix(vec3f(0.93), vec3f(1.0), vp);
  v = max(vec3f(l) + (v - vec3f(l)) * 1.32, vec3f(0.0));
  let av = max(fromAgx * v, vec3f(0.0));
  return av * av * (0.8 + 0.2 * av);
}

fn sceneAt(uv: vec2f) -> vec3f {
  let dd = vec2i(textureDimensions(depthTex));
  let sc = clamp(vec2i(uv * vec2f(dd)), vec2i(0), dd - vec2i(1));
  let d = textureLoad(depthTex, sc, 0);
  let w = pixelWorld(uv, d);
  let base = textureSampleLevel(sceneTex, linSmp, uv, 0.0).rgb;
  return applyAnalyticFog(uv, d, base, w);
}

// 1-bit Reality Shell duotone filter (World-of-Horror Mint/Plum & Sepia/Rust):
// Strictly screen-locked constant 4x4 staggered square halftone + crisp 1px depth silhouette outline.
// Zero GPU cost in Shell 0 because fsComp skips calling it whenever F.opt.z <= 0.005.
fn applyShellDuotone(ip: vec2i, dd: vec2i, dz: f32, zc: f32, col: vec3f) -> vec3f {
  let mode = u32(F.opt.y + 0.5);
  let light12 = select(vec3f(0.847, 1.0, 0.957), vec3f(0.965, 0.933, 0.847), mode == 2u);
  let dark12  = select(vec3f(0.105, 0.004, 0.062), vec3f(0.185, 0.022, 0.005), mode == 2u);
  let lightC  = select(light12, vec3f(1.0, 0.910, 0.620), mode >= 3u);
  let darkC   = select(dark12,  vec3f(0.032, 0.006, 0.048), mode >= 3u);

  // 1px depth silhouette edge (only 2 extra textureLoads, gated to deeper Shells)
  let zr = viewZ(textureLoad(depthTex, min(ip + vec2i(1, 0), dd - vec2i(1)), 0));
  let zd = viewZ(textureLoad(depthTex, min(ip + vec2i(0, 1), dd - vec2i(1)), 0));
  let edgeDiff = max(abs(zc - zr), abs(zc - zd)) / max(zc, 0.65);
  let isEdge = (dz < 0.9999) && (edgeDiff > 0.11);

  // Perceived brightness mapped onto a fixed screen-space 4x4 staggered square grid
  let lum = pow(clamp(dot(col, vec3f(0.299, 0.587, 0.114)), 0.0, 1.0), 0.78);
  let cellY = (ip.y >> 2) & 1;
  let sx = (ip.x + cellY * 2) & 3;
  let sy = ip.y & 3;
  var ink = isEdge;
  if (!ink) {
    if (lum < 0.16) {
      ink = true;
    } else if (lum < 0.36) {
      // Dense 3x3 square dot
      ink = (sx < 3) && (sy < 3);
    } else if (lum < 0.56) {
      // Midtone 2x2 crisp square dot
      ink = (sx >= 1 && sx <= 2) && (sy >= 1 && sy <= 2);
    } else if (lum < 0.76) {
      // Light 1x1 centered pixel dot
      ink = (sx == 1) && (sy == 1);
    }
  }
  return select(lightC, darkC, ink);
}

@fragment fn fsComp(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  // True native low-res PSX-style 1:1 rasterization (zero post-process pixelation shader, zero silhouette AA blur)
  let uv = fc.xy * F.outRes.zw;
  if (F.taa.z > 0.5 && F.taa.z < 1.5) {
    let b = textureSampleLevel(sceneTex, linSmp, uv, 0.0).rgb;
    return vec4f(pow(clamp(b, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2)), 1.0);
  }
  let dd = vec2i(textureDimensions(depthTex));
  let ip = clamp(vec2i(fc.xy), vec2i(0), dd - vec2i(1));
  let dz = textureLoad(depthTex, ip, 0);
  // Compute linear view depth and reconstructed world position ONCE per pixel; sky pixels skip sceneTex read, SSAO & contact shadows
  let isSky = dz >= 1.0;
  let zc = select(viewZ(dz), 500.0, isSky);
  let wp = wpFromDepth(uv, select(dz, 1.0, isSky));
  let w = pixelWorldWp(dz, wp);
  var col = vec3f(0.0);
  if (!isSky) {
    col = textureLoad(sceneTex, ip, 0).rgb;
    col = applyDepthCrease(ip, dd, dz, zc, col);
    if (F.pbr.y > 0.60 && zc < 9.0) { col *= contactShadowSun(dd, dz, zc, wp); }
  }
  col = applyAnalyticFogWp(dz, wp, col, w);
  if (F.pbr.y > 0.56) { col += sunShafts(ip, dd, uv, w); }
  col += opticalBloom(ip, uv, dd, dz, zc) * 0.095;
  // headache when straying from the story path: the world swims and blurs
  let blur = F.player.w;
  if (blur > 0.01) {
    let t = F.cam.w;
    let r = blur * 0.011 * (1.0 + 0.35 * sin(t * 2.7));
    let wob = vec2f(sin(t * 1.3 + uv.y * 9.0), cos(t * 1.1 + uv.x * 7.0)) * blur * 0.004;
    var acc = col;
    for (var k = 0; k < 6; k++) {
      let a = f32(k) * 1.0472 + t * 0.4;
      acc += sceneAt(uv + wob + vec2f(cos(a), sin(a)) * r * vec2f(F.outRes.y * F.outRes.z, 1.0));
    }
    col = mix(col, acc / 7.0, clamp(blur * 1.4, 0.0, 1.0));
    let l = dot(col, vec3f(0.3, 0.59, 0.11));
    col = mix(col, vec3f(l) * vec3f(1.05, 0.98, 0.95), blur * 0.5) * (1.0 - blur * 0.25);
  }
  let gl = F.misc.z;
  if (gl > 0.01) {
    let fr = F.camUp.w;
    let band = select(0.0, (f32(hashu(u32(uv.y * 48.0) + u32(fr) * 977u) & 255u) / 255.0 - 0.5) * 0.06 * gl, (hashu(u32(uv.y * 48.0) * 31u + u32(fr)) & 7u) == 0u);
    let off = vec2f(gl * 0.01, 0.0);
    let b0 = sceneAt(uv + vec2f(band, 0.0));
    let fringe = vec3f(sceneAt(uv + off + vec2f(band, 0.0)).r - b0.r, 0.0, sceneAt(uv - off + vec2f(band, 0.0)).b - b0.b);
    col = max(col + fringe + select(vec3f(0.0), b0 - sceneAt(uv), band != 0.0) * 0.5, vec3f(0.0));
  }
  // exposure: the nominal value of the time of day x the automatic adaptation (EXPOSURE_SHADER), then AgX
  col = clamp(agx(col * (F.grade.x * F.pbr.w)), vec3f(0.0), vec3f(1.0));

  // 3D LUT Cinematic Grading (16x16x16 volume) + Warm Golden-Amber Tungsten Indoor Grade
  let graded = textureSampleLevel(colorLUT, linSmp, col * (15.0 / 16.0) + (0.5 / 16.0), 0.0).rgb;

  let lum = dot(graded, vec3f(0.299, 0.587, 0.114));
  let indoorTungsten = (1.0 - smoothstep(0.26, 0.72, F.pbr.y)) * (1.0 - w);
  let warmTint = mix(vec3f(1.0, 1.0, 0.995), vec3f(1.12, 0.94, 0.66), indoorTungsten * 0.72);
  let dreamG = mix(graded, graded * graded * (3.0 - 2.0 * graded), 0.42) * warmTint + mix(vec3f(0.001, 0.002, 0.004), vec3f(0.006, 0.003, 0.0005), indoorTungsten);
  let nightG = mix(vec3f(lum), graded, 0.55) * vec3f(1.16, 0.84, 0.82);
  col = mix(dreamG, nightG, w);

  let asp = F.outRes.x * F.outRes.w;
  let vd = length((uv - 0.5) * vec2f(asp, 1.0));
  col *= 1.0 - smoothstep(0.42, 1.05, vd) * (F.grade.y + indoorTungsten * 0.16 + F.fadeCol.w * 0.4);

  // Subtle Film Grain at native framebuffer pixels
  let gn = f32(hashu(u32(fc.x) + u32(fc.y) * 4099u + u32(F.camUp.w) * 7919u) & 1023u) / 1023.0 - 0.5;
  col += vec3f(gn * F.grade.w * (0.70 + 0.25 * lum));

  // Reality Shell 1-bit Duotone transformation (skipped cleanly in Shell 0)
  if (F.opt.z > 0.005) {
    let duo = applyShellDuotone(ip, dd, dz, zc, col);
    col = mix(col, duo, clamp(F.opt.z, 0.0, 1.0));
  }
  // Subtle resonant edge flash on PERFECT rhythm combat strikes
  if (F.opt.w > 0.01) {
    let rim = smoothstep(0.32, 0.92, vd) * F.opt.w;
    let pulseCol = select(vec3f(0.95, 0.82, 0.48), vec3f(0.75, 1.0, 0.90), F.opt.z > 0.5);
    col += pulseCol * rim * 0.24;
  }

  col = mix(col, F.fadeCol.rgb, F.misc.w);
  let oc = max(col, vec3f(0.0));
  return vec4f(mix(sqrt(oc), oc, 0.09), 1.0);
}
