// The story of МЕЖДУ: 10 chapters reconstructing the week before the crash (Monday to Sunday + "Between"),
// featuring mandatory vs. optional clues, Real vs. Phantom NPCs, the Deduction Board, and the Play-Along Engine.
// This file holds the shared rules (chapter exits, NPC dialogue, endings, restore); each chapter's scenes are in story/chN.js.
import { CHAPTERS_DATA } from './chapters_data.js';
import { lightFor } from '../gfx/sky.js';
import { m, HO, NO } from './story/common.js';
import { setupChapter1 } from './story/ch1.js';
import { setupChapter2 } from './story/ch2.js';
import { setupChapter3 } from './story/ch3.js';
import { setupChapter4 } from './story/ch4.js';
import { setupChapter5 } from './story/ch5.js';
import { setupChapter6 } from './story/ch6.js';
import { setupChapter7 } from './story/ch7.js';
import { setupChapter8 } from './story/ch8.js';
import { setupChapter9 } from './story/ch9.js';
import { setupChapter10 } from './story/ch10.js';
import { setupProgression } from './story/progression.js';
import { setupDialogue } from './story/dialogue.js';
import { setupEndings } from './story/endings.js';
import { setupFigures } from './story/figures.js';
import { setupIntro } from './story/intro.js';
import { setupSeat } from './story/seat.js';
export function setupStory(G) {
  const S = {};
  G.story = S;
  const gD = (x, z) => G.groundAt(x, z, 0);
  const gN = (x, z) => G.groundAt(x, z, 1);
  const night = () => G.worldAtPlayer() > 0.5;
  const pl = () => G.player.pos;
  const say = (t, d) => G.say(t, d);
  const voice = (t, d, who = 'Голос') => G.say(t, d, who);
  const once = (k) => { if (G.flags['said_' + k]) return false; G.flags['said_' + k] = 1; return true; };
  const addClue = (id, silent = false) => G.memoryBoard && G.memoryBoard.addClue(id, silent);
  const addTestimony = (id, silent = false) => G.memoryBoard && G.memoryBoard.addTestimony(id, silent);
  const adapt = (variants) => (G.memoryBoard ? G.memoryBoard.adapt(variants) : (variants.default || variants.TRUTH || ''));

  const { smoothWalkAndSit } = setupSeat({ G, S, gD });

  // ============================================================== CHAPTER EXIT & PROGRESSION RULES
  // the shared helpers every story module gets; values a later module needs are added as they appear
  const ctx = { G, S, gD, gN, night, pl, say, voice, once, addClue, addTestimony, adapt, smoothWalkAndSit };
  ctx.registerChapterExit = setupProgression(ctx).registerChapterExit;

  // ============================================================== NPC DIALOGUE & PLAY-ALONG SYSTEM
  setupDialogue(ctx);

  // ============================================================== CHAPTER 1: ПОНЕДЕЛЬНИК — ПОРОГ (Suburban House, Yard & University)
  const { CH1_H, ch1Floor2Y, ch1FrontDoorState, ch1PassProp, ch1SedativeProp, ch1ReceiptProp } = setupChapter1(ctx);
  ctx.ch1Floor2Y = ch1Floor2Y;

  // ============================================================== CHAPTER 2: ВТОРНИК — КРАСНЫЙ СВЕТ (Archive & Darkroom)
  const { ch2KeyProp, ch2PhotoProp, ch2DoorOpenProp } = setupChapter2(ctx);

  // ============================================================== CHAPTER 3: СРЕДА — ПЕРРОН И МАСТЕРСКАЯ
  const { ch3KeyProp, ch3TicketProp, ch3DoorOpenProp } = setupChapter3(ctx);

  // ============================================================== CHAPTER 4: ЧЕТВЕРГ — НОЧНОЕ ШОССЕ И МОТЕЛЬ «ПОВОРОТ»
  const { ch4KeyProp, ch4BookProp, ch4DoorOpenProp } = setupChapter4(ctx);

  // ============================================================== CHAPTER 5: ПЯТНИЦА — ПЕСЧАНЫЙ БЕРЕГ И ПЕРЕПРАВА
  const { START, compassProp, plateD, lockProp, runeMap } = setupChapter5(ctx);
  ctx.START = START;

  // ============================================================== CHAPTER 6: СУББОТА, УТРО — ДОМ НА ХОЛМЕ (Deer Meadow & House)
  const { petal, hearthLightD, wreathD, wreathN, vines, key, doorOpen, B, F0, locketD, locketN, hearthUnlit, hearthNight, hearthFire } = setupChapter6(ctx);
  ctx.F0 = F0; ctx.B = B;

  // ============================================================== CHAPTER 7: СУББОТА, ПОЛДЕНЬ — КОСТЁР И КАМЕННЫЕ ЛИЦА
  const { fallen } = setupChapter7(ctx);

  // ============================================================== CHAPTER 8: СУББОТА, ВЕЧЕР — ВЕРХОВЬЕ РУЧЬЯ И ОБРЫВ
  const { plate, shard, CL } = setupChapter8(ctx);

  // ============================================================== CHAPTER 9: ВОСКРЕСЕНЬЕ — МОСТ ЧЕРЕЗ ПРОПАСТЬ И ТОННЕЛЬ
  const { featherProp, niches } = setupChapter9(ctx);

  // ============================================================== CHAPTER 10: МЕЖДУ — ПОДЗЕМНЫЙ ГРОТ И ПАЛАТА № 7
  const { carKey } = setupChapter10(ctx);

  // ============================================================== 4 ADAPTIVE ENDINGS
  setupEndings(ctx);

  // ============================================================== DYNAMIC NPC & FIGURE SPAWNING PER CHAPTER
  setupFigures(ctx);

  // ============================================================== CHAPTER RULES & RESTORE
  S.applyChapter = (ch) => {
    const D = G.duality;
    G.chapter = ch;
    const cd = CHAPTERS_DATA[ch] || CHAPTERS_DATA[1];
    G.sceneName = cd.sceneName;
    D.baseNight = ch >= 9;
    D.drain = ch <= 4 ? 1.8 : ch <= 7 ? 2.1 : 1.0;
    D.regen = ch <= 4 ? 2.4 : 1.8;
    if (ch >= 9) { D.base = 1; D.wave.active = false; D.nightTimer = 0; }
    S.setupFigures();
    G.deer.visible = (ch === 6 && !G.flags.deerTouched) || (ch === 8 && !G.flags.ch8end);
    if (ch === 6 && !G.flags.deerTouched) S.placeDeer();
    if (ch === 8) {
      const D2 = G.deer;
      D2.visible = true;
      D2.pos[0] = CL[0] - 0.8; D2.pos[1] = gD(CL[0] - 0.8, CL[1] - 0.6); D2.pos[2] = CL[1] - 0.6;
      D2.yaw = Math.PI; D2.target = null; D2.bowTarget = 0.3; D2.dissolving = false; D2.fade = 1.0;
    }
    G.rabbit.visible = ch === 5 && !G.flags.rabbitPet;
    G.refreshTools();
    if (G.memoryBoard) G.memoryBoard.refreshBadge();
    G.objective(cd.defaultObjective);
  };

  S.restore = async () => {
    const f = G.flags, ch = G.chapter || 1;
    f.eye = 1;
    await G.setEdit('ch1Door', !!f.ch1DoorOpened || ch > 1);
    await G.setEdit('ch2Door', !!f.ch2DoorOpened || ch > 2);
    await G.setEdit('ch3Door', !!f.ch3DoorOpened || ch > 3);
    await G.setEdit('ch4Door', !!f.ch4DoorOpened || ch > 4);
    await G.setEdit('bridge1', !!f.bridgeSolved || !!f.terminalUnlocked || ch > 5);
    await G.setEdit('startCave', !!f.chestDug || ch > 5);
    await G.setEdit('door', (!!G.has('rusty_key') && !!f.doorOpened) || ch > 6);
    await G.setEdit('hearth', !!f.hearthRepaired);
    await G.setEdit('grate', !!f.grateOpen || ch > 9);
    await G.setEdit('tunnelWall', !!f.wallOpen || ch > 9);

    ch1FrontDoorState.setInstant(!!G.edits.ch1Door);
    ch2DoorOpenProp.show(!!G.edits.ch2Door);
    ch3DoorOpenProp.show(!!G.edits.ch3Door);
    ch4DoorOpenProp.show(!!G.edits.ch4Door);
    ch1PassProp.show(!G.has('student_pass'));
    ch1SedativeProp.show(!G.has('sedative_bottle'));
    ch1ReceiptProp.show(!G.has('brake_receipt'));
    ch2KeyProp.show(!G.has('darkroom_key'));
    ch2PhotoProp.show(!G.has('wet_photo'));
    ch3KeyProp.show(!G.has('garage_key'));
    ch3TicketProp.show(!G.has('train_ticket'));
    ch4KeyProp.show(!G.has('motel_key'));
    ch4BookProp.show(!G.has('guestbook_page'));
    compassProp.show(!G.has('cracked_compass'));
    featherProp.show(!G.has('feather_black'));

    const doorIsOpen = !!G.edits.door;
    doorOpen.show(doorIsOpen); wreathD.show(!doorIsOpen); wreathN.show(!doorIsOpen); vines.show(!doorIsOpen);
    const hearthFixed = !!f.hearthRepaired;
    hearthUnlit.show(!hearthFixed); hearthNight.show(!hearthFixed); hearthFire.show(hearthFixed);
    hearthLightD.r = hearthFixed ? 9.5 : 7.5; hearthLightD.k = hearthFixed ? 2.8 : 2.2; hearthLightD.mask = hearthFixed ? 3 : 1;
    key.show(!G.has('rusty_key'));
    runeMap.show(!G.has('rune_map'));
    petal.show(!!f.deerTouched && !G.has('fallen_petal'));
    locketD.show(!G.has('locket')); locketN.show(!G.has('locket'));
    fallen.show(!G.has('carved_stone'));
    plate.show(!G.has('license_plate'));
    shard.show(!G.has('metal_shard'));
    carKey.show(!!f.flashback && !G.has('car_key'));

    const unlocked = !!f.terminalUnlocked || !!f.bridgeSolved || ch > 5;
    lockProp.show(!unlocked);
    plateD.setModel(unlocked ? 'rune_plate' : 'rune_plate_moss');

    for (const [h, g] of niches) h.setModel((G.edits.tunnelWall ? 'nichefill_' : 'niche_') + g);
    G.mike.visible = false; G.shadow.visible = false;
    S.sitting = null;
    S.applyChapter(ch);
    if (G.has('car_key') && ch === 10) S.showMike();
  };

  const _setEdit = G.setEdit.bind(G);
  G.setEdit = async (name, on) => {
    if (name === 'ch1Door' && on) G.flags.ch1DoorOpened = true;
    if (name === 'ch2Door' && on) G.flags.ch2DoorOpened = true;
    if (name === 'ch3Door' && on) G.flags.ch3DoorOpened = true;
    if (name === 'ch4Door' && on) G.flags.ch4DoorOpened = true;
    if (name === 'startCave' && on) G.flags.chestDug = true;
    if (name === 'door' && on) G.flags.doorOpened = true;
    if (name === 'grate' && on) G.flags.grateOpen = true;
    if (name === 'tunnelWall' && on) G.flags.wallOpen = true;
    return _setEdit(name, on);
  };

  // ============================================================== INTRO (CHAPTER 1: MONDAY IN ELIAS'S APARTMENT)
  setupIntro(ctx);

  // ============================================================== MISC HOOKS & LIGHTING
  S.onStand = () => {
    if (S.sitting === 'sofa') {
      G.player.pos[2] = Math.min(G.player.pos[2], HO.z(59.98));
    } else if (S.sitting === 'bench') {
      G.player.pos[0] = Math.min(G.player.pos[0], B[0] - 0.56);
    }
    S.sitting = null;
    G.player.seat = null;
  };
  G.onUpdate((dt) => {
    if (S.sitting === 'bench') G.stab(14 * dt);
    if (S.sitting === 'sofa') G.stab((G.flags.hearthRepaired ? 24 : 16) * dt);
    if (S.sitting === 'fire') G.stab(22 * dt);
    if (S.sitting && G.duality.stability >= 99.5 && once('restored' + G.chapter)) say('Дыхание выровнялось.', 2);
  });
  S.photoAnchor = async () => {
    const D = G.duality;
    G.toDream({ speed: 50 });
    D.nightTimer = 0;
    await G.wait(5);
    if (D.baseNight) G.toNight(0);
  };

  S.lighting = () => {
    const p = pl();
    const insideCh1 = G.chapter === 1 && p[0] > m(CH1_H.garageX0) && p[0] < m(CH1_H.x1) && p[2] > m(CH1_H.z0) && p[2] < m(CH1_H.z1) && p[1] < 14.5;
    const inside = G.state === 'game' && (insideCh1 || S.inHouse() || (p[2] < NO.z(24.5) && p[2] > NO.z(0) && p[0] > NO.x(55) && p[0] < NO.x(96) && p[1] < 12));
    // sky, sun, fog and exposure of the chapter's time of day (src/gfx/sky.js)
    return lightFor(G.chapter, inside, G.headache, G.voidMode);
  };

  S.menuScene = () => {
    G.chapter = 1;
    const mx = m(408), mz = m(2182);
    const y = gD(mx, mz);
    S._menuMx = mx; S._menuMz = mz; S._menuBaseY = y;
    G.player.place(mx, y, mz, Math.PI);
    G.player.pose = 'idle';
    G.rabbit.visible = false;
    S.menuA = 0;
  };
  S.menuUpdate = (dt) => {
    S.menuA += dt * 0.045;
    const mx = S._menuMx ?? m(408), mz = S._menuMz ?? m(2182);
    const y = S._menuBaseY ?? gD(mx, mz);
    const a = S.menuA;
    const r = 4.6 + Math.sin(a * 0.6) * 0.5;
    const cx = mx + Math.sin(a) * r, cz = mz - 5.5 + Math.cos(a) * r;
    const cp = G.player.camPos, ct = G.player.camTarget;
    cp[0] = cx; cp[1] = Math.max(y, G.groundAt(cx, cz)) + 2.1 + Math.sin(a * 0.7) * 0.25; cp[2] = cz;
    ct[0] = mx; ct[1] = y + 1.5; ct[2] = mz + 1.5;
  };
  return S;
}
