

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

@compute @workgroup_size(1)
fn rig(@builtin(global_invocation_id) gid: vec3u) {
  let rigIdx = gid.x;
  let pose = poses[rigIdx];
  let slot = pose.slot;
  if (pose.mask == 0u || pose.pos.w <= 0.001) {
    for (var i = 0u; i < 9u; i = i + 1u) {
      writeInst(slot + i, m34TRS(0.0, -1000.0, 0.0, 0.0, 0.0, 0.0, 0.0), 0u, 0u);
    }
    return;
  }
  let P = pose.poseId;
  let ph = pose.phase;
  let t = pose.time;
  
  var rootRoll = 0.0; var rootY = 0.0; var rootPitch = 0.0;
  var legL = 0.0; var legR = 0.0; var armL = 0.0; var armR = 0.0;
  var elbL = -0.2; var elbR = -0.2; var armRollL = 0.0; var armRollR = 0.0;
  var headP = 0.0; var headY = 0.0; var torsoP = 0.0; var bob = 0.0;
  var legRollL = 0.0; var legRollR = 0.0;

  if (P == 1u) { // walk
    let a = sin(ph) * min(0.65, 0.25 + pose.speed * 0.13);
    legL = a; legR = -a; armL = -a * 0.8; armR = a * 0.8; bob = abs(cos(ph)) * 0.035; torsoP = 0.04 + pose.speed * 0.012;
    elbL = -0.22 + min(0.0, armL) * 0.7; elbR = -0.22 + min(0.0, armR) * 0.7;
    if (pose.holdingTool > 0u) { armR = -0.35 + armR * 0.25; elbR = -0.55; armRollR = -0.12; }
  } else if (P == 0u) { // idle
    bob = sin(t * 1.6) * 0.006; armL = sin(t * 1.1) * 0.03; armR = -armL; headY = sin(t * 0.4) * 0.25; headP = sin(t * 0.33) * 0.05;
    legRollL = 0.035; legRollR = -0.035; armRollL = 0.07; armRollR = -0.07;
    if (pose.holdingTool > 0u) { armR = -0.35 + armR * 0.5; elbR = -0.55; armRollR = -0.12; }
  } else if (P == 2u) { // sit
    rootY = -0.38; legL = -0.68; legR = -0.68; armL = -0.3; armR = -0.3; elbL = -0.35; elbR = -0.35; headP = 0.12; headY = sin(t * 0.3) * 0.2;
    if (pose.seatId == 1u) { // ground
      rootY = -0.7; legL = -1.5; legR = -1.5; armL = 0.35; armR = 0.35; elbL = -0.04; elbR = -0.04; armRollL = 0.15; armRollR = -0.15; torsoP = -0.12; headP = 0.12;
    } else if (pose.seatId == 2u) { // bench
      rootY = -0.38; legL = -0.68; legR = -0.68; armL = -0.42; armR = -0.42; elbL = -0.45; elbR = -0.45; torsoP = -0.04; headP = 0.1;
    } else if (pose.seatId == 3u) { // sofa
      rootY = -0.42; legL = -0.72; legR = -0.72; armL = -0.35; armR = -0.35; elbL = -0.48; elbR = -0.48; armRollL = 0.12; armRollR = -0.12; torsoP = -0.09; headP = 0.08; headY = sin(t * 0.28) * 0.18;
    }
  } else if (P == 3u) { // kneel
    rootY = -0.32; legL = -0.45; legR = 0.35; torsoP = 0.14; armL = -0.35; armR = -0.35; elbL = -0.25; elbR = -0.25; headP = 0.22;
  } else if (P == 4u) { // lie
    rootPitch = -1.5708; rootY = 0.18; armL = 0.1; armR = 0.1; elbL = -0.05; elbR = -0.05; headY = 0.4;
  } else if (P == 5u) { // wash_ashore
    rootPitch = -1.5708 + 0.04;
    rootY = 0.08 + sin(t * 1.4) * 0.008;
    armL = -0.18; armR = 0.24; elbL = -0.32; elbR = -0.45; armRollL = 0.18; armRollR = -0.22;
    headY = 0.22 + sin(t * 0.7) * 0.03; headP = 0.08;
    legL = 0.12; legR = -0.08; legRollL = 0.06; legRollR = -0.06;
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
      legL = 0.18; legR = -0.55 + stroke * 0.35;
      rootY = -0.05 - stroke * 0.05;
    } else if (phase < 0.78) {
      let lift = sin(((phase - 0.45) / 0.33) * 3.14159265);
      torsoP = 0.32 - lift * 0.22;
      headP = 0.20;
      armR = -0.68 + lift * 0.22; elbR = -0.42 - lift * 0.25; armRollR = -0.48;
      armL = -0.52 + lift * 0.18; elbL = -0.68 - lift * 0.20; armRollL = 0.48;
      legL = 0.22; legR = -0.22;
      rootY = -0.02 + lift * 0.03;
    } else {
      torsoP = 0.22; headP = 0.25;
      armR = -0.48; elbR = -0.38; armRollR = -0.50;
      armL = -0.42; elbL = -0.56; armRollL = 0.50;
      legL = 0.18; legR = -0.28;
      rootY = -0.03;
    }
  } else if (P == 9u) { // getup_kneel
    rootY = -0.44 + sin(t * 1.2) * 0.02;
    legL = -0.85; legR = -0.85; legRollL = 0.12; legRollR = -0.12;
    torsoP = 0.38; headP = 0.42; headY = sin(t * 1.5) * 0.12;
    armL = -0.58; armR = -0.58; elbL = -0.45; elbR = -0.45; armRollL = 0.18; armRollR = -0.18;
  } else if (P == 10u) { // walk_head
    let a = sin(ph) * min(0.4, 0.15 + pose.speed * 0.12);
    legL = a; legR = -a; armL = -a * 0.6; armR = 0.58; elbR = 0.0; armRollR = 2.93;
    headP = 0.28 + sin(t * 6.0) * 0.04; headY = sin(t * 2.3) * 0.15; torsoP = 0.16;
    bob = abs(cos(ph)) * 0.02; rootRoll = sin(t * 2.1) * 0.06 * pose.headache;
  } else if (P == 11u) { // getup_stand
    rootY = -0.15 + sin(t * 1.4) * 0.02;
    torsoP = 0.18; headP = 0.22; rootRoll = sin(t * 2.0) * 0.08;
    armR = 0.55; elbR = 0.0; armRollR = 2.93;
    armL = -0.25; elbL = -0.2; armRollL = 0.1;
    legL = 0.1; legR = -0.1;
  }

  let s = pose.pos.w;
  let tmpRoot = m34TRS(pose.pos.x, pose.pos.y + rootY + bob, pose.pos.z, pose.yaw, rootPitch, rootRoll, s);
  
  let hipY = 0.78; let shY = 1.27; let neckY = 1.31; let hipX = 0.112; let shX = 0.29;
  
  var ni = 0u;
  // torso
  let torsoMat = m34Mul(tmpRoot, m34TRS(0.0, hipY - 0.02, 0.0, 0.0, torsoP, 0.0, 1.0));
  writeInst(slot + ni, torsoMat, pose.models.x, pose.mask); ni++;
  
  // head
  let headMat = m34Mul(tmpRoot, m34TRS(0.0, neckY - torsoP * 0.1, torsoP * 0.25, headY, headP, 0.0, 1.0));
  writeInst(slot + ni, headMat, pose.models.y, pose.mask); ni++;
  
  // Left arm
  let uarmLMat = m34Mul(tmpRoot, m34TRS(shX, shY, torsoP * 0.15, 0.0, armL, armRollL + 0.05, 1.0));
  writeInst(slot + ni, uarmLMat, pose.models.w, pose.mask); ni++;
  let farmLMat = m34Mul(uarmLMat, m34TRS(0.0, -0.17, 0.0, 0.0, elbL, 0.0, 1.0));
  writeInst(slot + ni, farmLMat, pose.models2.y, pose.mask); ni++;
  
  // Right arm
  let uarmRMat = m34Mul(tmpRoot, m34TRS(-shX, shY, torsoP * 0.15, 0.0, armR, armRollR - 0.05, 1.0));
  writeInst(slot + ni, uarmRMat, pose.models.z, pose.mask); ni++;
  let farmRMat = m34Mul(uarmRMat, m34TRS(0.0, -0.17, 0.0, 0.0, elbR, 0.0, 1.0));
  writeInst(slot + ni, farmRMat, pose.models2.x, pose.mask); ni++;
  
  // Legs
  let legLMat = m34Mul(tmpRoot, m34TRS(hipX, hipY, 0.0, 0.0, legL, legRollL, 1.0));
  writeInst(slot + ni, legLMat, pose.models2.z, pose.mask); ni++;
  let legRMat = m34Mul(tmpRoot, m34TRS(-hipX, hipY, 0.0, 0.0, legR, legRollR, 1.0));
  writeInst(slot + ni, legRMat, pose.models2.z, pose.mask); ni++;
  
  // Tool (1-handed at side when walking/idle, 2-handed across body when digging)
  if (pose.holdingTool > 0u) {
    var toolLocal: array<vec4f, 3>;
    if (P == 8u) {
      toolLocal = m34TRS(-0.04, -0.62, 0.16, 0.15, -0.38, 0.52, 1.0);
    } else {
      toolLocal = m34TRS(0.07, -0.74, 0.11, 0.0, -0.15, 0.12, 1.0);
    }
    let toolMat = m34Mul(farmRMat, toolLocal);
    writeInst(slot + ni, toolMat, pose.holdingTool, pose.mask); ni++;
  } else {
    writeInst(slot + ni, m34TRS(0.0, -1000.0, 0.0, 0.0, 0.0, 0.0, 0.0), 0u, 0u); ni++;
  }
}
