//! The part-based character rig (player.js makeRig / writeRig): torso, head, two upper arms, two forearms with
//! hands, two legs, posed by joint angles and written as GPU instances (3x4 matrix, model, mask, phase, extra).

/// model indices of the rig parts (into the pack's models/models.json)
#[derive(Clone, Copy)]
pub struct RigModels {
    pub head: u32,
    pub torso: u32,
    pub uarm: u32,
    pub uarm_l: u32,
    pub farm: u32,
    pub farm_l: u32,
    pub leg: u32,
}

impl RigModels {
    pub fn find(prefix: &str, names: &[&str]) -> Option<Self> {
        let f = |s: &str| names.iter().position(|n| *n == format!("{prefix}_{s}")).map(|i| i as u32);
        Some(RigModels { head: f("head")?, torso: f("torso")?, uarm: f("uarm")?, uarm_l: f("uarmL")?, farm: f("farm")?, farm_l: f("farmL")?, leg: f("leg")? })
    }
}

pub type M34 = [f32; 12];

/// math.js m34TRS: R = Ry * Rx * Rz, scaled, translated
pub fn m34_trs(x: f32, y: f32, z: f32, yaw: f32, pitch: f32, roll: f32, s: f32) -> M34 {
    let (cy, sy, cp, sp, cr, sr) = (yaw.cos(), yaw.sin(), pitch.cos(), pitch.sin(), roll.cos(), roll.sin());
    [
        (cy * cr + sy * sp * sr) * s, (-cy * sr + sy * sp * cr) * s, sy * cp * s, x,
        cp * sr * s, cp * cr * s, -sp * s, y,
        (-sy * cr + cy * sp * sr) * s, (sy * sr + cy * sp * cr) * s, cy * cp * s, z,
    ]
}

/// math.js m34Mul: a * b (affine 3x4)
pub fn m34_mul(a: &M34, b: &M34) -> M34 {
    let mut o = [0.0; 12];
    for r in 0..3 {
        for c in 0..4 {
            o[r * 4 + c] = a[r * 4] * b[c] + a[r * 4 + 1] * b[4 + c] + a[r * 4 + 2] * b[8 + c] + if c == 3 { a[r * 4 + 3] } else { 0.0 };
        }
    }
    o
}

fn inst(out: &mut Vec<u32>, m: &M34, model: u32, mask: u32) {
    out.extend(m.iter().map(|f| f.to_bits()));
    out.extend_from_slice(&[model, mask, 0f32.to_bits(), 0f32.to_bits()]);
}

/// writeRig for the idle and walk poses: appends 8 instances (16 words each) to `out`
#[allow(clippy::too_many_arguments)]
pub fn write_rig(out: &mut Vec<u32>, m: &RigModels, pos: [f32; 3], yaw: f32, walking: bool, phase: f32, speed: f32, t: f32) {
    let (mut leg_l, mut leg_r, mut elb_l, mut elb_r) = (0.0f32, 0.0f32, -0.2f32, -0.2f32);
    let (arm_l, arm_r, bob): (f32, f32, f32);
    let (mut arm_roll_l, mut arm_roll_r, mut head_p, mut head_y, mut torso_p, mut leg_roll_l, mut leg_roll_r) = (0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32);
    if walking {
        let a = phase.sin() * (0.25 + speed * 0.13).min(0.65);
        leg_l = a;
        leg_r = -a;
        arm_l = -a * 0.8;
        arm_r = a * 0.8;
        bob = phase.cos().abs() * 0.035;
        torso_p = 0.04 + speed * 0.012;
        elb_l = -0.22 + arm_l.min(0.0) * 0.7;
        elb_r = -0.22 + arm_r.min(0.0) * 0.7;
    } else {
        bob = (t * 1.6).sin() * 0.006;
        arm_l = (t * 1.1).sin() * 0.03;
        arm_r = -arm_l;
        head_y = (t * 0.4).sin() * 0.25;
        head_p = (t * 0.33).sin() * 0.05;
        leg_roll_l = 0.035;
        leg_roll_r = -0.035;
        arm_roll_l = 0.07;
        arm_roll_r = -0.07;
    }
    let root = m34_trs(pos[0], pos[1] + bob, pos[2], yaw, 0.0, 0.0, 1.0);
    let (hip_y, sh_y, neck_y, hip_x, sh_x) = (0.78, 1.27, 1.31, 0.112, 0.29);
    let mask = 3;
    let part = |out: &mut Vec<u32>, model: u32, jx: f32, jy: f32, jz: f32, pitch: f32, yaw: f32, roll: f32| {
        inst(out, &m34_mul(&root, &m34_trs(jx, jy, jz, yaw, pitch, roll, 1.0)), model, mask);
    };
    part(out, m.torso, 0.0, hip_y - 0.02, 0.0, torso_p, 0.0, 0.0);
    part(out, m.head, 0.0, neck_y - torso_p * 0.1, torso_p * 0.25, head_p, head_y, 0.0);
    let arm = |out: &mut Vec<u32>, um: u32, fm: u32, jx: f32, pitch: f32, roll: f32, elbow: f32| {
        let upper = m34_mul(&root, &m34_trs(jx, sh_y, torso_p * 0.15, 0.0, pitch, roll, 1.0));
        inst(out, &upper, um, mask);
        inst(out, &m34_mul(&upper, &m34_trs(0.0, -0.17, 0.0, 0.0, elbow, 0.0, 1.0)), fm, mask);
    };
    arm(out, m.uarm_l, m.farm_l, sh_x, arm_l, arm_roll_l + 0.05, elb_l);
    arm(out, m.uarm, m.farm, -sh_x, arm_r, arm_roll_r - 0.05, elb_r);
    part(out, m.leg, hip_x, hip_y, 0.0, leg_l, 0.0, leg_roll_l);
    part(out, m.leg, -hip_x, hip_y, 0.0, leg_r, 0.0, leg_roll_r);
}
