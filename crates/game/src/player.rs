//! Third-person controller and over-the-shoulder camera: src/game/player.js (Player.update, collides, updateCamera).
use crate::voxels::{Voxels, F_LEAF, F_SOLID};

const HW: f32 = 0.27;
const HEIGHT: f32 = 1.72;

#[derive(Default, Clone, Copy)]
pub struct Input {
    /// joystick: x right, y forward, length up to 1
    pub mv: [f32; 2],
    /// look drag in pixels this frame
    pub look: [f32; 2],
    pub run: bool,
}

pub struct Player {
    pub pos: [f32; 3],
    pub vel_y: f32,
    pub yaw: f32,
    pub cam_yaw: f32,
    pub cam_pitch: f32,
    pub cam_dist: f32,
    cam_dist_cur: f32,
    pub on_ground: bool,
    pub phase: f32,
    pub speed: f32,
    pub walking: bool,
    pub vis_y: f32,
    pub cam_pos: [f32; 3],
    pub cam_target: [f32; 3],
    pub indoor: bool,
    bounds: [f32; 4],
    shoulder_cur: f32,
    cam_hold: f32,
    cam_tight: f32,
    look_idle: f32,
    tgt: [f32; 3],
    dir: [f32; 3],
}

fn angle_lerp(a: f32, b: f32, t: f32) -> f32 {
    let tau = std::f32::consts::TAU;
    let d = ((b - a + std::f32::consts::PI).rem_euclid(tau)) - std::f32::consts::PI;
    a + d * t
}

impl Player {
    pub fn new(w: &Voxels) -> Self {
        Player {
            pos: [0.0; 3],
            vel_y: 0.0,
            yaw: std::f32::consts::PI,
            cam_yaw: std::f32::consts::PI,
            cam_pitch: 0.28,
            cam_dist: 4.2,
            cam_dist_cur: 4.2,
            on_ground: false,
            phase: 0.0,
            speed: 0.0,
            walking: false,
            vis_y: 0.0,
            cam_pos: [0.0; 3],
            cam_target: [0.0; 3],
            indoor: false,
            bounds: [2.0, w.wx as f32 * w.vs - 2.0, 2.0, w.wz as f32 * w.vs - 2.0],
            shoulder_cur: 0.66,
            cam_hold: 0.0,
            cam_tight: 0.0,
            look_idle: 0.0,
            tgt: [0.0; 3],
            dir: [0.0; 3],
        }
    }

    pub fn place(&mut self, x: f32, y: f32, z: f32, yaw: f32) {
        self.pos = [x, y, z];
        self.vel_y = 0.0;
        self.yaw = yaw;
        self.cam_yaw = yaw;
        self.cam_dist_cur = self.cam_dist;
        self.vis_y = y;
    }

    /// main.js placePlayer: the nearest height in the column where the whole body fits, searching down from `hint`
    pub fn spawn(&mut self, w: &Voxels, x: f32, z: f32, hint: f32, yaw: f32) {
        let top = ((hint + 1.0) / w.vs) as i32;
        let mut y = hint;
        for vy in (1..=top.min(w.wy - 1)).rev() {
            let yy = vy as f32 * w.vs;
            if w.solid_m(x, yy - 0.05, z) && !self.collides(x, yy, z, w) {
                y = yy;
                break;
            }
        }
        self.place(x, y + 0.02, z, yaw);
    }

    pub fn collides(&self, x: f32, y: f32, z: f32, w: &Voxels) -> bool {
        let (vs, eps) = (w.vs, 1e-5);
        let x0 = ((x - HW + eps) / vs).floor() as i32;
        let x1 = ((x + HW - eps) / vs).floor() as i32;
        let z0 = ((z - HW + eps) / vs).floor() as i32;
        let z1 = ((z + HW - eps) / vs).floor() as i32;
        let y0 = ((y + 0.01 + eps) / vs).floor() as i32;
        let y1 = ((y + HEIGHT - eps) / vs).floor() as i32;
        for vy in y0..=y1 {
            for vz in z0..=z1 {
                for vx in x0..=x1 {
                    if w.solid(vx, vy, vz) {
                        return true;
                    }
                }
            }
        }
        false
    }

    fn try_move(&mut self, dx: f32, dz: f32, w: &Voxels) -> bool {
        let p = self.pos;
        let (nx, nz) = (p[0] + dx, p[2] + dz);
        if !self.collides(nx, p[1], nz, w) {
            self.pos[0] = nx;
            self.pos[2] = nz;
            return true;
        }
        if self.on_ground {
            for k in 1..=4 {
                let sy = k as f32 * w.vs;
                if !self.collides(nx, p[1] + sy, nz, w) && !self.collides(p[0], p[1] + sy, p[2], w) {
                    self.pos = [nx, p[1] + sy, nz];
                    self.vel_y = 0.0;
                    return true;
                }
            }
        }
        false
    }

    pub fn update(&mut self, dt: f32, inp: &Input, w: &Voxels) {
        let (mut mx, mut mz, mut mag) = (0.0f32, 0.0f32, inp.mv[0].hypot(inp.mv[1]).min(1.0));
        if mag > 0.08 {
            // camera-relative: camYaw is the direction the camera looks
            let (fx, fz) = (self.cam_yaw.sin(), self.cam_yaw.cos());
            let (rx, rz) = (-fz, fx);
            mx = fx * inp.mv[1] + rx * inp.mv[0];
            mz = fz * inp.mv[1] + rz * inp.mv[0];
            let l = mx.hypot(mz).max(1e-6);
            mx /= l;
            mz /= l;
        } else {
            mag = 0.0;
        }
        let sdt = dt.clamp(0.001, 0.05);
        let max_speed = if inp.run { 3.8 } else { 2.75 };
        let target = mag * max_speed;
        self.speed += (target - self.speed) * (sdt * 14.0).min(1.0);
        self.speed = self.speed.clamp(0.0, max_speed);
        if mag > 0.0 {
            self.yaw = angle_lerp(self.yaw, mx.atan2(mz), (sdt * 12.0).min(1.0));
        }
        let (vx, vz) = if mag > 0.0 { (mx * self.speed, mz * self.speed) } else { (self.yaw.sin() * self.speed * 0.9, self.yaw.cos() * self.speed * 0.9) };
        let p = self.pos;
        let was_grounded = self.on_ground || self.collides(p[0], p[1] - 0.05, p[2], w);
        self.on_ground = was_grounded || (self.vel_y <= 0.0 && self.collides(p[0], p[1] - 2.0 * w.vs - 0.02, p[2], w));
        let (mut ddx, mut ddz) = (vx * sdt, vz * sdt);
        let len = ddx.hypot(ddz);
        let max_step = 0.11f32.min(max_speed * sdt + 0.005);
        if len > max_step && len > 1e-6 {
            ddx *= max_step / len;
            ddz *= max_step / len;
        }
        if !self.try_move(ddx, ddz, w) {
            self.try_move(ddx, 0.0, w);
            self.try_move(0.0, ddz, w);
        }
        self.pos[0] = self.pos[0].clamp(self.bounds[0], self.bounds[1]);
        self.pos[2] = self.pos[2].clamp(self.bounds[2], self.bounds[3]);
        // vertical
        self.vel_y = (self.vel_y - 22.0 * sdt).max(-18.0);
        let p = self.pos;
        let ny = p[1] + self.vel_y * sdt;
        if self.collides(p[0], ny, p[2], w) {
            if self.vel_y < 0.0 {
                self.pos[1] = (ny / w.vs).ceil() * w.vs;
                self.on_ground = true;
            }
            self.vel_y = 0.0;
        } else if was_grounded && self.vel_y <= 0.0 && self.collides(p[0], p[1] - 2.0 * w.vs - 0.02, p[2], w) {
            // snap down 1-2 voxel steps so the hero stays grounded on furrows and slopes
            for k in 1..=2 {
                let sy = ((p[1] - k as f32 * w.vs) / w.vs).round() * w.vs;
                if !self.collides(p[0], sy, p[2], w) && self.collides(p[0], sy - 0.04, p[2], w) {
                    self.pos[1] = sy;
                    self.vel_y = 0.0;
                    self.on_ground = true;
                    break;
                }
            }
        } else {
            self.pos[1] = ny;
            self.on_ground = false;
        }
        self.vis_y += (self.pos[1] - self.vis_y) * (dt * 14.0).min(1.0);
        if (self.pos[1] - self.vis_y).abs() > 2.0 {
            self.vis_y = self.pos[1];
        }
        self.walking = self.speed > 0.25;
        self.phase += dt * (2.2 + self.speed * 2.6) * if self.walking { 1.0 } else { 0.0 };
    }

    /// player.js _solid: solid and not foliage (the camera passes through leaves)
    fn cam_solid(w: &Voxels, x: f32, y: f32, z: f32) -> bool {
        let m = w.mat((x / w.vs).floor() as i32, (y / w.vs).floor() as i32, (z / w.vs).floor() as i32);
        let fl = w.flags(m);
        fl & F_SOLID != 0 && fl & F_LEAF == 0
    }

    /// first solid voxel (not foliage) on the thin line from the pivot along the boom (player.js _boomHit)
    fn boom_hit(&self, w: &Voxels, max_t: f32) -> Option<f32> {
        let (tg, d) = (self.tgt, self.dir);
        let mut t = 0.1;
        while t <= max_t {
            if Self::cam_solid(w, tg[0] + d[0] * t, tg[1] + d[1] * t, tg[2] + d[2] * t) {
                return Some(t);
            }
            t += 0.04;
        }
        None
    }

    /// Over-the-shoulder camera (player.js updateCamera): the pivot slides from the right shoulder to the centre when
    /// a wall is beside the hero, only the thin line of sight shortens the boom, walls beside the camera push it
    /// sideways, the boom grows back after a short hold, and in tight spaces it swings behind the walking hero.
    pub fn update_camera(&mut self, dt: f32, inp: &Input, w: &Voxels, portrait: bool) {
        let tau = std::f32::consts::TAU;
        let looked = inp.look[0].abs() + inp.look[1].abs() > 0.5;
        self.cam_yaw = (self.cam_yaw - inp.look[0] * 0.0042).rem_euclid(tau);
        self.cam_pitch = (self.cam_pitch + inp.look[1] * 0.0036).clamp(-0.55, 1.25);
        self.look_idle = if looked { 0.0 } else { self.look_idle + dt };
        let p = self.pos;
        self.indoor = [2.4, 3.4, 3.8, 4.2].iter().any(|&h| Self::cam_solid(w, p[0], p[1] + h, p[2]));
        if self.cam_tight > 0.3 && self.speed > 0.6 && self.look_idle > 1.0 {
            let d = (self.yaw - self.cam_yaw).sin().atan2((self.yaw - self.cam_yaw).cos());
            self.cam_yaw += d * (dt * 1.6 * self.cam_tight).min(1.0);
        }
        let (rx, rz) = (-self.cam_yaw.cos(), self.cam_yaw.sin());
        let mut shoulder_want: f32 = if portrait { 0.72 } else { 0.66 };
        let base_y = self.vis_y + 1.38;
        let mut s = 0.08;
        while s <= shoulder_want + 0.2 {
            if Self::cam_solid(w, p[0] + rx * s, base_y, p[2] + rz * s) {
                shoulder_want = (s - 0.24).max(0.0);
                break;
            }
            s += 0.06;
        }
        let k = if shoulder_want < self.shoulder_cur { 14.0 } else { 4.0 };
        self.shoulder_cur += (shoulder_want - self.shoulder_cur) * (dt * k).min(1.0);
        self.tgt = [p[0] + rx * self.shoulder_cur, base_y, p[2] + rz * self.shoulder_cur];
        let (cp, sp) = (self.cam_pitch.cos(), self.cam_pitch.sin());
        self.dir = [-self.cam_yaw.sin() * cp, sp, -self.cam_yaw.cos() * cp];
        let want = if self.indoor { 2.4 } else { self.cam_dist } * if portrait { 1.08 } else { 1.0 };
        let hit = self.boom_hit(w, want + 0.2);
        let d = hit.map_or(want, |h| (h - 0.18).min(want).max(0.45));
        self.cam_tight = if hit.is_some() { (1.0 - d / want).clamp(0.0, 1.0) } else { 0.0 };
        if d < self.cam_dist_cur {
            self.cam_hold = 0.35;
            self.cam_dist_cur += (d - self.cam_dist_cur) * (dt * 18.0).min(1.0);
        } else {
            self.cam_hold = (self.cam_hold - dt).max(0.0);
            if self.cam_hold <= 0.0 {
                self.cam_dist_cur += (d - self.cam_dist_cur) * (dt * 3.5).min(1.0);
            }
        }
        let dd = self.cam_dist_cur;
        let lift = 0.10 * (dd / 2.2).min(1.0) + 0.18 * (1.0 - dd / 1.2).max(0.0);
        let (tg, dr) = (self.tgt, self.dir);
        let (mut cx, mut cy, mut cz) = (tg[0] + dr[0] * dd, tg[1] + dr[1] * dd + lift, tg[2] + dr[2] * dd);
        let r = 0.2;
        let sol = |x: f32, y: f32, z: f32| Self::cam_solid(w, x, y, z);
        if sol(cx + rx * r, cy, cz + rz * r) && !sol(cx - rx * r, cy, cz - rz * r) {
            cx -= rx * r * 0.7;
            cz -= rz * r * 0.7;
        } else if sol(cx - rx * r, cy, cz - rz * r) && !sol(cx + rx * r, cy, cz + rz * r) {
            cx += rx * r * 0.7;
            cz += rz * r * 0.7;
        }
        if sol(cx, cy + r, cz) {
            cy -= r * 0.6;
        }
        self.cam_target = tg;
        self.cam_pos = [cx, cy, cz];
    }
}
