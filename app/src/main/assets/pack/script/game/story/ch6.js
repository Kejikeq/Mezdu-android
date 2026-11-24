// CHAPTER 6: СУББОТА, УТРО — ДОМ НА ХОЛМЕ (Deer Meadow & House)
import { HO, MD, dist2, m } from './common.js';
import { P } from '../../world/layout.js';
import { LETTER_FRAGMENTS, LETTER_TAIL } from '../items.js';

export function setupChapter6(ctx) {
  const { gD, registerChapterExit } = ctx;
  const { petal } = placeDeer(ctx);
  const { hearthLightD, wreathD, wreathN, vines, key, doorOpen } = placeHouse(ctx);
  const { B } = placeBench(ctx);
  const { F0, locketD, locketN, houseWoodPile, hearthUnlit, hearthNight, hearthFire } = placeInterior(ctx);
  hearthScenes(ctx, { F0, hearthFire, hearthLightD, hearthNight, hearthUnlit, houseWoodPile });
  placeCassette(ctx, { F0 });
  memoryObjective(ctx, { locketD, locketN });
  // Chapter 6 Exit Gateway behind the house (by the bench / north hedge)
  registerChapterExit(
    6,
    [HO.x(74), gD(HO.x(74), HO.z(53)) + 0.8, HO.z(53)],
    'Калитка за домом: выйти на тропу каменных лиц к костру (Глава 7 →)',
    'Калитка за домом (соберите 3 памятные вещи в доме и зафиксируйте вывод Субботы в Дневнике)'
  );
  return { petal, hearthLightD, wreathD, wreathN, vines, key, doorOpen, B, F0, locketD, locketN, hearthUnlit, hearthNight, hearthFire };
}

// the deer on the meadow: its walk, the night drip from its mouth and the petal clue
function placeDeer({ G, S, gD, night, once, pl, say }) {
  const DEER0 = MD(48, 72.5);
  S.placeDeer = () => {
    const D = G.deer;
    D.visible = true; D.pos = [DEER0[0], gD(...DEER0), DEER0[1]]; D.yaw = Math.PI / 2; D.target = null; D.bow = 0; D.bowTarget = 0; D.nightSpeedMul = 1.0;
    D.dreamOnly = false; D.nightOnly = false; D.fade = 1.0; D.dissolving = false; D.speed = 2.4;
  };
  const petal = G.place('item_petal_pink', DEER0[0] + 0.6, gD(DEER0[0] + 0.6, DEER0[1] + 0.3) + 0.04, DEER0[1] + 0.3, 0, { scale: 4, mask: 3, pitch: -Math.PI / 2, highlight: true, visible: false });
  G.interact({
    pos: [DEER0[0] + 0.6, 7.8, DEER0[1] + 0.3], r: 1.8, label: 'Поднять лепесток', cond: () => G.flags.deerTouched && !G.has('fallen_petal'),
    run: async () => {
      if (await G.pickup('fallen_petal', { desc: 'Лепесток с рога оленя. Розовый, живой, тёплый.' })) {
        petal.show(false);
        await G.wait(0.6);
        say('…Он почернел и высох прямо в ладони.', 4);
      }
    },
  });
  G.interact({
    pos: [DEER0[0] + 0.9, 8.6, DEER0[1]], r: 2.6, world: 'd', label: 'Коснуться оленя', icon: 'hand',
    cond: () => G.chapter === 6 && G.deer.visible && !G.flags.deerTouched && dist2(G.deer.pos, ...DEER0) < 1,
    run: async () => {
      G.lock(true);
      G.toNight(10, { force: true, speed: 50 });
      G.stab(-15);
      G.audio.sfx('heart');
      G.deer.bowTarget = 0;
      await G.wait(0.8);
      say('Не двигайся. Не дыши. Он… это всё ещё он?', 5);
      await G.wait(3.6);
      say('Он не нападает. Он просто… смотрит и медленно уходит в сторону дома на холме.', 3.8);
      await G.wait(2.8);
      G.set('deerTouched');
      petal.show(true);
      const t1 = MD(58, 63), t2 = HO(60, 74);
      G.deer.speed = 1.6; G.deer.fade = 1.0; G.deer.dissolving = true;
      G.deer.target = [t1[0], 0, t1[1]];
      G.deer.onArrive = () => {
        G.deer.target = [t2[0], 0, t2[1]];
        G.deer.onArrive = () => { G.deer.visible = false; };
      };
      G.lock(false);
      G.objective('Идти к дому на холме, куда ушёл олень');
    },
  });
  G.onUpdate(() => {
    const D = G.deer;
    if (G.chapter === 6 && D.visible && !G.flags.deerTouched) {
      const d = dist2(pl(), D.pos[0], D.pos[2]);
      D.bowTarget = d < 7 && !night() ? 0.55 : 0;
      const a = Math.atan2(pl()[0] - D.pos[0], pl()[2] - D.pos[2]) - D.yaw;
      D.headYawT = d < 10 ? Math.max(-0.8, Math.min(0.8, Math.atan2(Math.sin(a), Math.cos(a)))) : 0;
      if (d < 9 && once('deerSeen')) say('Ты меня знаешь, да? Почему я тебя помню?', 4.5);
    }
    G.emit.drip = D.visible && night() && G.chapter === 6 ? [D.mouth[0], D.mouth[1], D.mouth[2], 1] : [0, 0, 0, 0];
  });
  return { petal };
}

// the forester's house on the hill: door, key, wreaths, vines, the hearth light
function placeHouse({ G, once, say }) {
  // Forester's house on the hill
  const H = P.house;
  const doorX = m(H.door + 4), doorZ = m(H.z1 + 4);
  const hearthLightD = G.light({ pos: [HO.x(78), 8.3, HO.z(57.3)], r: 7.5, col: [1, 0.55, 0.25], k: 2.2, mask: 1, flicker: true, fire: true });
  G.light({ pos: [HO.x(78), 9.4, HO.z(60)], r: 8, col: [1, 0.12, 0.06], k: 2.0, mask: 2, flicker: true });
  G.light({ pos: [HO.x(81), 8.7, HO.z(58.6)], r: 3.5, col: [1, 0.7, 0.35], k: 1.2, mask: 1, flicker: true });
  const wreathD = G.place('wreath', doorX, 8.9, doorZ + 0.02, 0, { mask: 1 });
  const wreathN = G.place('wreath_dead', doorX, 8.85, doorZ + 0.02, 0, { mask: 2 });
  const vines = G.place('vines', doorX, 7.5, doorZ + 0.02, 0, { mask: 2 });
  const key = G.place('item_rusty_key', doorX + 0.06, 8.68, doorZ + 0.03, 0, { scale: 2.2, mask: 2, roll: 0.5, highlight: true });
  const doorOpen = G.place('door_open', doorX - 0.5, 7.5, doorZ - 0.25, Math.PI / 2 + 0.25, { mask: 3, visible: false });
  for (const wx of [HO.x(75.25), HO.x(80.25)]) {
    G.place('flower_box', wx, 7.85, doorZ + 0.18, 0, { mask: 1 });
    G.place('flower_box_dead', wx, 7.85, doorZ + 0.18, 0, { mask: 2 });
  }
  G.interact({
    pos: [doorX, 8.4, doorZ + 0.7], r: 1.9, world: 'd', label: () => (G.has('rusty_key') ? 'Открыть ключом' : 'Открыть дверь'), icon: 'door', cond: () => G.chapter === 6 && !G.edits.door,
    run: async () => {
      if (!G.has('rusty_key')) {
        G.audio.sfx('click');
        say('Заперто.', 1.5);
        await G.wait(1.1);
        G.toNight(16, { speed: 40 });
        await G.wait(1.2);
        if (once('houseNight')) say('Под засохшим венком на двери что-то блестит…', 4.5);
        G.objective('Достать ключ под венком на двери');
      } else {
        G.audio.sfx('door');
        await G.setEdit('door', true);
        doorOpen.show(true); wreathD.show(false); wreathN.show(false); vines.show(false);
        say('Ключ провернулся. Дверь в дом открыта.', 3.5);
        G.objective('Осмотреть гостиную дома и собрать три памятные вещи');
      }
    },
  });
  G.interact({
    pos: [doorX, 8.4, doorZ + 0.7], r: 1.9, world: 'n', label: 'Открыть дверь', icon: 'door', cond: () => G.chapter === 6 && !G.edits.door,
    run: () => say(G.has('rusty_key') ? 'Вернитесь в дневной мир (отпустите R / Глаз), чтобы отпереть замок.' : 'Не открывается. Колючие лианы держат её, но под венком виден ключ.', 3.5),
  });
  G.interact({
    pos: [doorX + 0.12, 8.5, doorZ + 0.5], r: 1.6, world: 'n', label: 'Достать ключ под венком', icon: 'key', cond: () => G.chapter === 6 && !G.has('rusty_key'), prop: key,
    run: async () => {
      if (await G.pickup('rusty_key')) {
        key.show(false);
        say('Тяжёлый ключ от двери дома. Вернусь в дневной сон и отопру дверь.', 4.2);
        G.objective('Вернуться в дневной мир и открыть дверь дома');
      }
    },
  });
  return { hearthLightD, wreathD, wreathN, vines, key, doorOpen };
}

// the bench outside the house and sitting on it
function placeBench({ G, S, gD, night, once, pl, say, smoothWalkAndSit }) {
  // Bench anchor outside the house
  const B = [m(P.bench[0]) + 0.25, m(P.bench[1]) + 0.25];
  G.place('bench', B[0], gD(...B), B[1], Math.PI / 2, { mask: 3 });
  if (G.world && G.world.addCollider) {
    G.world.addCollider({ x0: B[0] - 0.28, x1: B[0] + 0.28, y0: gD(...B), y1: gD(...B) + 0.90, z0: B[1] - 0.78, z1: B[1] + 0.78, mask: 3, tag: 'bench' });
  }
  S.sitBench = async (instant = false) => {
    const seatX = B[0] - 0.04, seatZ = B[1], seatYaw = -Math.PI / 2;
    if (instant) {
      G.player.place(seatX, gD(seatX, seatZ), seatZ, seatYaw);
      G.player.pose = 'sit'; G.player.seat = 'bench'; G.player.camYaw = seatYaw;
      S.sitting = 'bench';
      if (night()) G.toDream();
      return;
    }
    const p = pl();
    const behind = p[0] > B[0] + 0.05 && Math.abs(p[2] - B[1]) < 1.15;
    const waypoints = [];
    if (behind) {
      const side = p[2] >= B[1] ? 1 : -1;
      waypoints.push([B[0] + 0.28, B[1] + side * 1.25]);
      waypoints.push([B[0] - 0.45, B[1] + side * 1.15]);
      waypoints.push([seatX, seatZ]);
    } else {
      waypoints.push([seatX, seatZ]);
    }
    await smoothWalkAndSit(waypoints, seatYaw, 'bench');
    if (night()) G.toDream();
  };
  G.interact({
    pos: [B[0], gD(...B) + 0.5, B[1]], r: 2.2, label: 'Сесть на скамейку', icon: 'sit', cond: () => S.sitting !== 'bench',
    run: async () => { await S.sitBench(); if (once('bench')) say('Здесь… спокойнее. Можно перевести дух.', 4); },
  });
  return { B };
}

// house interior: furniture, the sofa, the locket and the hearth props
function placeInterior({ G, S, night, once, pl, say, smoothWalkAndSit }) {
  // House interior props
  const F0 = 7.5;
  const sofa = G.place('sofa', HO.x(78), F0, HO.z(60.7), Math.PI, { mask: 1 });
  G.place('sofa_torn', HO.x(78.2), F0, HO.z(60.9), Math.PI + 0.2, { mask: 2 });
  G.place('table', HO.x(81), F0, HO.z(58.7), 0, { mask: 1 });
  G.place('table_broken', HO.x(81), F0, HO.z(58.7), 0.3, { mask: 2, roll: 0.18 });
  G.place('teacup', HO.x(80.7), F0 + 0.64, HO.z(58.4), 0.3, { mask: 1, scale: 1.4 });
  G.place('teacup_black', HO.x(80.3), F0 + 0.03, HO.z(59.4), 1.2, { mask: 2, scale: 1.4, roll: 1.4 });
  G.place('teapot', HO.x(81.4), F0 + 0.64, HO.z(58.9), 2.4, { mask: 1, scale: 1.3 });
  G.place('candle', HO.x(81.6), F0 + 0.64, HO.z(58.3), 0, { mask: 1 });
  G.place('chair', HO.x(82.1), F0, HO.z(59.7), -Math.PI / 2, { mask: 1 });
  G.place('chair', HO.x(81.6), F0 + 0.25, HO.z(60.6), 0.8, { mask: 2, pitch: Math.PI / 2 });
  G.place('drawers', HO.x(74.3), F0, HO.z(59.5), Math.PI / 2, { mask: 1 });
  G.place('drawers_burnt', HO.x(74.3), F0, HO.z(59.5), Math.PI / 2, { mask: 2 });
  G.place('bookshelf', HO.x(82.25), F0, HO.z(60.8), -Math.PI / 2, { mask: 1 });
  G.place('bookshelf_fallen', HO.x(81.2), F0, HO.z(61.2), -Math.PI / 2 + 0.15, { mask: 2 });
  G.place('frame_pic', HO.x(76.2), 10.0, HO.z(57.1), 0, { mask: 1, scale: 1.4 });
  G.place('frame_pic', HO.x(74.05), 9.6, HO.z(61.4), Math.PI / 2, { mask: 1, scale: 1.2 });
  G.place('candle', HO.x(76.9), 9.52, HO.z(57.25), 0, { mask: 1 });
  G.place('candle', HO.x(79.2), 9.52, HO.z(57.25), 0, { mask: 1 });
  const locketD = G.place('item_locket', HO.x(77.9), 9.53, HO.z(57.25), 0, { scale: 2.6, mask: 1, highlight: true });
  const locketN = G.place('item_locket', HO.x(78.1), 7.55, HO.z(56.95), 0.6, { scale: 2.6, mask: 2, pitch: -Math.PI / 2, highlight: true });

  const houseWoodPile = G.place('firewood_pile', HO.x(76.15), F0, HO.z(57.15), 0.15, { mask: 3 });
  const hearthUnlit = G.place('hearth_unlit', HO.x(78), F0, HO.z(56.78), 0, { mask: 1 });
  const hearthNight = G.place('hearth_night', HO.x(78), F0, HO.z(56.78), 0, { mask: 2 });
  const hearthFire = G.place('hearth_fire', HO.x(78), F0, HO.z(56.78), 0, { mask: 3, visible: false });
  G.anchor({ pos: [HO.x(78), F0 + 1.0, HO.z(58.5)], r: 5.5, cond: () => !!G.flags.hearthRepaired && !G.peering });

  if (G.world && G.world.addCollider) {
    G.world.addCollider({ x0: HO.x(78) - 0.88, x1: HO.x(78) + 0.88, y0: F0, y1: F0 + 0.95, z0: HO.z(60.7) - 0.36, z1: HO.z(60.7) + 0.38, mask: 3, tag: 'sofa' });
    G.world.addCollider({ x0: HO.x(81) - 0.58, x1: HO.x(81) + 0.58, y0: F0, y1: F0 + 0.85, z0: HO.z(58.7) - 0.38, z1: HO.z(58.7) + 0.38, mask: 3, tag: 'table' });
    G.world.addCollider({ x0: HO.x(82.1) - 0.24, x1: HO.x(82.1) + 0.24, y0: F0, y1: F0 + 0.98, z0: HO.z(59.7) - 0.24, z1: HO.z(59.7) + 0.24, mask: 1, tag: 'chair_d' });
    G.world.addCollider({ x0: HO.x(81.6) - 0.26, x1: HO.x(81.6) + 0.26, y0: F0, y1: F0 + 0.85, z0: HO.z(60.6) - 0.26, z1: HO.z(60.6) + 0.26, mask: 2, tag: 'chair_n' });
    G.world.addCollider({ x0: HO.x(74.3) - 0.26, x1: HO.x(74.3) + 0.28, y0: F0, y1: F0 + 0.95, z0: HO.z(59.5) - 0.50, z1: HO.z(59.5) + 0.50, mask: 3, tag: 'drawers' });
    G.world.addCollider({ x0: HO.x(82.25) - 0.22, x1: HO.x(82.25) + 0.22, y0: F0, y1: F0 + 1.85, z0: HO.z(60.8) - 0.50, z1: HO.z(60.8) + 0.50, mask: 1, tag: 'bookshelf_d' });
    G.world.addCollider({ x0: HO.x(81.2) - 0.45, x1: HO.x(81.2) + 0.45, y0: F0, y1: F0 + 0.75, z0: HO.z(61.2) - 0.65, z1: HO.z(61.2) + 0.65, mask: 2, tag: 'bookshelf_n' });
    G.world.addCollider({ x0: HO.x(76.15) - 0.28, x1: HO.x(76.15) + 0.28, y0: F0, y1: F0 + 0.75, z0: HO.z(57.15) - 0.22, z1: HO.z(57.15) + 0.22, mask: 3, tag: 'firewood_pile' });
    G.world.addCollider({ x0: HO.x(77.38), x1: HO.x(78.62), y0: F0, y1: F0 + 1.15, z0: HO.z(56.30), z1: HO.z(56.92), mask: 3, tag: 'hearth_grate' });
  }

  S.sitSofa = async (instant = false) => {
    const seatX = HO.x(78), seatZ = HO.z(60.68), seatYaw = Math.PI;
    if (instant) {
      G.player.place(seatX, F0, seatZ, seatYaw);
      G.player.pose = 'sit'; G.player.seat = 'sofa'; G.player.camYaw = seatYaw + 0.35;
      S.sitting = 'sofa';
      if (night()) G.toDream();
      return;
    }
    const p = pl();
    const behind = p[2] > HO.z(60.62) && Math.abs(p[0] - HO.x(78)) < 1.15;
    const waypoints = [];
    if (behind) {
      const side = p[0] >= HO.x(78) ? 1 : -1;
      waypoints.push([HO.x(78) + side * 1.18, HO.z(60.85)]);
      waypoints.push([HO.x(78) + side * 1.12, HO.z(60.02)]);
      waypoints.push([seatX, seatZ]);
    } else {
      waypoints.push([seatX, seatZ]);
    }
    await smoothWalkAndSit(waypoints, seatYaw, 'sofa');
    if (night()) G.toDream();
  };
  G.interact({
    pos: [HO.x(78), F0 + 0.55, HO.z(60.45)], r: 2.1, world: 'any', label: 'Сесть на диван', icon: 'sit', prop: sofa, cond: () => G.chapter === 6 && S.sitting !== 'sofa',
    run: async () => {
      await S.sitSofa();
      if (once('sofa')) say(G.flags.hearthRepaired ? 'На диване у растопленного камина так тепло… Тревога отступает.' : 'Старый мягкий диван напротив камина. Здесь можно перевести дух.', 4);
    },
  });
  return { F0, locketD, locketN, houseWoodPile, hearthUnlit, hearthNight, hearthFire };
}

// repairing and lighting the hearth, sitting by it
function hearthScenes({ G, S, night, once, say, smoothWalkAndSit }, { F0, hearthFire, hearthLightD, hearthNight, hearthUnlit, houseWoodPile }) {
  S.repairHearth = async () => {
    if (!G.has('firewood')) {
      say('В топке пусто и холодно. Сначала нужно взять сухие дрова из поленницы слева от камина.', 3.8);
      return;
    }
    G.take('firewood');
    G.set('hearthRepaired');
    G.audio.sfx('success');
    await G.setEdit('hearth', true);
    hearthUnlit.show(false);
    hearthNight.show(false);
    hearthFire.show(true);
    hearthLightD.r = 9.5;
    hearthLightD.k = 2.8;
    hearthLightD.mask = 3;
    if (night()) G.toDream();
    G.stab(35);
    say('Колосник починен, сухие берёзовые дрова вспыхнули. Живой огонь согревает весь дом.', 4.2);
  };
  S.sitHearth = async () => {
    const targetX = HO.x(78), targetZ = HO.z(58.05), faceFireYaw = Math.PI;
    await smoothWalkAndSit([[targetX, targetZ]], faceFireYaw, 'ground');
    S.sitting = 'fire';
    if (night()) G.toDream();
    if (once('hearthSit')) say('Огонь в камине потрескивает. Пальцы наконец согрелись.', 3.8);
  };
  G.interact({
    pos: [HO.x(76.15), F0 + 0.45, HO.z(57.35)], r: 1.7, world: 'any', label: 'Поленница: взять сухие дрова', icon: 'hand', prop: houseWoodPile,
    cond: () => G.chapter === 6 && !G.has('firewood') && !G.flags.hearthRepaired,
    run: async () => {
      if (await G.pickup('firewood')) {
        say('Сухие берёзовые и дубовые поленья. Подойдут, чтобы растопить камин.', 3.8);
      }
    },
  });
  G.interact({
    pos: [HO.x(78), F0 + 0.55, HO.z(57.35)], r: 2.0, world: 'any',
    label: () => (!G.flags.hearthRepaired ? (G.has('firewood') ? 'Камин: сложить дрова и разжечь' : 'Камин: осмотреть холодную топку') : 'Сесть у камина'),
    icon: 'fire', prop: hearthUnlit,
    cond: () => G.chapter === 6 && (!G.flags.hearthRepaired || S.sitting !== 'fire'),
    run: async () => {
      if (!G.flags.hearthRepaired) await S.repairHearth();
      else await S.sitHearth();
    },
  });
}

// the crowbar and the hidden floor cassette (optional clue 6C)
function placeCassette({ G, S, addClue, gD, pl, say }, { F0 }) {
  // Crowbar & hidden floor cassette (Optional Clue 6C)
  const [CBX, CBZ] = [HO.x(72.9), HO.z(57.8)];
  const [FLX, FLZ] = [HO.x(81.5), HO.z(61.6)];
  const wbY = gD(CBX, CBZ);
  G.place('workbench', CBX, wbY, CBZ, Math.PI / 2, { scale: 1.0, mask: 3 });
  const crowbarProp = G.place('tool_crowbar', CBX, wbY + 0.74, CBZ, 0.35, { scale: 1.25, mask: 3 });
  const floorProp = G.place('floor_boards', FLX, F0 + 0.02, FLZ, 0, { scale: 1.1, mask: 3 });
  const cassetteProp = G.place('item_cassette', FLX, F0 + 0.06, FLZ, 0.3, { scale: 2.2, mask: 3, highlight: true, visible: false });

  const inHouse = (p) => p[0] > HO.x(74.5) && p[0] < HO.x(81.8) && p[2] > HO.z(57.2) && p[2] < HO.z(62.4) && p[1] < 11;
  S.inHouse = () => inHouse(pl());

  G.interact({
    pos: [CBX, wbY + 0.85, CBZ], r: 2.1, hold: 0.6,
    label: 'Взять гвоздодёр с верстака',
    icon: 'hand', prop: crowbarProp,
    cond: () => G.chapter === 6 && !G.flags.hasCrowbar && !G.flags.floorBreached && !S.inHouse(),
    run: async () => {
      G.flags.hasCrowbar = true;
      crowbarProp.show(false);
      G.player.holdingTool = G.models.tool_crowbar;
      G.audio.sfx('click'); G.vibrate(35);
      say('Кованый стальной гвоздодёр. Теперь можно поддеть заколоченные половицы внутри дома.', 4.2);
    },
  });

  G.interact({
    pos: [FLX, F0 + 0.45, FLZ], r: 1.65,
    label: () => (G.flags.hasCrowbar ? 'Вскрыть половицы гвоздодёром' : 'Осмотреть заколоченные половицы (опц.)'),
    icon: 'hand', prop: floorProp,
    cond: () => G.chapter === 6 && !G.flags.floorBreached && S.inHouse(),
    run: async () => {
      if (!G.flags.hasCrowbar) {
        say('Старые дубовые половицы прибиты гвоздями. Под ними тайник — нужен гвоздодёр с верстака снаружи у левой стены дома.', 4.2);
        return;
      }
      G.lock(true);
      const toFloorYaw = Math.atan2(FLX - G.player.pos[0], FLZ - G.player.pos[2]);
      G.player.yaw = toFloorYaw;
      G.player.pose = 'dig';
      G.player.lockPose = true;
      for (let i = 0; i < 2; i++) {
        G.audio.sfx('wood'); G.vibrate(45);
        await G.wait(0.55);
      }
      G.flags.floorBreached = true;
      floorProp.show(false);
      cassetteProp.show(true);
      G.player.pose = 'idle';
      G.player.lockPose = false;
      G.player.holdingTool = 0;
      if (crowbarProp.move) crowbarProp.move(FLX - 0.45, F0 + 0.03, FLZ - 0.25, 0.8);
      crowbarProp.show(true);
      say('Гвозди поддались! Под половицами — тайник с аудиокассетой.', 3.8);
      G.lock(false);
    },
  });

  G.interact({
    pos: [FLX, F0 + 0.4, FLZ], r: 1.65,
    label: 'Забрать аудиокассету с голосом Лии (опц.)',
    icon: 'hand', prop: cassetteProp,
    cond: () => G.chapter === 6 && G.flags.floorBreached && !G.has('cassette_leah') && S.inHouse(),
    run: async () => {
      if (await G.pickup('cassette_leah')) {
        cassetteProp.show(false);
        addClue('c6_leah_cassette');
        G.audio.sfx('success');
        G.stab(50);
        say('Сквозь тихое шипение магнитной ленты звучит голос из реального мира: «Мы ждём тебя, вернись скорее!»', 5.0);
      }
    },
  });
}

// the three memories of the house and the full letter
function memoryObjective({ G, S, addClue, night, once, say }, { locketD, locketN }) {
  const memories = () => ['letter_full', 'photo_2', 'locket'].filter((k) => G.has(k)).length;
  const memObjective = () => {
    if (G.chapter !== 6) return;
    if (!G.flags.letterD) {
      G.objective('Осмотреть комод у левой стены: открыть верхний ящик');
      return;
    }
    if (G.flags.letterD && !G.has('photo_2')) {
      G.objective('В темноте (удерживай R/глаз): открыть верхний ящик комода и взять фото');
      return;
    }
    if (G.flags.letterD && G.flags.letterN && !G.has('letter_full')) {
      G.objective('Подойти к обеденному столу и сложить части письма');
      return;
    }
    if (!G.has('locket')) {
      G.objective('Забрать золотой медальон с каминной полки');
      return;
    }
    G.objective(`Воспоминания дома собраны (${memories()} из 3). Сделайте вывод Субботы в Дневнике (J) и выходите на тропу за домом.`);
  };

  G.interact({
    pos: [HO.x(74.9), 8.2, HO.z(59.5)], r: 1.8, label: () => (G.flags.letterD && !G.has('photo_2') ? 'Комод: заглянуть на дно ящика' : 'Комод: открыть верхний ящик'), icon: 'hand', cond: () => G.chapter === 6,
    run: async () => {
      if (!night() && !G.flags.letterD) {
        if (!G.flags.sawPhotoD) {
          G.audio.sfx('click');
          await G.inspect('item_photo_old', 'Старая фотография', 'Я и Михаил. Мы смеёмся у ручья.', 'верхний ящик');
          G.set('sawPhotoD');
        }
        await G.read(['…не могу больше скрывать.', 'Ты должен знать правду о том, что случилось у ручья…'], false);
        G.set('letterD');
        G.peering = true;
        G.toNight(26, { force: true, speed: 30 });
        if (once('lettersFloat')) { await G.wait(0.4); say('Буквы поплыли. Комната — перевёрнута.', 3.5); }
      } else {
        if (!night()) {
          G.peering = true;
          G.toNight(22, { force: true, speed: 35 });
          await G.wait(0.35);
        }
        if (!G.has('photo_2')) {
          await G.pickup('photo_2', { kicker: 'верхний ящик' });
          addClue('c6_gold_locket');
        }
        await G.read(['…я не могу тебя найти. Три дня.', 'Полиция ничего не делает.', 'Ручей. Я знаю, что ты был у ручья…'], true);
        G.set('letterN');
        if (G.flags.letterD && once('twoLetters')) say('Тот же почерк. Другие слова. Два письма — одно целое.', 4);
      }
      memObjective();
    },
  });
  G.interact({
    pos: [HO.x(81), 8.3, HO.z(58.7)], r: 1.9, label: 'Стол: сложить части письма', icon: 'read', cond: () => G.chapter === 6 && G.flags.letterD && G.flags.letterN && !G.has('letter_full'),
    run: async () => {
      const ok = await G.ui.letterPuzzle({ fragments: LETTER_FRAGMENTS, tail: LETTER_TAIL });
      if (ok) {
        G.give('letter_full');
        addClue('c6_house_letter');
        await S.readFullLetter();
        memObjective();
      }
    },
  });
  S.readFullLetter = () => G.read(['Я не могу больше скрывать. Ты должен знать правду о том, что случилось у ручья.', 'Я не могу тебя найти. Три дня. Полиция ничего не делает. Я знаю, что ты был у ручья.', '<b>Вернись. Пожалуйста.</b>'], false);
  for (const [lk, pos, world] of [[locketD, [HO.x(77.9), 9.4, HO.z(57.6)], 'd'], [locketN, [HO.x(78.1), 7.8, HO.z(57.4)], 'n']]) {
    G.interact({
      pos, r: 1.8, world, label: 'Камин: взять золотой медальон', icon: 'hand', prop: lk, cond: () => G.chapter === 6 && !G.has('locket'),
      run: async () => {
        if (await G.pickup('locket')) {
          locketD.show(false);
          locketN.show(false);
          addClue('c6_gold_locket');
          memObjective();
        }
      },
    });
  }
}
