
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
@group(0) @binding(2) var volTex: texture_2d<f32>;
@group(0) @binding(3) var depthTex: texture_depth_2d;
@group(0) @binding(4) var linSmp: sampler;
@group(0) @binding(7) var dofTex: texture_2d<f32>;
@group(0) @binding(8) var histTex: texture_2d<f32>;
@group(0) @binding(9) var gbufTex: texture_2d<f32>;
@group(0) @binding(10) var colorLUT: texture_3d<f32>;
// temporal anti-aliasing inside the final pass: the scene pixel is blended with last frame's
// reprojected result (clamped to the current neighbourhood); the result is also written out as the
// history for the next frame (second render target) - no separate full-screen TAA pass
struct TaaOut { col: vec3f, detail: vec3f };
fn ycc(c: vec3f) -> vec3f { return vec3f(dot(c, vec3f(0.25, 0.5, 0.25)), dot(c, vec3f(0.5, 0.0, -0.5)), dot(c, vec3f(-0.25, 0.5, -0.25))); }
fn rgbOf(c: vec3f) -> vec3f { return vec3f(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z); }
fn max3(c: vec3f) -> f32 { return max(c.x, max(c.y, c.z)); }
// history with a Catmull-Rom filter in 5 bilinear taps: stays sharp while it is reprojected every frame
fn histCatmull(uv: vec2f) -> vec3f {
  let dim = vec2f(textureDimensions(histTex));
  let sp = uv * dim;
  let tc = floor(sp - 0.5) + 0.5;
  let f = sp - tc;
  let w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
  let w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
  let w2 = f * (0.5 + f * (2.0 - 1.5 * f));
  let w3 = f * f * (-0.5 + 0.5 * f);
  let w12 = w1 + w2;
  let t0 = (tc - 1.0) / dim;
  let t3 = (tc + 2.0) / dim;
  let t12 = (tc + w2 / w12) / dim;
  var c = textureSampleLevel(histTex, linSmp, vec2f(t12.x, t0.y), 0.0).rgb * (w12.x * w0.y);
  c += textureSampleLevel(histTex, linSmp, vec2f(t0.x, t12.y), 0.0).rgb * (w0.x * w12.y);
  c += textureSampleLevel(histTex, linSmp, t12, 0.0).rgb * (w12.x * w12.y);
  c += textureSampleLevel(histTex, linSmp, vec2f(t3.x, t12.y), 0.0).rgb * (w3.x * w12.y);
  c += textureSampleLevel(histTex, linSmp, vec2f(t12.x, t3.y), 0.0).rgb * (w12.x * w3.y);
  return max(c / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y), vec3f(0.0));
}
// Temporal anti-aliasing and upscaling in the final pass. The scene is rendered with a sub-pixel Halton(2,3)
// jitter (and may be smaller than the output); every output pixel takes the nearest scene sample, trusts it by its
// distance to the pixel centre, and blends it with the history reprojected through the depth (camera motion).
// The history is clipped to the mean +- 1.25 sigma of the 5-tap neighbourhood in YCoCg; pixels of moving objects
// (G-buffer flag) lean on the current frame. detail = RCAS sharpening of the result, limited by the neighbourhood.
fn taaResolve(uv: vec2f, dz: f32, dyn: bool) -> TaaOut {
  let dims = vec2i(textureDimensions(sceneTex));
  let fd = vec2f(dims);
  let suv = uv + F.fx2.zw;
  let ip = clamp(vec2i(suv * fd), vec2i(0), dims - vec2i(1));
  let cur = textureLoad(sceneTex, ip, 0).rgb;
  let yc = ycc(cur);
  var m1 = yc;
  var m2 = yc * yc;
  var mn = yc;
  var mx = yc;
  var rmn = vec3f(1.0);
  var rmx = vec3f(0.0);
  var rsum = vec3f(0.0);
  for (var k = 0; k < 4; k++) {
    var o = vec2i(1, 0);
    if (k == 1) { o = vec2i(-1, 0); } else if (k == 2) { o = vec2i(0, 1); } else if (k == 3) { o = vec2i(0, -1); }
    let c = textureLoad(sceneTex, clamp(ip + o, vec2i(0), dims - vec2i(1)), 0).rgb;
    let y = ycc(c);
    m1 += y; m2 += y * y; mn = min(mn, y); mx = max(mx, y);
    let t = c / (1.0 + max3(c));
    rmn = min(rmn, t); rmx = max(rmx, t); rsum += t;
  }
  var res = cur;
  var motion = 0.0;
  if (F.taa.w > 0.5) {
    let w4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, dz, 1.0);
    let pp = F.prevVP * vec4f(w4.xyz / w4.w, 1.0);
    let puv = vec2f(pp.x / pp.w * 0.5 + 0.5, 0.5 - pp.y / pp.w * 0.5);
    if (pp.w > 0.0 && puv.x >= 0.0 && puv.y >= 0.0 && puv.x <= 1.0 && puv.y <= 1.0) {
      let mean = m1 * 0.2;
      let sig = sqrt(max(m2 * 0.2 - mean * mean, vec3f(0.0)));
      let lo = max(mn, mean - sig * 1.25) - vec3f(0.004);
      let hi = min(mx, mean + sig * 1.25) + vec3f(0.004);
      // clip the history towards the centre of the box (keeps its hue instead of clamping per channel)
      var h = ycc(textureSampleLevel(histTex, linSmp, puv, 0.0).rgb); // one bilinear tap (the sharpening below makes up for its softness)
      let bc = (lo + hi) * 0.5;
      let be = (hi - lo) * 0.5 + vec3f(0.0001);
      let hv = h - bc;
      let ha = abs(hv / be);
      let hm = max(ha.x, max(ha.y, ha.z));
      if (hm > 1.0) { h = bc + hv / hm; }
      motion = length((puv - uv) * F.outRes.xy);
      // how far the scene sample is from this output pixel's centre, in scene pixels (0 .. 0.7)
      let off = length(((vec2f(ip) + 0.5) / fd - suv) * fd);
      var blend = clamp(0.1 + motion * 0.01, 0.1, 0.3) * mix(1.0, 0.3, clamp(off * 1.5, 0.0, 1.0));
      if (dyn) { blend = max(blend, 0.35); }
      let wc = blend / (1.0 + yc.x);
      let wh = (1.0 - blend) / (1.0 + max(h.x, 0.0));
      res = max(rgbOf((yc * wc + h * wh) / (wc + wh)), vec3f(0.0));
    }
  }
  // RCAS: the negative lobe is as strong as the local contrast allows without ringing
  let e = res / (1.0 + max3(res));
  let hitMin = rmn / (4.0 * rmx + vec3f(0.0001));
  let hitMax = (vec3f(1.0) - rmx) / (4.0 * rmn - vec3f(4.0001));
  let lobe3 = max(-hitMin, hitMax);
  let lobe = max(-0.1875, min(max3(lobe3), 0.0)) * F.opt.y;
  let sh = clamp((rsum * lobe + e) / (4.0 * lobe + 1.0), vec3f(0.0), vec3f(0.98));
  return TaaOut(res, (sh / (1.0 - max3(sh)) - res) / (1.0 + motion * 0.35));
}
struct CompOut { @location(0) c: vec4f, @location(1) hist: vec4f };
// soft clouds drifting over the forest; in the nightmare they are low, torn and blood-red
// Fast analytical sky + crisp sun disc & corona (zero 3D noise texture fetches, zero pow() calls)
fn skyColor(rd: vec3f, w: f32) -> vec3f {
  // below the horizon the visible sky keeps the horizon haze (the dome's ground half is for the lighting only)
  let d = normalize(vec3f(rd.x, max(rd.y, 0.0), rd.z));
  let s = max(dot(rd, F.sunDir.xyz), 0.0);
  var c = skyDome(d, w) + mix(F.skyPD[3].rgb, F.skyPN[3].rgb, w) * smoothstep(0.9978, 0.9993, s) * 6.5; // the sun, at night the moon
  let st = mix(F.skyX[0].w, F.skyX[1].w, w);
  if (st > 0.01 && rd.y > 0.02) {
    // stars: single lit cells of a fine grid on the dome, twinkling a little
    let h = hash3i(vec3i(floor(d * 230.0)));
    c += vec3f(0.85, 0.92, 1.0) * (step(0.9968, h) * st * (0.7 + 0.3 * sin(F.cam.w * (1.3 + h * 2.0) + h * 400.0)) * smoothstep(0.02, 0.22, rd.y) * 0.5);
  }
  return c;
}
// AgX tone curve (minimal fit): scene-linear in, display-linear out; keeps the shadows and desaturates the highlights
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
  // a little more contrast and colour than the neutral base look
  let l = dot(v, vec3f(0.2126, 0.7152, 0.0722));
  v = pow(max(v, vec3f(0.0)), vec3f(1.08));
  v = max(vec3f(l) + (v - vec3f(l)) * 1.3, vec3f(0.0));
  return pow(max(fromAgx * v, vec3f(0.0)), vec3f(2.2));
}
// Distant, gentle background bokeh: starts far behind the player (focus + 22m) and never blurs the sky/sun
fn cocAt(uv: vec2f, depth: f32) -> f32 {
  if (depth >= 0.9999) { return 0.0; }
  let d = max(F.taa.x * F.taa.y / (F.taa.y - depth * (F.taa.y - F.taa.x)), 0.05);
  let focus = max(distance(F.player.xyz + vec3f(0.0, 1.0, 0.0), F.cam.xyz), 1.0);
  return clamp((d - (focus + 22.0)) / 38.0, 0.0, 0.52);
}
fn dofScene(uv: vec2f, col: vec3f, coc: f32) -> vec3f {
  if (F.misc.w > 0.98) { return col; }
  if (coc < 0.02) { return col; }
  let bl = textureSampleLevel(dofTex, linSmp, uv, 0.0);
  if (bl.a < 0.01) { return col; }
  return mix(col, bl.rgb / bl.a, smoothstep(0.02, 0.52, coc) * 0.72);
}
@fragment fn fsDofDown(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let res = F.res.xy;
  let dd = vec2i(textureDimensions(depthTex));
  let c = fc.xy * 4.0 / res;
  var sky = vec3f(0.0); var skyDone = false;
  var acc = vec3f(0.0); var ws = 0.0; var cs = 0.0;
  for (var k = 0; k < 4; k++) {
    let o = vec2f(f32(k & 1), f32(k >> 1)) * 2.0 - 1.0;
    let uv = c + o / res;
    let p = clamp(vec2i(uv * res), vec2i(0), dd - vec2i(1));
    let z = textureLoad(depthTex, p, 0);
    var col = textureSampleLevel(sceneTex, linSmp, uv, 0.0).rgb;
    if (z >= 1.0) {
      if (!skyDone) {
        let wp4 = F.invViewProj * vec4f(c.x * 2.0 - 1.0, 1.0 - c.y * 2.0, 1.0, 1.0);
        sky = select(skyColor(normalize(wp4.xyz / wp4.w - F.cam.xyz), pixelWorld(c, 1.0)), vec3f(0.0), F.misc.x > 0.5);
        skyDone = true;
      }
      col = sky;
    }
    let cc = cocAt(uv, z);
    acc += col * (cc + 0.02); ws += cc + 0.02; cs += cc;
  }
  if (F.counts.z == 0u) {
    return vec4f(acc / max(ws, 1e-4), cs * 0.25);
  }
  let fog = textureSampleLevel(volTex, linSmp, c, 0.0);
  return vec4f((acc / ws) * fog.a + fog.rgb, cs * 0.25);
}
// Soft 8-tap Golden-Angle bokeh filter: halves GPU texture bandwidth and gently separates distant background
@fragment fn fsBokeh(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let dims = vec2i(textureDimensions(dofTex));
  let R = clamp(F.res.y * 0.25 * 0.013, 1.4, 3.6);
  var acc = vec3f(0.0); var ws = 0.0;
  let inv = 1.0 / vec2f(dims);
  for (var k = 0; k < 8; k++) {
    let fk = f32(k) + 0.5;
    let rr = sqrt(fk * 0.125) * R;
    let a = fk * 2.39996;
    let sm = textureSampleLevel(dofTex, linSmp, (fc.xy + vec2f(cos(a), sin(a)) * rr) * inv, 0.0);
    let w = 1.0 + sm.a * 2.5;
    acc += sm.rgb * w; ws += w;
  }
  return vec4f(acc / max(ws, 1e-4), 1.0);
}
@fragment fn fsDofSmooth(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let dims = max(floor(F.res.xy * 0.25), vec2f(1.0));
  var acc = vec4f(0.0);
  for (var k = 0; k < 4; k++) {
    let o = vec2f(f32(k & 1), f32(k >> 1)) - 0.5;
    acc += textureSampleLevel(dofTex, linSmp, (fc.xy + o) / dims, 0.0);
  }
  return acc * 0.25;
}
// Deferred G-Buffer normal + depth outline & deferred bounce/subsurface lighting
fn outlineAndDeferred(p: vec2i, dz: f32, uv: vec2f, colIn: vec3f) -> vec3f {
  let dd = vec2i(textureDimensions(depthTex));
  if (dz >= 1.0) { return colIn; }
  let dc = viewZ(dz);
  let gb = textureLoad(gbufTex, p, 0);
  let gNorm = normalize(gb.rgb * 2.0 - 1.0);
  let isFoliage = gb.a >= 0.495;
  let gRest = gb.a - select(0.0, 0.5, isFoliage);
  let gRest2 = gRest - select(0.0, 0.25, gRest >= 0.245);
  let gAo = clamp((gRest2 - select(0.0, 0.125, gRest2 >= 0.12)) / 0.115, 0.0, 1.0);

  // Deferred indirect sky/ground bounce & foliage rim refinement from G-Buffer normal
  let w = pixelWorld(uv, dz);
  let skyBounce = skyCol(w) * (gNorm.y * 0.5 + 0.5) * 0.07 * gAo;
  var col = colIn + colIn * skyBounce;
  if (isFoliage) {
    let sunWrap = clamp(dot(gNorm, F.sunDir.xyz) * 0.5 + 0.5, 0.0, 1.0);
    col *= 0.92 + 0.14 * sunWrap * (0.5 + 0.5 * gAo);
    return col;
  }

  if (dc > 35.0) { return col; }
  // depth step to the right / lower neighbour (two taps each: the foliage flag and the depth)
  var mx = 0.0;
  for (var k = 0; k < 2; k++) {
    let np = clamp(p + vec2i(1 - k, k), vec2i(0), dd - vec2i(1));
    if (textureLoad(gbufTex, np, 0).a >= 0.495) { continue; } // do not crease against foliage
    let dn = textureLoad(depthTex, np, 0);
    let zn = select(viewZ(dn), 500.0, dn >= 1.0);
    mx = max(mx, abs(zn - dc) / min(zn, dc));
  }
  let edge = smoothstep(0.14, 0.28, mx) * (1.0 - smoothstep(18.0, 32.0, dc));
  return mix(col, col * vec3f(0.38, 0.36, 0.34), edge * 0.45);
}
fn pixelWorld(uv: vec2f, depth: f32) -> f32 {
  if (F.misc.x > 0.5) { return 1.0; }
  if (F.waveP.z < 0.5) { return F.sunDir.w; }
  if (depth >= 1.0) {
    let tn = smoothstep(3.0, 70.0, F.wave.w);
    var f = tn;
    if (F.wave2.w > 0.0) { f = 1.0 - smoothstep(3.0, 70.0, F.wave2.w) * (1.0 - tn); }
    return mix(F.waveP.x, F.waveP.y, f);
  }
  let wp4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
  let p = wp4.xyz / wp4.w;
  let inside = distance(p, F.wave.xyz) < F.wave.w || (F.wave2.w > 0.0 && distance(p, F.wave2.xyz) > F.wave2.w);
  return select(F.waveP.x, F.waveP.y, inside);
}
fn sceneAt(uv: vec2f) -> vec3f {
  let res = vec2i(F.res.xy);
  let sc = clamp(vec2i(uv * F.res.xy), vec2i(0), res - vec2i(1));
  return sceneAtZ(uv, textureLoad(depthTex, sc, 0));
}
fn sceneAtZ(uv: vec2f, d: f32) -> vec3f { return skyFog(uv, d, textureSampleLevel(sceneTex, linSmp, uv, 0.0).rgb); }
fn skyFog(uv: vec2f, d: f32, base: vec3f) -> vec3f {
  var col = base;
  if (d >= 1.0) {
    let wp4 = F.invViewProj * vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 1.0, 1.0);
    let rd = normalize(wp4.xyz / wp4.w - F.cam.xyz);
    col = select(skyColor(rd, pixelWorld(uv, 1.0)), vec3f(0.0), F.misc.x > 0.5);
    if (F.counts.z == 0u) {
      let w = pixelWorld(uv, 1.0);
      let fogCol = fogCol(w);
      col = mix(col, fogCol, 0.45);
      return col;
    }
  }
  if (F.counts.z == 0u) {
    return col;
  }
  let fog = fogAt(uv, d);
  return col * fog.a + fog.rgb;
}
// the quarter-resolution fog: plain bilinear far away; near the camera the 4 texels around are weighted by how
// close their depth is, so the fog of the background does not leak onto the hero's outline
fn fogAt(uv: vec2f, d: f32) -> vec4f {
  let z = viewZ(d);
  let bl = textureSampleLevel(volTex, linSmp, uv, 0.0);
  // the depth-aware filter wherever an edge can show a halo of the half-resolution fog (very thin fog: plain bilinear)
  if (d >= 1.0 || z > 90.0 || bl.a > 0.992) { return bl; }
  let vd = vec2i(textureDimensions(volTex));
  let dd = vec2i(textureDimensions(depthTex));
  let vp = uv * vec2f(vd) - 0.5;
  let b = vec2i(floor(vp));
  let f = vp - floor(vp);
  var acc = vec4f(0.0);
  var ws = 0.0;
  for (var k = 0; k < 4; k++) {
    let o = vec2i(k & 1, k >> 1);
    let q = clamp(b + o, vec2i(0), vd - vec2i(1));
    let zq = viewZ(textureLoad(depthTex, min(q * (dd / vd) + (dd / vd) / 2, dd - vec2i(1)), 0));
    let wg = mix(1.0 - f.x, f.x, f32(o.x)) * mix(1.0 - f.y, f.y, f32(o.y)) / (0.04 + abs(zq - z) / z * 6.0);
    acc += textureLoad(volTex, q, 0) * wg;
    ws += wg;
  }
  return acc / max(ws, 0.00001);
}
@fragment fn fsComp(@builtin(position) fc: vec4f) -> CompOut {
  var out: CompOut;
  let uv = fc.xy * F.outRes.zw;
  if (F.taa.z > 0.5 && F.taa.z < 1.5) {
    let b = textureSampleLevel(sceneTex, linSmp, uv, 0.0).rgb;
    out.c = vec4f(pow(clamp(b, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2)), 1.0); out.hist = vec4f(b, 1.0);
    return out;
  }
  let dd = vec2i(textureDimensions(depthTex));
  let pz = min(vec2i(uv * vec2f(dd)), dd - vec2i(1));
  let dz = textureLoad(depthTex, pz, 0);
  let gflag = textureLoad(gbufTex, pz, 0).a;
  let grest = gflag - select(0.0, 0.5, gflag >= 0.495);
  let taaRes = taaResolve(uv, dz, dz < 1.0 && (grest - select(0.0, 0.25, grest >= 0.245)) >= 0.12);
  let taa = taaRes.col;
  out.hist = vec4f(taa, 1.0);
  var col = skyFog(uv, dz, taa);
  col = outlineAndDeferred(pz, dz, uv, col);
  let keepSharp = dz >= 0.9999;
  let coc0 = select(cocAt(uv, dz), 0.0, keepSharp);
  if (coc0 < 0.3) {
    col = max(col + taaRes.detail * (1.0 - smoothstep(0.0, 0.3, coc0)), col * 0.5);
  }
  col = dofScene(uv, col, coc0);
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
    // colour fringes and torn bands on top of the finished image (keeps the blur, light and outline)
    let off = vec2f(gl * 0.01, 0.0);
    let b0 = sceneAt(uv + vec2f(band, 0.0));
    let fringe = vec3f(sceneAt(uv + off + vec2f(band, 0.0)).r - b0.r, 0.0, sceneAt(uv - off + vec2f(band, 0.0)).b - b0.b);
    col = max(col + fringe + select(vec3f(0.0), b0 - sceneAt(uv), band != 0.0) * 0.5, vec3f(0.0));
  }
  // chromatic aberration of the lens: red and blue drift apart by up to F.opt.z pixels, only towards the corners
  let cad = (uv - 0.5) * vec2f(F.outRes.x * F.outRes.w, 1.0);
  let ca = F.opt.z * smoothstep(0.5, 1.0, length(cad));
  if (ca > 0.02 && dz < 1.0) {
    let cof = normalize(uv - 0.5) * ca * F.outRes.zw;
    let s0 = textureSampleLevel(sceneTex, linSmp, uv, 0.0).rgb;
    col.r = max(col.r + textureSampleLevel(sceneTex, linSmp, uv + cof, 0.0).r - s0.r, 0.0);
    col.b = max(col.b + textureSampleLevel(sceneTex, linSmp, uv - cof, 0.0).b - s0.b, 0.0);
  }
  let w = pixelWorld(uv, dz);
  // exposure: the nominal value of the time of day x the automatic adaptation (EXPOSURE_SHADER), then AgX
  col = clamp(agx(col * (F.grade.x * F.pbr.w)), vec3f(0.0), vec3f(1.0));
  
  // 3D LUT Cinematic Grading (16x16x16 volume)
  let graded = textureSampleLevel(colorLUT, linSmp, col * (15.0 / 16.0) + (0.5 / 16.0), 0.0).rgb;
  
  let lum = dot(graded, vec3f(0.299, 0.587, 0.114));
  let dreamG = mix(graded, graded * graded * (3.0 - 2.0 * graded), 0.35) * vec3f(1.0, 1.0, 0.99) + vec3f(0.006, 0.008, 0.012);
  let nightG = mix(vec3f(lum), graded, 0.5) * vec3f(1.15, 0.84, 0.82);
  col = mix(dreamG, nightG, w);

  let asp = F.outRes.x * F.outRes.w;
  let vd = length((uv - 0.5) * vec2f(asp, 1.0));
  col *= 1.0 - smoothstep(0.42, 1.05, vd) * (F.grade.y + F.fadeCol.w * 0.4);

  // Soft Film Grain (temporal, resolution-aware)
  let gn = f32(hashu(u32(fc.x) + u32(fc.y) * 4099u + u32(F.camUp.w) * 7919u) & 1023u) / 1023.0 - 0.5;
  col += vec3f(gn * F.grade.w * (0.85 + 0.25 * lum));

  col = mix(col, F.fadeCol.rgb, F.misc.w);
  out.c = vec4f(pow(max(col, vec3f(0.0)), vec3f(1.0 / 2.2)), 1.0);
  return out;
}
