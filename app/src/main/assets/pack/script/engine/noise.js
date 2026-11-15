// Deterministic integer hashing and value noise.
// hashu / hash3i / vnoise3 are bit-exact mirrors of the WGSL versions in gfx/wgsl.js,
// so CPU gameplay (collision world) and GPU visuals agree on the dream/nightmare boundary.

export function hashu(x) {
  const v = (Math.imul(x >>> 0, 747796405) + 2891336453) >>> 0;
  const w = Math.imul(((v >>> ((v >>> 28) + 4)) ^ v) >>> 0, 277803737) >>> 0;
  return ((w >>> 22) ^ w) >>> 0;
}

export function hash3i(x, y, z) {
  const h = hashu(((x >>> 0) + hashu(((y >>> 0) + hashu(z >>> 0)) >>> 0)) >>> 0);
  return h / 4294967296;
}

export function hash2i(x, z, seed = 0) {
  return hash3i(x | 0, z | 0, seed | 0);
}

const sm = (t) => t * t * (3 - 2 * t);

export function vnoise3(x, y, z) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const fx = x - xi, fy = y - yi, fz = z - zi;
  const ux = sm(fx), uy = sm(fy), uz = sm(fz);
  const a = hash3i(xi, yi, zi), b = hash3i(xi + 1, yi, zi);
  const c = hash3i(xi, yi + 1, zi), d = hash3i(xi + 1, yi + 1, zi);
  const e = hash3i(xi, yi, zi + 1), f = hash3i(xi + 1, yi, zi + 1);
  const g = hash3i(xi, yi + 1, zi + 1), h = hash3i(xi + 1, yi + 1, zi + 1);
  const x00 = a + (b - a) * ux, x10 = c + (d - c) * ux;
  const x01 = e + (f - e) * ux, x11 = g + (h - g) * ux;
  const y0 = x00 + (x10 - x00) * uy, y1 = x01 + (x11 - x01) * uy;
  return y0 + (y1 - y0) * uz;
}

export function vnoise2(x, z, seed = 0) {
  const xi = Math.floor(x), zi = Math.floor(z);
  const fx = x - xi, fz = z - zi;
  const u = sm(fx), v = sm(fz);
  const a = hash3i(xi, seed, zi), b = hash3i(xi + 1, seed, zi);
  const c = hash3i(xi, seed, zi + 1), d = hash3i(xi + 1, seed, zi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

export function fbm2(x, z, seed = 0, oct = 4) {
  let s = 0, amp = 0.5, f = 1, n = 0;
  for (let i = 0; i < oct; i++) {
    s += amp * vnoise2(x * f, z * f, seed + i * 17);
    n += amp; amp *= 0.5; f *= 2.03;
  }
  return s / n;
}

// Small fast seeded PRNG (mulberry32)
export function rng(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smoothstep = (e0, e1, x) => {
  const t = clamp((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
};
