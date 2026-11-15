// CHAPTER 9: ВОСКРЕСЕНЬЕ — МОСТ ЧЕРЕЗ ПРОПАСТЬ И ТОННЕЛЬ
import { P } from '../../world/layout.js';
import { NO, m } from './common.js';

export function setupChapter9(ctx) {
  const { G, S, addClue, gD, night, pl, registerChapterExit, say } = ctx;
  const BR = P.bridge2;
  const lanterns = [[73.2, 40.0, 5.0], [72.3, 20.2, 4.6], [77.6, 14.4, 2.8]];
  lanterns.forEach(([lx, lz, r], i) => {
    const [x, z] = NO(lx, lz);
    const y = i === 0 ? gD(x, z) : 8.0;
    G.place('lantern_post', x, y, z, 0, { mask: 3 });
    G.anchor({ pos: [x, y + 1.2, z], r, cond: () => G.chapter >= 9 });
    G.light({ pos: [x, y + 2.15, z], r: 6, col: [1, 0.74, 0.44], k: 1.8, mask: 3, cond: () => G.chapter >= 9 });
  });
  for (let k = 0; k < 6; k++) G.place('flower_box', m(BR.x0) + (k % 2 ? 3.25 : 0.25), 9.0, m(BR.z0) + 2 + k * 1.6, Math.PI / 2, { mask: 1, scale: 0.6 });

  // Optional 9C: Black feather by the first bridge lantern
  const featherProp = G.place('item_feather_black', NO.x(73.6), gD(...NO(73.6, 39.6)) + 0.05, NO.z(39.6), 0.4, { mask: 3, scale: 2.2, highlight: true });
  G.interact({
    pos: [NO.x(73.6), gD(...NO(73.6, 39.6)) + 0.6, NO.z(39.6)], r: 2.2, world: 'any',
    label: 'У фонаря: поднять чёрное перо ворона (опц.)',
    icon: 'hand', prop: featherProp,
    cond: () => G.chapter === 9 && !G.has('feather_black'),
    run: async () => {
      if (await G.pickup('feather_black', { kicker: 'фонарь у моста' })) {
        featherProp.show(false);
        addClue('c9_black_feather');
      }
    },
  });

  const onGirder = (p) => p[2] > m(BR.gap0) - 0.25 && p[2] < m(BR.gap1 + 1) + 0.25 && p[0] < m(BR.x0) + 1.15 && p[0] > m(BR.x0) - 0.4;
  G.fearExtra = (x, y, z, w) => G.chapter === 9 && w === 1 && !G.flags.grip && y > 7.6 && onGirder([x, y, z]) && !onGirder(G.player.pos);
  G.onUpdate((dt) => {
    const pp = G.player;
    pp.slip = 0;
    if (G.chapter !== 9) { pp.speedMul = 1; return; }
    const p = pl();
    if (onGirder(p) && night() && p[1] > 7.6 && G.flags.grip) { pp.speedMul = 1; p[0] += (m(BR.x0) + 0.25 - p[0]) * Math.min(1, dt * 4); }
    else pp.speedMul = 1;
  });
  G.interact({
    pos: [m(BR.x0) + 0.4, 8.4, m(BR.gap1 + 1) + 0.8], r: 2.4, world: 'any',
    label: 'Вонзить стальной осколок в трещину балки',
    icon: 'hand',
    cond: () => G.chapter === 9 && !G.flags.grip,
    run: () => {
      G.set('grip');
      G.audio.sfx('stone');
      say('Осколок вошёл в трещину. Теперь можно перейти по краю балки.', 4.0);
    },
  });

  const T = P.tunnel;
  const codeLockProp = G.place('code_lock', NO.x(76.45), 8.4, m(T.grateZ) + 0.55, 0, { mask: 3, scale: 1.65, highlight: true });
  G.light({ pos: [NO.x(76.3), 9.1, m(T.grateZ) + 0.9], r: 4.5, col: [1, 0.68, 0.34], k: 1.9, mask: 3, cond: () => G.chapter >= 9 && !G.edits.grate });
  G.interact({
    pos: [NO.x(76.3), 8.7, m(T.grateZ) + 1.1], r: 2.9, label: 'Кодовый замок на решётке («7319»)', icon: 'key', prop: codeLockProp, cond: () => G.chapter === 9 && !G.edits.grate,
    run: async () => {
      const ok = await G.ui.codePuzzle({ title: 'Ржавая решётка', text: 'Четыре цифры с автомобильного номера «7319»:', check: (c) => c === '7319' });
      if (ok) {
        G.audio.sfx('success'); G.audio.sfx('rumble', { dur: 1.6 });
        await G.setEdit('grate', true);
        addClue('c9_grate_code');
        G.checkpoint('tunnel', [NO.x(75.5), 8, m(T.grateZ) - 1], Math.PI, 'Тоннель');
        G.objective('Пройти тоннель мозаик и разгадать четыре рунные ниши');
      }
    },
  });

  // Tunnel mosaics & reverse runes
  for (const z of [22.4, 17.6, 16.2]) G.place('txt_vernis', NO.x(74.03), 8.7 + (z % 1) * 0.4, NO.z(z), Math.PI / 2, { mask: 2 });
  for (const z of [23.0, 17.0, 15.6]) G.place('txt_vernis', NO.x(76.97), 9.0 - (z % 1) * 0.3, NO.z(z), -Math.PI / 2, { mask: 2 });
  ['txt_r1', 'txt_r2', 'txt_r3', 'txt_r4'].forEach((t, i) => G.place(t, NO.x(76.97), 9.75 - i * 0.62, NO.z(20.2), -Math.PI / 2, { mask: 2 }));
  G.place('mosaic_house', NO.x(74.03), 8.6, NO.z(22.4), Math.PI / 2, { mask: 1 });
  G.place('mosaic_people', NO.x(76.97), 8.6, NO.z(21.0), -Math.PI / 2, { mask: 1 });
  G.place('mosaic_forest', NO.x(76.97), 8.6, NO.z(17.4), -Math.PI / 2, { mask: 1 });
  const nicheOrder = ['moon', 'leaf', 'sun', 'wave'];
  const niches = nicheOrder.map((g, i) => {
    const z = NO.z(17.8 + i * 0.65);
    const d = G.place('niche_' + g, NO.x(74.03), 8.5, z, Math.PI / 2, { mask: 3, highlight: true, scale: 1.2 });
    G.place('nichestone_' + g, NO.x(74.03), 8.5, z, Math.PI / 2, { mask: 2, scale: 1.2 });
    return [d, g];
  });
  G.light({ pos: [NO.x(74.6), 9.0, NO.z(18.8)], r: 4.5, col: [1, 0.72, 0.38], k: 1.8, mask: 3, cond: () => G.chapter >= 9 && !G.edits.tunnelWall });

  S.openCavePassage = async () => {
    if (G.edits.tunnelWall) return;
    if (!G.has('rune_map')) G.give('rune_map', true);
    const ok = await G.ui.runePuzzle({
      title: 'Четыре ниши обратного времени',
      kicker: 'мозаика тоннеля',
      text: 'Формы ниш повторяют руны переправы в обратном порядке (Лист, Волна, Луна, Солнце):',
      solution: ['leaf', 'wave', 'moon', 'sun'],
      solutions: [
        ['leaf', 'wave', 'moon', 'sun'],
        ['sun', 'moon', 'wave', 'leaf'],
      ],
    });
    if (!ok) return;
    for (const [h, g] of niches) h.setModel('nichefill_' + g);
    G.audio.sfx('success'); G.audio.sfx('rumble', { dur: 2.5 });
    await G.setEdit('tunnelWall', true);
    addClue('c9_reverse_runes');
    say('Каменная преграда отъехала! Зафиксируйте вывод Воскресенья в Дневнике (J) и шагните в зал Источника.', 4.4);
    G.objective('Зафиксировать вывод Главы 9 в Дневнике (J) и войти в зал Источника');
  };
  G.interact({
    pos: [NO.x(74.4), 8.5, NO.z(18.8)], r: 3.0, label: 'Каменные ниши: вставить четыре руны', icon: 'hand', cond: () => G.chapter === 9 && !G.edits.tunnelWall,
    run: () => S.openCavePassage(),
  });
  G.interact({
    pos: [NO.x(75.5), 8.5, m(T.wallZ) + 0.6], r: 3.2, label: 'Каменная преграда (четыре рунные ниши)', icon: 'key', cond: () => G.chapter === 9 && !G.edits.tunnelWall,
    run: () => S.openCavePassage(),
  });

  // Chapter 9 Exit Gateway at the opened tunnel wall
  registerChapterExit(
    9,
    [NO.x(75.5), 8.2, m(T.wallZ) - 0.8],
    'Зал Источника: шагнуть за грань в Главу 10 («Между» →)',
    'Проход в грот (откройте каменную преграду и зафиксируйте вывод Воскресенья в Дневнике)'
  );
  return { featherProp, niches };
}
