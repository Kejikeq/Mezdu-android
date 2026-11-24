
struct PU { viewProj: mat4x4f, model: mat4x4f, light: vec4f, params: vec4f, pivot: vec4f, tint: vec4f };
@group(0) @binding(0) var<uniform> U: PU;
@group(0) @binding(1) var<storage, read> mfaces: array<u32>;
var<private> NAX: array<u32, 6> = array<u32, 6>(0u, 0u, 1u, 1u, 2u, 2u);
var<private> UAX: array<u32, 6> = array<u32, 6>(1u, 2u, 2u, 0u, 0u, 1u);
var<private> VAX: array<u32, 6> = array<u32, 6>(2u, 1u, 0u, 2u, 1u, 0u);
var<private> NPOS: array<f32, 6> = array<f32, 6>(1.0, 0.0, 1.0, 0.0, 1.0, 0.0);
var<private> NRM: array<vec3f, 6> = array<vec3f, 6>(vec3f(1.0, 0.0, 0.0), vec3f(-1.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vec3f(0.0, -1.0, 0.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, -1.0));
var<private> QUAD: array<u32, 6> = array<u32, 6>(0u, 1u, 2u, 0u, 2u, 3u);
var<private> QUADF: array<u32, 6> = array<u32, 6>(1u, 2u, 3u, 1u, 3u, 0u);
var<private> CU: array<f32, 4> = array<f32, 4>(0.0, 1.0, 1.0, 0.0);
var<private> CV: array<f32, 4> = array<f32, 4>(0.0, 0.0, 1.0, 1.0);
struct VO { @builtin(position) pos: vec4f, @location(0) n: vec3f, @location(1) col: vec3f, @location(2) ao: f32, @location(3) @interpolate(flat) fl: u32, @location(4) wp: vec3f };
fn decodeOct9Preview(pk: u32) -> vec3f {
  let ox = f32(pk & 511u) * (2.0 / 511.0) - 1.0;
  let oy = f32((pk >> 9u) & 511u) * (2.0 / 511.0) - 1.0;
  var n = vec3f(ox, oy, 1.0 - abs(ox) - abs(oy));
  if (n.z < 0.0) {
    let sx = select(-1.0, 1.0, n.x >= 0.0);
    let sy = select(-1.0, 1.0, n.y >= 0.0);
    n = vec3f((1.0 - abs(n.y)) * sx, (1.0 - abs(n.x)) * sy, n.z);
  }
  return normalize(n);
}
@vertex fn vs(@builtin(vertex_index) vi: u32) -> VO {
  let mode = u32(U.params.w + 0.5); // 0: v1(2u), 1: v2(3u), 2: lowpoly(6u), 3: smooth(10u)
  let stride = select(select(select(2u, 3u, mode == 1u), 6u, mode == 2u), 10u, mode == 3u);
  let fo = u32(U.params.y) + (vi / 6u) * stride;
  let k = vi % 6u;
  let w0 = mfaces[fo];
  let w1 = mfaces[fo + 1u];
  var dir = (w0 >> 24u) & 7u;
  var part = (w0 >> 27u) & 15u;
  var em = w0 >> 31u;
  var lp = vec3f(f32(w0 & 255u), f32((w0 >> 8u) & 255u), f32((w0 >> 16u) & 255u));
  var du = 1.0; var dv = 1.0;
  var colWord = w1;
  var nrm = NRM[dir];
  var c = QUAD[k];
  if (mode >= 2u) {
    colWord = mfaces[fo + 4u];
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
    if (mode == 3u) {
      nrm = decodeOct9Preview(mfaces[fo + 6u + c]);
    } else {
      let fnRaw = cross(p2 - p0, p3 - p1);
      nrm = normalize(select(vec3f(0.0, 1.0, 0.0), fnRaw, length(fnRaw) > 1e-5));
    }
  } else {
    if (mode == 1u) {
      let w2 = mfaces[fo + 2u];
      lp = vec3f(f32(w0 & 1023u), f32((w0 >> 10u) & 4095u), f32((w0 >> 22u) & 1023u));
      dir = w2 & 7u; part = (w2 >> 3u) & 15u; em = (w2 >> 7u) & 1u;
      du = f32(((w2 >> 8u) & 255u) + 1u); dv = f32(((w2 >> 16u) & 255u) + 1u);
    }
    let aow = colWord >> 24u;
    if ((aow & 3u) + ((aow >> 4u) & 3u) > ((aow >> 2u) & 3u) + ((aow >> 6u) & 3u)) { c = QUADF[k]; }
    nrm = NRM[dir];
    lp[NAX[dir]] += NPOS[dir];
    lp[UAX[dir]] += CU[c] * du;
    lp[VAX[dir]] += CV[c] * dv;
  }
  let aow = colWord >> 24u;
  let p = (lp - U.pivot.xyz) * U.pivot.w;
  let wp = (U.model * vec4f(p, 1.0)).xyz;
  var o: VO;
  o.pos = U.viewProj * vec4f(wp, 1.0);
  o.n = (U.model * vec4f(nrm, 0.0)).xyz;
  o.col = pow(vec3f(f32((colWord >> 16u) & 255u), f32((colWord >> 8u) & 255u), f32(colWord & 255u)) / 255.0, vec3f(2.2));
  o.ao = f32((aow >> (c * 2u)) & 3u) / 3.0;
  o.fl = part | (em << 4u);
  o.wp = wp;
  return o;
}
@fragment fn fs(i: VO) -> @location(0) vec4f {
  let n = normalize(i.n);
  let L = normalize(U.light.xyz);
  let key = max(dot(n, L), 0.0) * vec3f(1.0, 0.93, 0.82) * 1.6;
  let fill = max(dot(n, normalize(vec3f(-0.6, 0.2, 0.5))), 0.0) * vec3f(0.45, 0.55, 0.75) * 0.6;
  let v = normalize(-i.wp + vec3f(0.0, 0.0, U.params.z));
  let rim = pow(1.0 - max(dot(n, normalize(vec3f(0.0, 0.0, 1.0))), 0.0), 3.0) * 0.25;
  let amb = mix(vec3f(0.16, 0.14, 0.13), vec3f(0.34, 0.36, 0.42), n.y * 0.5 + 0.5);
  var c = i.col * (key + fill + amb * (0.35 + 0.65 * i.ao)) + vec3f(rim) * i.col;
  let part = i.fl & 15u;
  if (((i.fl >> 4u) & 1u) == 1u) {
    var k = 1.4;
    if (part == 5u) { k = 1.0 + sin(U.params.x * 3.0) * 0.8; }
    c += i.col * k;
  }
  if (part == 6u) { c = mix(c, vec3f(0.3, 0.9, 1.2), 0.55 + 0.25 * sin(U.params.x * 2.0)); }
  c *= U.tint.rgb;
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return vec4f(pow(clamp(c, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2)), 1.0);
}
