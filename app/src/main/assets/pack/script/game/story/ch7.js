// CHAPTER 7: СУББОТА, ПОЛДЕНЬ — КОСТЁР И КАМЕННЫЕ ЛИЦА
import { P, PATHS } from '../../world/layout.js';
import { HO, TK, m } from './common.js';

export function setupChapter7(ctx) {
  const { gD, registerChapterExit } = ctx;
  const { fallen } = placeRoute(ctx);
  placeCampfire(ctx);
  placeThicket(ctx);
  // Chapter 7 Exit Gateway (west of Thicket toward Upstream)
  registerChapterExit(
    7,
    [TK.x(31), gD(TK.x(31), TK.z(43)) + 0.8, TK.z(43)],
    'Тропа вдоль воды: выйти к верховью ручья и месту крушения (Глава 8 →)',
    'Путь к верховью ручья (совместите карты у костра, заберите билет в чаще и сделайте вывод в Дневнике)'
  );
  return { fallen };
}

// the path of the stone faces from the house to the campfire and the drain of the hero's strength along it
function placeRoute({ G, S, addClue, gD, gN, night, once, pl, say }) {
  const P3 = PATHS[4].pts;
  const along = (f, off) => {
    let L = 0; const seg = [];
    for (let i = 0; i < P3.length - 1; i++) { const l = Math.hypot(P3[i + 1][0] - P3[i][0], P3[i + 1][1] - P3[i][1]); seg.push(l); L += l; }
    let d = f * L, i = 0;
    while (i < seg.length - 1 && d > seg[i]) { d -= seg[i]; i++; }
    const t = d / seg[i], ax = P3[i][0], az = P3[i][1], bx = P3[i + 1][0], bz = P3[i + 1][1];
    const dx = (bx - ax) / seg[i], dz = (bz - az) / seg[i];
    return [m(ax + (bx - ax) * t - dz * off), m(az + (bz - az) * t + dx * off)];
  };
  const carved = [0.12, 0.26, 0.4, 0.55, 0.7, 0.86].map((f, i) => along(f, i % 2 ? 4.5 : -4.5));
  const carvedN = carved.map(([x, z], i) => G.place('stone_face', x, gN(x, z), z, i * 1.3, { scale: 1.1, mask: 2 }));
  const FS = along(0.47, 3.4);
  const fallen = G.place('item_carved_stone', FS[0], gD(...FS) + 0.06, FS[1], 0.5, { scale: 3, mask: 3, pitch: -1.2, highlight: true });
  G.interact({
    pos: [FS[0], gD(...FS) + 0.3, FS[1]], r: 1.7, label: 'Поднять резной камень-оберег (опц.)', cond: () => G.chapter >= 7 && !G.has('carved_stone'),
    run: async () => {
      if (await G.pickup('carved_stone')) {
        fallen.show(false);
        addClue('c7_carved_stone');
      }
    },
  });
  G.onUpdate(() => {
    if (G.chapter !== 7) return;
    const p = pl();
    carved.forEach(([x, z], i) => {
      const open = Math.hypot(p[0] - x, p[2] - z) < 4.5;
      const want = open ? 'stone_face_open' : 'stone_face';
      if (carvedN[i].__m !== want) { carvedN[i].__m = want; carvedN[i].setModel(want); if (open && night() && once('eyesOpen')) say('Не смотри на меня. Не смотри!', 2.5); }
    });
  });
  S.drainMul = () => {
    const p = pl();
    if (G.chapter === 7) for (const [x, z] of carved) if (Math.hypot(p[0] - x, p[2] - z) < 5) return 1.9;
    return 1;
  };
  return { fallen };
}

// the campfire: the photos, the maps and combining them
function placeCampfire({ F0, G, S, addClue, gD, gN, night, once, pl, say, smoothWalkAndSit }) {
  // Campfire
  const CF = [m(P.campfire[0]), m(P.campfire[1])];
  G.place('campfire', CF[0], gD(...CF), CF[1], 0, { mask: 1 });
  G.place('campfire_dead', CF[0], gN(...CF), CF[1], 0, { mask: 2 });
  G.place('firewood_pile', CF[0] - 1.45, gD(CF[0] - 1.45, CF[1] - 0.8), CF[1] - 0.8, 0.5, { mask: 3 });
  G.light({ pos: [CF[0], gD(...CF) + 0.8, CF[1]], r: 9, col: [1, 0.5, 0.2], k: 2.4, mask: 1, flicker: true, fire: true, cond: () => G.chapter >= 7 });
  const BP = [CF[0] + 1.7, CF[1] + 1.1];
  G.place('backpack', BP[0], gD(...BP), BP[1], -0.7, { mask: 1, scale: 1.2 });
  G.place('backpack_torn', BP[0], gN(...BP), BP[1], -0.4, { mask: 2, scale: 1.2, roll: 0.3 });
  G.place('item_bottle', BP[0] + 0.5, gD(...BP), BP[1] - 0.2, 0, { mask: 1 });
  G.place('item_map_combined', CF[0] - 1.6, gD(...CF) + 0.04, CF[1] + 0.4, 0.4, { mask: 3, scale: 2.5, pitch: -Math.PI / 2, visible: false });
  G.onUpdate(() => {
    if (S.inHouse() && G.flags.hearthRepaired) {
      G.emit.ember = [HO.x(78), F0 + 0.35, HO.z(56.78), 1];
    } else if (G.chapter >= 7) {
      G.emit.ember = [CF[0], gD(...CF) + 0.3, CF[1], 1];
    } else {
      G.emit.ember = [0, 0, 0, 0];
    }
    G.emit.smoke = (G.chapter === 6 || G.flags.hearthRepaired) ? [HO.x(78), 16.4, HO.z(56.3), 1] : [0, 0, 0, 0];
  });
  G.anchor({ pos: [CF[0], gD(...CF) + 1, CF[1]], r: 4.5, cond: () => G.chapter >= 7 });
  G.interact({
    pos: [CF[0], gD(...CF) + 0.6, CF[1]], r: 3.2, world: 'any', label: 'Сесть у костра', icon: 'fire', cond: () => G.chapter >= 7 && S.sitting !== 'fire',
    run: async () => {
      const p = pl();
      const dx = p[0] - CF[0], dz = p[2] - CF[1];
      const dist = Math.hypot(dx, dz);
      const angle = dist > 0.05 ? Math.atan2(dz, dx) : 0;
      const R_SIT = 1.65;
      const targetX = CF[0] + Math.cos(angle) * R_SIT;
      const targetZ = CF[1] + Math.sin(angle) * R_SIT;
      const faceFireYaw = Math.atan2(-Math.cos(angle), -Math.sin(angle));
      await smoothWalkAndSit([[targetX, targetZ]], faceFireYaw, 'ground');
      S.sitting = 'fire';
      if (night()) G.toDream();
      if (once('fire')) say('Огонь. Руки наконец перестают дрожать.', 3.5);
    },
  });
  G.interact({
    pos: [BP[0], gD(...BP) + 0.4, BP[1]], r: 1.8, world: 'd', label: 'Рюкзак: достать дневную карту', icon: 'bag', cond: () => G.chapter === 7 && !G.has('map_dream') && !G.has('map_combined'),
    run: async () => {
      say('Наш походный рюкзак… Достану дневную карту троп.', 3.8);
      await G.wait(0.4);
      await G.pickup('map_dream');
      if (!G.has('map_night')) {
        G.toNight(16, { speed: 40 });
        G.objective('Забрать фонарик и тёмную карту из разорванного рюкзака в «Кошмаре»');
      }
    },
  });
  G.interact({
    pos: [BP[0], gN(...BP) + 0.4, BP[1]], r: 1.8, world: 'n', label: 'Разорванный рюкзак: забрать фонарик и тёмную карту', icon: 'bag', cond: () => G.chapter === 7 && (!G.has('broken_flashlight') || (!G.has('map_night') && !G.has('map_combined'))),
    run: async () => {
      if (!G.has('broken_flashlight') && await G.pickup('broken_flashlight')) say('Фонарик горит! (Кнопка справа внизу / клавиша F)', 3.8);
      if (!G.has('map_night') && !G.has('map_combined')) await G.pickup('map_night');
      if (G.has('map_dream') && G.has('map_night')) G.objective('Подойти к бревну у костра и совместить обе карты');
    },
  });
  G.interact({
    pos: [CF[0] - 1.2, gD(...CF) + 0.4, CF[1] + 0.6], r: 2.2, label: 'Бревно у костра: совместить карты', icon: 'combine', cond: () => G.chapter === 7 && G.has('map_dream') && G.has('map_night'),
    run: () => S.combineMaps(),
  });
  S.combineMaps = async () => {
    const ok = await G.ui.mapPuzzle();
    if (!ok) return;
    G.take('map_dream'); G.take('map_night'); G.give('map_combined');
    addClue('c7_combined_map');
    G.audio.sfx('success');
    say('Красный ход упирается в изгиб ручья под обрывом! Теперь нужно осмотреть чащу к западу от костра.', 4.5);
    if (!G.has('photo_3')) G.objective('Осмотреть лесную чащу к западу от костра и найти студенческий билет');
  };
}

// the thicket west of the campfire and its figures
function placeThicket({ G, S, addClue, gD, gN, night, say }) {
  // Thicket & figures
  const TH = [m(P.thicket[0]), m(P.thicket[1])];
  const teddyD = G.place('teddy', TH[0] + 0.7, gD(TH[0] + 0.7, TH[1] + 1.2), TH[1] + 1.2, 0.6, { mask: 1, scale: 1.4 });
  const teddyN = G.place('teddy_torn', TH[0] + 0.7, gN(TH[0] + 0.7, TH[1] + 1.2), TH[1] + 1.2, 0.9, { mask: 2, scale: 1.4, roll: 0.4 });
  G.interact({ pos: [TH[0] + 0.7, gD(TH[0], TH[1]) + 0.3, TH[1] + 1.2], r: 1.8, world: 'd', label: 'Осмотреть мишку', icon: 'eye', prop: teddyD, cond: () => G.chapter === 7, run: () => G.inspect('teddy', 'Плюшевый мишка', 'Детская игрушка посреди чащи. Пуговичные глаза, заплатка на лапе.') });
  G.interact({
    pos: [TH[0] + 0.7, gN(TH[0], TH[1]) + 0.3, TH[1] + 1.2], r: 1.8, world: 'n', label: 'Достать записку из мишки (опц.)', icon: 'hand', prop: teddyN, cond: () => G.chapter === 7 && !G.has('bear_note'),
    run: async () => {
      if (await G.pickup('bear_note', { desc: 'Мишка порван. Внутри — записка.' })) {
        addClue('c7_carved_stone');
        await G.read(['Мама, я боюсь темноты.'], false);
      }
    },
  });
  G.interact({
    pos: [TK.x(37.4), gN(...TK(37.4, 41.4)) + 1.3, TK.z(41.4)], r: 2.8, world: 'any',
    label: () => (night() ? 'Взять студенческий билет, который он протягивает' : 'Фигура в чаще (вглядитесь R / Глаз, чтобы взять предмет)'),
    icon: 'hand',
    cond: () => G.chapter === 7 && !G.has('photo_3'),
    run: async () => {
      if (!night()) {
        G.peering = true;
        G.toNight(18, { force: true, speed: 40 });
        await G.wait(0.6);
      }
      say('Он протягивает мне размокшую карточку. Пальцы холодные, как речная вода.', 3.5);
      await G.wait(1.0);
      if (await G.pickup('photo_3')) {
        addClue('c7_student_card');
        if (S.reachFig) { S.reachFig.model = G.models.figure_n; S.reachFig.face = true; }
        say('Студенческий билет: «МИХАИЛ». Я вспомнил его имя!', 4.5);
        G.objective('Зафиксировать вывод Главы 7 в Дневнике (J) и пройти по руслу к верховью ручья');
      }
    },
  });
}
