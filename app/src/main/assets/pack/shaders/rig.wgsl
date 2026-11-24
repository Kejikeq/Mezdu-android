

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

@group(0) @binding(0) var<storage, read> poses: array<RigPose>;
@group(0) @binding(1) var<storage, read_write> insts: array<Inst>;

fn m34TRS(x: f32, y: f32, z: f32, yaw: f32, pitch: f32, roll: f32, s: f32) -> array<vec4f, 3> {
  let cy = cos(yaw); let sy = sin(yaw);
  let cp = cos(pitch); let sp = sin(pitch);
  let cr = cos(roll); let sr = sin(roll);
  let r00 = cy * cr + sy * sp * sr;
  let r01 = -cy * sr + sy * sp * cr;
  let r02 = sy * cp;
  let r10 = cp * sr;
  let r11 = cp * cr;
  let r12 = -sp;
  let r20 = -sy * cr + cy * sp * sr;
  let r21 = sy * sr + cy * sp * cr;
  let r22 = cy * cp;
  var out: array<vec4f, 3>;
  out[0] = vec4f(r00 * s, r01 * s, r02 * s, x);
  out[1] = vec4f(r10 * s, r11 * s, r12 * s, y);
  out[2] = vec4f(r20 * s, r21 * s, r22 * s, z);
  return out;
}

fn m34Mul(a: array<vec4f, 3>, b: array<vec4f, 3>) -> array<vec4f, 3> {
  var out: array<vec4f, 3>;
  for (var i = 0u; i < 3u; i++) {
    let ai = a[i];
    out[i] = vec4f(
      ai.x * b[0].x + ai.y * b[1].x + ai.z * b[2].x,
      ai.x * b[0].y + ai.y * b[1].y + ai.z * b[2].y,
      ai.x * b[0].z + ai.y * b[1].z + ai.z * b[2].z,
      ai.x * b[0].w + ai.y * b[1].w + ai.z * b[2].w + ai.w
    );
  }
  return out;
}

fn writeInst(slot: u32, m: array<vec4f, 3>, model: u32, mask: u32) {
  insts[slot].m0 = m[0];
  insts[slot].m1 = m[1];
  insts[slot].m2 = m[2];
  insts[slot].model = model;
  insts[slot].mask = select(mask | 32u, 0u, mask == 0u); // 32: a moving object (TAA trusts its history less)
  insts[slot].phase = 0.0;
  insts[slot].extra = 0.0;
}

// 11-bone bind positions matching toyBodyUnified (vs = 0.02, pivot [24, 0, 18]):
// 0:Pelvis(0,0.80,0), 1:Torso(0,0.96,0), 2:Head(0,1.40,0),
// 3:ArmL(0.175,1.29,0), 4:ForearmL(0.20,1.01,-0.005),
// 5:ArmR(-0.175,1.29,0), 6:ForearmR(-0.20,1.01,-0.005),
// 7:ThighL(0.096,0.78,0), 8:ShinL(0.096,0.45,0.005),
// 9:ThighR(-0.096,0.78,0), 10:ShinR(-0.096,0.45,0.005)
fn m34TNeg(bx: f32, by: f32, bz: f32) -> array<vec4f, 3> {
  var out: array<vec4f, 3>;
  out[0] = vec4f(1.0, 0.0, 0.0, -bx);
  out[1] = vec4f(0.0, 1.0, 0.0, -by);
  out[2] = vec4f(0.0, 0.0, 1.0, -bz);
  return out;
}

@compute @workgroup_size(1)
fn rig(@builtin(global_invocation_id) gid: vec3u) {
  let rigIdx = gid.x;
  let pose = poses[rigIdx];
  let slot = pose.slot;
  if (pose.mask == 0u || pose.pos.w <= 0.001) {
    for (var i = 0u; i < 13u; i = i + 1u) {
      writeInst(slot + i, m34TRS(0.0, -1000.0, 0.0, 0.0, 0.0, 0.0, 0.0), 0u, 0u);
    }
    return;
  }
  let P = pose.poseId;
  let ph = pose.phase;
  let t = pose.time;

  var rootRoll = 0.0; var rootY = 0.0; var rootPitch = 0.0;
  var legL = 0.0; var legR = 0.0; var kneeL = 0.05; var kneeR = 0.05;
  var armL = 0.0; var armR = 0.0;
  var elbL = -0.2; var elbR = -0.2; var armRollL = 0.0; var armRollR = 0.0;
  var headP = 0.0; var headY = 0.0; var headRoll = 0.0;
  var torsoP = 0.0; var torsoYaw = 0.0; var torsoRoll = 0.0;
  var pelvisX = 0.0; var pelvisYaw = 0.0; var pelvisRoll = 0.0;
  var bob = 0.0; var legRollL = 0.0; var legRollR = 0.0;

  if (P == 1u) { // walk -> jog -> sprint biomechanical blend
    let moveT = clamp(pose.speed / 2.2, 0.15, 1.0);
    let runT = clamp((pose.speed - 2.35) / 1.45, 0.0, 1.0);
    let sPh = sin(ph); let cPh = cos(ph);
    let strideAmp = min(0.76, 0.24 + pose.speed * 0.135 + runT * 0.08);
    legL = sPh * strideAmp + runT * 0.05;
    legR = -sPh * strideAmp + runT * 0.05;
    let swingL = max(0.0, sin(ph - 0.78));
    let swingR = max(0.0, -sin(ph - 0.78));
    let loadL = max(0.0, -sin(ph + 0.88));
    let loadR = max(0.0, sin(ph + 0.88));
    kneeL = max(0.05, -sPh * (0.28 + 0.14 * runT) + swingL * (0.58 + 0.44 * runT) + loadL * (0.14 + 0.08 * runT));
    kneeR = max(0.05, sPh * (0.28 + 0.14 * runT) + swingR * (0.58 + 0.44 * runT) + loadR * (0.14 + 0.08 * runT));
    legRollL = 0.018 + max(0.0, -cPh) * 0.018 * moveT;
    legRollR = -0.018 - max(0.0, cPh) * 0.018 * moveT;
    let vault = pow(abs(cPh), 1.3);
    bob = vault * (0.028 * moveT + 0.020 * runT) - (0.010 + 0.018 * runT);
    pelvisX = cPh * (0.018 * moveT * (1.0 - 0.45 * runT));
    pelvisYaw = sPh * (0.115 * moveT + 0.075 * runT);
    pelvisRoll = cPh * (0.046 * moveT + 0.026 * runT);
    torsoYaw = -pelvisYaw * (1.18 + 0.16 * runT);
    torsoRoll = -pelvisRoll * 0.84;
    torsoP = 0.045 + pose.speed * 0.016 + runT * 0.085;
    let armScale = 0.72 + 0.34 * runT;
    armL = -sPh * strideAmp * armScale - runT * 0.08;
    armR = sPh * strideAmp * armScale - runT * 0.08;
    elbL = (-0.24 - 0.56 * runT) + min(0.0, armL) * (0.68 + 0.25 * runT);
    elbR = (-0.24 - 0.56 * runT) + min(0.0, armR) * (0.68 + 0.25 * runT);
    armRollL = 0.030 + max(0.0, -armL) * 0.09 + 0.04 * runT;
    armRollR = -0.030 - max(0.0, -armR) * 0.09 - 0.04 * runT;
    headY = -torsoYaw * 0.52;
    headP = -torsoP * 0.35 + sin(ph * 2.0 - 0.4) * (0.016 + 0.014 * runT);
    headRoll = -torsoRoll * 0.55;
    if (pose.holdingTool > 0u) { armR = -0.35 + armR * 0.25; elbR = -0.55; armRollR = -0.12; }
  } else if (P == 0u) { // idle: natural contrapposto weight shift, relaxed arms, organic breathing
    let shift = sin(t * 0.68);
    let breath = sin(t * 1.58);
    let breath2 = sin(t * 1.58 - 0.55);
    rootY = -0.016;
    bob = breath * 0.0045;
    pelvisX = shift * 0.014;
    pelvisYaw = -0.045 + shift * 0.032;
    pelvisRoll = 0.022 + shift * 0.020;
    rootRoll = 0.006 + shift * 0.008;
    torsoYaw = 0.040 - shift * 0.028;
    torsoRoll = -pelvisRoll * 0.78;
    torsoP = 0.028 + breath * 0.011;
    legL = 0.072 - shift * 0.030; legR = -0.062 - shift * 0.026;
    kneeL = 0.115 - shift * 0.045; kneeR = 0.065 + shift * 0.045;
    legRollL = 0.032 + shift * 0.010; legRollR = -0.028 + shift * 0.010;
    armL = 0.055 + breath2 * 0.024 + shift * 0.016;
    armR = -0.072 - breath2 * 0.020 + shift * 0.014;
    elbL = -0.32 - breath2 * 0.035; elbR = -0.25 + breath2 * 0.025;
    armRollL = 0.042 + breath * 0.012; armRollR = -0.038 - breath * 0.012;
    headY = sin(t * 0.42) * 0.14 + sin(t * 0.19) * 0.07 - torsoYaw * 0.45;
    headP = 0.018 + sin(t * 0.34) * 0.035 - breath * 0.008;
    headRoll = -torsoRoll * 0.5 + sin(t * 0.29) * 0.028;
    if (pose.holdingTool > 0u) { armR = -0.35 + armR * 0.5; elbR = -0.55; armRollR = -0.12; }
  } else if (P == 2u) { // sit
    rootY = -0.38; legL = -0.68; legR = -0.68; kneeL = 0.68; kneeR = 0.68; armL = -0.3; armR = -0.3; elbL = -0.35; elbR = -0.35; headP = 0.12; headY = sin(t * 0.3) * 0.2;
    if (pose.seatId == 1u) { // ground
      rootY = -0.7; legL = -1.5; legR = -1.5; kneeL = 0.08; kneeR = 0.08; armL = 0.35; armR = 0.35; elbL = -0.04; elbR = -0.04; armRollL = 0.15; armRollR = -0.15; torsoP = -0.12; headP = 0.12;
    } else if (pose.seatId == 2u) { // bench
      rootY = -0.38; legL = -0.68; legR = -0.68; kneeL = 0.68; kneeR = 0.68; armL = -0.42; armR = -0.42; elbL = -0.45; elbR = -0.45; torsoP = -0.04; headP = 0.1;
    } else if (pose.seatId == 3u) { // sofa
      rootY = -0.42; legL = -0.72; legR = -0.72; kneeL = 0.72; kneeR = 0.72; armL = -0.35; armR = -0.35; elbL = -0.48; elbR = -0.48; armRollL = 0.12; armRollR = -0.12; torsoP = -0.09; headP = 0.08; headY = sin(t * 0.28) * 0.18;
    }
  } else if (P == 3u) { // kneel
    rootY = -0.32; legL = -0.45; legR = 0.35; kneeL = 0.85; kneeR = 1.05; torsoP = 0.14; armL = -0.35; armR = -0.35; elbL = -0.25; elbR = -0.25; headP = 0.22;
  } else if (P == 4u) { // lie
    rootPitch = -1.5708; rootY = 0.18; armL = 0.1; armR = 0.1; elbL = -0.05; elbR = -0.05; headY = 0.4;
  } else if (P == 5u) { // wash_ashore
    rootPitch = -1.5708 + 0.04;
    rootY = 0.08 + sin(t * 1.4) * 0.008;
    armL = -0.18; armR = 0.24; elbL = -0.32; elbR = -0.45; armRollL = 0.18; armRollR = -0.22;
    headY = 0.22 + sin(t * 0.7) * 0.03; headP = 0.08;
    legL = 0.12; legR = -0.08; kneeL = 0.15; kneeR = 0.05; legRollL = 0.06; legRollR = -0.06;
  } else if (P == 6u) { // anxious
    armL = 0.58 + sin(t * 9.0) * 0.03; armR = armL; elbL = 0.0; elbR = 0.0; armRollL = -2.93; armRollR = 2.93; headP = 0.32 + sin(t * 9.0) * 0.05; torsoP = 0.18;
    headY = sin(t * 13.0) * 0.08; bob = sin(t * 17.0) * 0.01;
  } else if (P == 7u) { // reach
    armR = -1.45 * pose.reach; elbR = 0.0; armL = sin(t) * 0.03; headP = -0.05;
  } else if (P == 8u) { // dig
    let phase = fract((t * 4.0) / 6.2831853);
    if (phase < 0.45) {
      let stroke = sin((phase / 0.45) * 3.14159265);
      torsoP = 0.24 + stroke * 0.20;
      headP = 0.30 + stroke * 0.12;
      armR = -0.50 - stroke * 0.26; elbR = -0.40 - stroke * 0.14; armRollR = -0.52;
      armL = -0.44 - stroke * 0.24; elbL = -0.58 - stroke * 0.14; armRollL = 0.52;
      legL = 0.18; legR = -0.55 + stroke * 0.35; kneeL = 0.22; kneeR = 0.35;
      rootY = -0.05 - stroke * 0.05;
    } else if (phase < 0.78) {
      let lift = sin(((phase - 0.45) / 0.33) * 3.14159265);
      torsoP = 0.32 - lift * 0.22;
      headP = 0.20;
      armR = -0.68 + lift * 0.22; elbR = -0.42 - lift * 0.25; armRollR = -0.48;
      armL = -0.52 + lift * 0.18; elbL = -0.68 - lift * 0.20; armRollL = 0.48;
      legL = 0.22; legR = -0.22; kneeL = 0.24; kneeR = 0.24;
      rootY = -0.02 + lift * 0.03;
    } else {
      torsoP = 0.22; headP = 0.25;
      armR = -0.48; elbR = -0.38; armRollR = -0.50;
      armL = -0.42; elbL = -0.56; armRollL = 0.50;
      legL = 0.18; legR = -0.28; kneeL = 0.20; kneeR = 0.25;
      rootY = -0.03;
    }
  } else if (P == 9u) { // getup_kneel
    rootY = -0.44 + sin(t * 1.2) * 0.02;
    legL = -0.85; legR = -0.85; kneeL = 1.25; kneeR = 1.25; legRollL = 0.12; legRollR = -0.12;
    torsoP = 0.38; headP = 0.42; headY = sin(t * 1.5) * 0.12;
    armL = -0.58; armR = -0.58; elbL = -0.45; elbR = -0.45; armRollL = 0.18; armRollR = -0.18;
  } else if (P == 10u) { // walk_head
    let a = sin(ph) * min(0.4, 0.15 + pose.speed * 0.12);
    legL = a; legR = -a;
    kneeL = max(0.04, -a * 0.4 + max(0.0, sin(ph - 0.6)) * 0.38);
    kneeR = max(0.04, a * 0.4 + max(0.0, -sin(ph - 0.6)) * 0.38);
    armL = -a * 0.6; armR = 0.58; elbR = 0.0; armRollR = 2.93;
    headP = 0.28 + sin(t * 6.0) * 0.04; headY = sin(t * 2.3) * 0.15; torsoP = 0.16;
    bob = abs(cos(ph)) * 0.02; rootRoll = sin(t * 2.1) * 0.06 * pose.headache;
  } else if (P == 11u) { // getup_stand
    rootY = -0.15 + sin(t * 1.4) * 0.02;
    torsoP = 0.18; headP = 0.22; rootRoll = sin(t * 2.0) * 0.08;
    armR = 0.55; elbR = 0.0; armRollR = 2.93;
    armL = -0.25; elbL = -0.2; armRollL = 0.1;
    legL = 0.1; legR = -0.1; kneeL = 0.15; kneeR = 0.2;
  }

  let s = pose.pos.w;
  let tmpRoot = m34TRS(pose.pos.x, pose.pos.y + rootY + bob, pose.pos.z, pose.yaw, rootPitch, rootRoll, s);

  // Slot 0: Unified skinned mesh instance (keep extra = 1.0 so masked/hair passes never dither-discard characters)
  let walkActive = (P == 1u || P == 10u);
  let camPhase = select(t * 1.45, ph, walkActive);
  let camSwing = select(select(0.08, 0.04, P != 0u), min(1.15, 0.30 + pose.speed * 0.28), walkActive);
  writeInst(slot + 0u, tmpRoot, pose.models2.w, pose.mask);
  insts[slot + 0u].phase = 0.0;
  insts[slot + 0u].extra = 1.0;

  // Hierarchical local bones (relative to bind joints)
  let local0 = m34TRS(pelvisX, 0.80, 0.0, pelvisYaw, 0.0, pelvisRoll, 1.0);
  let local1 = m34Mul(m34TRS(pelvisX, 0.80, 0.0, torsoYaw, torsoP, torsoRoll, 1.0), m34TRS(0.0, 0.16, 0.0, 0.0, 0.0, 0.0, 1.0));
  let local2 = m34Mul(local1, m34TRS(0.0, 0.44 - torsoP * 0.04, torsoP * 0.18, headY, headP, headRoll, 1.0));

  let local3 = m34Mul(local1, m34TRS(0.175, 0.33, 0.0, 0.0, armL, armRollL + 0.035, 1.0));
  let local4 = m34Mul(local3, m34TRS(0.025, -0.28, -0.005, 0.0, elbL, 0.0, 1.0));
  let local5 = m34Mul(local1, m34TRS(-0.175, 0.33, 0.0, 0.0, armR, armRollR - 0.035, 1.0));
  let local6 = m34Mul(local5, m34TRS(-0.025, -0.28, -0.005, 0.0, elbR, 0.0, 1.0));

  let local7 = m34Mul(local0, m34TRS(0.096, -0.02, 0.0, 0.0, legL, legRollL, 1.0));
  let local8 = m34Mul(local7, m34TRS(0.0, -0.33, 0.005, 0.0, kneeL, 0.0, 1.0));
  let local9 = m34Mul(local0, m34TRS(-0.096, -0.02, 0.0, 0.0, legR, legRollR, 1.0));
  let local10 = m34Mul(local9, m34TRS(0.0, -0.33, 0.005, 0.0, kneeR, 0.0, 1.0));

  // Slots 1..11: SkinMat[b] = tmpRoot * Local[b] * T(-BindPos[b]) (mask = 0 so cull ignores them)
  writeInst(slot + 1u, m34Mul(tmpRoot, m34Mul(local0, m34TNeg(0.0, 0.80, 0.0))), 0u, 0u);
  writeInst(slot + 2u, m34Mul(tmpRoot, m34Mul(local1, m34TNeg(0.0, 0.96, 0.0))), 0u, 0u);
  writeInst(slot + 3u, m34Mul(tmpRoot, m34Mul(local2, m34TNeg(0.0, 1.40, 0.0))), 0u, 0u);
  insts[slot + 3u].phase = camPhase;
  insts[slot + 3u].extra = camSwing;
  writeInst(slot + 4u, m34Mul(tmpRoot, m34Mul(local3, m34TNeg(0.175, 1.29, 0.0))), 0u, 0u);
  writeInst(slot + 5u, m34Mul(tmpRoot, m34Mul(local4, m34TNeg(0.20, 1.01, -0.005))), 0u, 0u);
  writeInst(slot + 6u, m34Mul(tmpRoot, m34Mul(local5, m34TNeg(-0.175, 1.29, 0.0))), 0u, 0u);
  writeInst(slot + 7u, m34Mul(tmpRoot, m34Mul(local6, m34TNeg(-0.20, 1.01, -0.005))), 0u, 0u);
  writeInst(slot + 8u, m34Mul(tmpRoot, m34Mul(local7, m34TNeg(0.096, 0.78, 0.0))), 0u, 0u);
  writeInst(slot + 9u, m34Mul(tmpRoot, m34Mul(local8, m34TNeg(0.096, 0.45, 0.005))), 0u, 0u);
  writeInst(slot + 10u, m34Mul(tmpRoot, m34Mul(local9, m34TNeg(-0.096, 0.78, 0.0))), 0u, 0u);
  writeInst(slot + 11u, m34Mul(tmpRoot, m34Mul(local10, m34TNeg(-0.096, 0.45, 0.005))), 0u, 0u);

  // Slot 12: Held tool attached to right forearm bone
  if (pose.holdingTool > 0u) {
    var toolLocal: array<vec4f, 3>;
    if (P == 8u) {
      toolLocal = m34TRS(-0.04, -0.60, 0.14, 0.15, -0.38, 0.52, 1.0);
    } else {
      toolLocal = m34TRS(0.0, -0.72, 0.06, 0.0, -0.15, 0.12, 1.0);
    }
    let worldBone6 = m34Mul(tmpRoot, local6);
    writeInst(slot + 12u, m34Mul(worldBone6, toolLocal), pose.holdingTool, pose.mask);
  } else {
    writeInst(slot + 12u, m34TRS(0.0, -1000.0, 0.0, 0.0, 0.0, 0.0, 0.0), 0u, 0u);
  }
}
