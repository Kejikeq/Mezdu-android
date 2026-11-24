// Minimal column-major mat4 + row-major 3x4 affine helpers (allocation-free hot paths).

export function mat4() { const m = new Float32Array(16); m[0] = m[5] = m[10] = m[15] = 1; return m; }

export function perspective(out, fovy, aspect, near, far) {
  const f = 1 / Math.tan(fovy / 2), nf = 1 / (near - far);
  out.fill(0);
  out[0] = f / aspect; out[5] = f; out[10] = far * nf; out[11] = -1; out[14] = far * near * nf;
  return out;
}

// WebGPU depth range [0,1]
export function ortho(out, l, r, b, t, n, f) {
  out.fill(0);
  out[0] = 2 / (r - l); out[5] = 2 / (t - b); out[10] = 1 / (n - f);
  out[12] = -(r + l) / (r - l); out[13] = -(t + b) / (t - b); out[14] = n / (n - f); out[15] = 1;
  return out;
}

export function lookAt(out, eye, c, up) {
  let zx = eye[0] - c[0], zy = eye[1] - c[1], zz = eye[2] - c[2];
  let l = Math.hypot(zx, zy, zz) || 1; zx /= l; zy /= l; zz /= l;
  let xx = up[1] * zz - up[2] * zy, xy = up[2] * zx - up[0] * zz, xz = up[0] * zy - up[1] * zx;
  l = Math.hypot(xx, xy, xz) || 1; xx /= l; xy /= l; xz /= l;
  const yx = zy * xz - zz * xy, yy = zz * xx - zx * xz, yz = zx * xy - zy * xx;
  out[0] = xx; out[1] = yx; out[2] = zx; out[3] = 0;
  out[4] = xy; out[5] = yy; out[6] = zy; out[7] = 0;
  out[8] = xz; out[9] = yz; out[10] = zz; out[11] = 0;
  out[12] = -(xx * eye[0] + xy * eye[1] + xz * eye[2]);
  out[13] = -(yx * eye[0] + yy * eye[1] + yz * eye[2]);
  out[14] = -(zx * eye[0] + zy * eye[1] + zz * eye[2]);
  out[15] = 1;
  return out;
}

export function mul(out, a, b) {
  const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3], a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7],
    a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11], a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  for (let i = 0; i < 4; i++) {
    const b0 = b[i * 4], b1 = b[i * 4 + 1], b2 = b[i * 4 + 2], b3 = b[i * 4 + 3];
    out[i * 4] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
    out[i * 4 + 1] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
    out[i * 4 + 2] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
    out[i * 4 + 3] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  }
  return out;
}

export function invert(out, a) {
  const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3], a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7],
    a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11], a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  const b00 = a00 * a11 - a01 * a10, b01 = a00 * a12 - a02 * a10, b02 = a00 * a13 - a03 * a10,
    b03 = a01 * a12 - a02 * a11, b04 = a01 * a13 - a03 * a11, b05 = a02 * a13 - a03 * a12,
    b06 = a20 * a31 - a21 * a30, b07 = a20 * a32 - a22 * a30, b08 = a20 * a33 - a23 * a30,
    b09 = a21 * a32 - a22 * a31, b10 = a21 * a33 - a23 * a31, b11 = a22 * a33 - a23 * a32;
  let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
  if (!det) return null;
  det = 1 / det;
  out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * det;
  out[1] = (a02 * b10 - a01 * b11 - a03 * b09) * det;
  out[2] = (a31 * b05 - a32 * b04 + a33 * b03) * det;
  out[3] = (a22 * b04 - a21 * b05 - a23 * b03) * det;
  out[4] = (a12 * b08 - a10 * b11 - a13 * b07) * det;
  out[5] = (a00 * b11 - a02 * b08 + a03 * b07) * det;
  out[6] = (a32 * b02 - a30 * b05 - a33 * b01) * det;
  out[7] = (a20 * b05 - a22 * b02 + a23 * b01) * det;
  out[8] = (a10 * b10 - a11 * b08 + a13 * b06) * det;
  out[9] = (a01 * b08 - a00 * b10 - a03 * b06) * det;
  out[10] = (a30 * b04 - a31 * b02 + a33 * b00) * det;
  out[11] = (a21 * b02 - a20 * b04 - a23 * b00) * det;
  out[12] = (a11 * b07 - a10 * b09 - a12 * b06) * det;
  out[13] = (a00 * b09 - a01 * b07 + a02 * b06) * det;
  out[14] = (a31 * b01 - a30 * b03 - a32 * b00) * det;
  out[15] = (a20 * b03 - a21 * b01 + a22 * b00) * det;
  return out;
}

// 6 planes (a,b,c,d) with inward normals, from a column-major view-projection (WebGPU z 0..1)
// Refactored to Data-Oriented Design (DOD): zero temporary array allocations per frame.
export function frustumPlanes(out, m) {
  const m0 = m[0], m1 = m[1], m2 = m[2], m3 = m[3];
  const m4 = m[4], m5 = m[5], m6 = m[6], m7 = m[7];
  const m8 = m[8], m9 = m[9], m10 = m[10], m11 = m[11];
  const m12 = m[12], m13 = m[13], m14 = m[14], m15 = m[15];

  let x = m3 + m0, y = m7 + m4, z = m11 + m8, w = m15 + m12;
  let invL = 1.0 / (Math.hypot(x, y, z) || 1.0);
  out[0] = x * invL; out[1] = y * invL; out[2] = z * invL; out[3] = w * invL;

  x = m3 - m0; y = m7 - m4; z = m11 - m8; w = m15 - m12;
  invL = 1.0 / (Math.hypot(x, y, z) || 1.0);
  out[4] = x * invL; out[5] = y * invL; out[6] = z * invL; out[7] = w * invL;

  x = m3 + m1; y = m7 + m5; z = m11 + m9; w = m15 + m13;
  invL = 1.0 / (Math.hypot(x, y, z) || 1.0);
  out[8] = x * invL; out[9] = y * invL; out[10] = z * invL; out[11] = w * invL;

  x = m3 - m1; y = m7 - m5; z = m11 - m9; w = m15 - m13;
  invL = 1.0 / (Math.hypot(x, y, z) || 1.0);
  out[12] = x * invL; out[13] = y * invL; out[14] = z * invL; out[15] = w * invL;

  x = m2; y = m6; z = m10; w = m14;
  invL = 1.0 / (Math.hypot(x, y, z) || 1.0);
  out[16] = x * invL; out[17] = y * invL; out[18] = z * invL; out[19] = w * invL;

  x = m3 - m2; y = m7 - m6; z = m11 - m10; w = m15 - m14;
  invL = 1.0 / (Math.hypot(x, y, z) || 1.0);
  out[20] = x * invL; out[21] = y * invL; out[22] = z * invL; out[23] = w * invL;

  return out;
}

// axis-aligned box (centre, half sizes) against the frustum: exact enough for chunk culling
export function boxInFrustum(pl, x, y, z, hx, hy, hz) {
  for (let i = 0; i < 6; i++) {
    const a = pl[i * 4], b = pl[i * 4 + 1], c = pl[i * 4 + 2];
    if (a * x + b * y + c * z + pl[i * 4 + 3] + Math.abs(a) * hx + Math.abs(b) * hy + Math.abs(c) * hz < 0) return false;
  }
  return true;
}
export function sphereInFrustum(pl, x, y, z, r) {
  for (let i = 0; i < 6; i++) {
    if (pl[i * 4] * x + pl[i * 4 + 1] * y + pl[i * 4 + 2] * z + pl[i * 4 + 3] < -r) return false;
  }
  return true;
}

// ---- 3x4 row-major affine: [r00 r01 r02 tx | r10 r11 r12 ty | r20 r21 r22 tz]
export function m34() { return new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]); }

export function m34Set(o, oo, a) { for (let i = 0; i < 12; i++) o[oo + i] = a[i]; }

// Compose T(pos) * Ry(yaw) * Rx(pitch) * Rz(roll) * S(scale)
export function m34TRS(o, x, y, z, yaw = 0, pitch = 0, roll = 0, s = 1) {
  const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch), cr = Math.cos(roll), sr = Math.sin(roll);
  // R = Ry * Rx * Rz
  const r00 = cy * cr + sy * sp * sr, r01 = -cy * sr + sy * sp * cr, r02 = sy * cp;
  const r10 = cp * sr, r11 = cp * cr, r12 = -sp;
  const r20 = -sy * cr + cy * sp * sr, r21 = sy * sr + cy * sp * cr, r22 = cy * cp;
  o[0] = r00 * s; o[1] = r01 * s; o[2] = r02 * s; o[3] = x;
  o[4] = r10 * s; o[5] = r11 * s; o[6] = r12 * s; o[7] = y;
  o[8] = r20 * s; o[9] = r21 * s; o[10] = r22 * s; o[11] = z;
  return o;
}

// o = a * b (both 3x4 affine)
export function m34Mul(o, a, b) {
  const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3], a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7], a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  const b00 = b[0], b01 = b[1], b02 = b[2], b03 = b[3], b10 = b[4], b11 = b[5], b12 = b[6], b13 = b[7], b20 = b[8], b21 = b[9], b22 = b[10], b23 = b[11];
  o[0] = a00 * b00 + a01 * b10 + a02 * b20; o[1] = a00 * b01 + a01 * b11 + a02 * b21; o[2] = a00 * b02 + a01 * b12 + a02 * b22; o[3] = a00 * b03 + a01 * b13 + a02 * b23 + a03;
  o[4] = a10 * b00 + a11 * b10 + a12 * b20; o[5] = a10 * b01 + a11 * b11 + a12 * b21; o[6] = a10 * b02 + a11 * b12 + a12 * b22; o[7] = a10 * b03 + a11 * b13 + a12 * b23 + a13;
  o[8] = a20 * b00 + a21 * b10 + a22 * b20; o[9] = a20 * b01 + a21 * b11 + a22 * b21; o[10] = a20 * b02 + a21 * b12 + a22 * b22; o[11] = a20 * b03 + a21 * b13 + a22 * b23 + a23;
  return o;
}

const _ptScratch = new Float32Array(3);
export function m34Point(m, x, y, z, out = _ptScratch) {
  out[0] = m[0] * x + m[1] * y + m[2] * z + m[3];
  out[1] = m[4] * x + m[5] * y + m[6] * z + m[7];
  out[2] = m[8] * x + m[9] * y + m[10] * z + m[11];
  return out;
}

// Compose T(pos) * R(align local +Y to (dx,dy,dz)) * S(scale) — right-handed orthonormal basis, zero allocations.
export function m34AlignY(o, px, py, pz, dx, dy, dz, s = 1) {
  const len = Math.hypot(dx, dy, dz);
  let ux = 0, uy = 1, uz = 0;
  if (len > 1e-6) {
    const inv = 1 / len;
    ux = dx * inv; uy = dy * inv; uz = dz * inv;
  }
  // Use world +Y as roll reference unless shaft is nearly vertical, preventing sudden twist flips
  const nearVert = Math.abs(uy) > 0.96;
  const rx = 0, ry = nearVert ? 0 : 1, rz = nearVert ? 1 : 0;
  // xAxis = normalize(u x ref), zAxis = xAxis x u => right-handed det = +1
  let xx = uy * rz - uz * ry;
  let xy = uz * rx - ux * rz;
  let xz = ux * ry - uy * rx;
  const xl = Math.hypot(xx, xy, xz) || 1;
  xx /= xl; xy /= xl; xz /= xl;
  const zx = xy * uz - xz * uy;
  const zy = xz * ux - xx * uz;
  const zz = xx * uy - xy * ux;
  o[0] = xx * s; o[1] = ux * s; o[2] = zx * s; o[3] = px;
  o[4] = xy * s; o[5] = uy * s; o[6] = zy * s; o[7] = py;
  o[8] = xz * s; o[9] = uz * s; o[10] = zz * s; o[11] = pz;
  return o;
}

export const angleLerp = (a, b, t) => {
  let d = ((b - a + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
  return a + d * t;
};
