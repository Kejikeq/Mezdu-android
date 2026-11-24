
struct ExpU { dt: f32, range: f32, key: f32, skyLum: f32, nomExp: f32, step: u32, w: u32, h: u32 };
@group(0) @binding(0) var<uniform> U: ExpU;
@group(0) @binding(1) var sceneTex: texture_2d<f32>;
@group(0) @binding(2) var depthTex: texture_depth_2d;
@group(0) @binding(3) var<storage, read_write> bins: array<atomic<u32>, 64>;
@group(0) @binding(4) var<storage, read_write> expo: array<f32, 4>; // factor, mean luminance, target, -
@compute @workgroup_size(8, 8) fn expHist(@builtin(global_invocation_id) gid: vec3u) {
  let p = gid.xy * U.step + vec2u(U.step / 2u);
  if (p.x >= U.w || p.y >= U.h) { return; }
  let uv = vec2f(f32(p.x) / max(f32(U.w), 1.0), f32(p.y) / max(f32(U.h), 1.0));
  let isSky = textureLoad(depthTex, p, 0) >= 0.9999;
  var lum = dot(textureLoad(sceneTex, p, 0).rgb, vec3f(0.2126, 0.7152, 0.0722));
  if (isSky) { lum = U.skyLum; }
  // Center-weighted metering prioritizes hero, architecture & terrain over upper bright sky
  let cd = length((uv - vec2f(0.5, 0.54)) * vec2f(1.25, 1.0));
  var weight = select(select(1u, 2u, cd < 0.45), 4u, cd < 0.24);
  if (isSky) { weight = 1u; }
  atomicAdd(&bins[u32(clamp((log2(max(lum, 0.00001)) + 10.0) * 4.0, 0.0, 63.0))], weight);
}
@compute @workgroup_size(1) fn expResolve() {
  var cnt: array<f32, 64>;
  var total = 0.0;
  for (var i = 0u; i < 64u; i++) { cnt[i] = f32(atomicExchange(&bins[i], 0u)); total += cnt[i]; }
  if (total < 16.0) { return; }
  let lo = total * 0.25;
  let hi = total * 0.85;
  var acc = 0.0;
  var sum = 0.0;
  var n = 0.0;
  for (var i = 0u; i < 64u; i++) {
    let a0 = acc;
    acc += cnt[i];
    let take = max(min(acc, hi) - max(a0, lo), 0.0);
    sum += take * ((f32(i) + 0.5) * 0.25 - 10.0);
    n += take;
  }
  let avg = exp2(sum / max(n, 1.0));
  let goal = clamp(U.key / (avg * U.nomExp), exp2(-U.range * 0.72), exp2(U.range * 1.10));
  let cur = select(expo[0], 1.0, expo[0] <= 0.001);
  let tau = select(2.1, 1.1, goal < cur);
  expo[0] = mix(cur, goal, 1.0 - exp(-U.dt / tau));
  expo[1] = avg;
  expo[2] = goal;
}
