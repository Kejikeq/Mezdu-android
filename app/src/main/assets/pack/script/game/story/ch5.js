// CHAPTER 5: ПЯТНИЦА — ПЕСЧАНЫЙ БЕРЕГ И ПЕРЕПРАВА
import { CR, m } from './common.js';
import { P, VS } from '../../world/layout.js';

export function setupChapter5(ctx) {
  const { gD, registerChapterExit } = ctx;
  const { START, compassProp } = placeShore(ctx);
  placeCave(ctx);
  const { plateD, lockProp, runeMap } = placeCrossing(ctx);
  // Chapter 5 Exit Gateway on the North Bank of the bridge
  registerChapterExit(
    5,
    [CR.x(67), gD(CR.x(67), CR.z(85)) + 0.8, CR.z(85)],
    'Тропа за мостом: подняться к поляне с Оленем и Дому на холме (Глава 6 →)',
    'Северный берег (восстановите мост и зафиксируйте вывод Пятницы в Дневнике)'
  );
  return { START, compassProp, plateD, lockProp, runeMap };
}

// the start on the sandy shore: the rabbit, the cracked compass (optional 5C), the nightmare rune stones
function placeShore({ G, addClue, gD, gN, once, say }) {
  const START = [m(P.start[0]), m(P.start[1])];
  G.rabbit.pos = [START[0] + 1.6, gD(START[0] + 1.6, START[1] - 1.8), START[1] - 1.8];
  G.rabbit.yaw = -2.4;

  // Optional 5C: Cracked field compass at the water's edge
  const compassProp = G.place('item_locket', START[0] - 2.4, gD(START[0] - 2.4, START[1] - 1.2) + 0.05, START[1] - 1.2, 0.5, { scale: 2.2, mask: 3, highlight: true });
  G.interact({
    pos: [START[0] - 2.4, gD(START[0] - 2.4, START[1] - 1.2) + 0.5, START[1] - 1.2], r: 2.2, world: 'any',
    label: 'Кромка воды: поднять разбитый компас (опц.)',
    icon: 'hand', prop: compassProp,
    cond: () => G.chapter === 5 && !G.has('cracked_compass'),
    run: async () => {
      if (await G.pickup('cracked_compass', { kicker: 'прибрежная галька' })) {
        compassProp.show(false);
        addClue('c5_cracked_compass');
        say('Стекло треснуло от удара о камни, а стрелка замерла… Словно меня выбросило сюда волной.', 4.2);
      }
    },
  });

  // Nightmare rune stones in the dry bed
  const runeStones = [['leaf', 60.6, 91.2], ['sun', 62.8, 89.6], ['wave', 65.6, 91.6], ['moon', 66.9, 89.9]];
  const runeInfo = { sun: ['Солнце', 'красным'], moon: ['Луна', 'синим'], wave: ['Волна', 'жёлтым'], leaf: ['Лист', 'зелёным'] };
  for (const [g, lx, lz] of runeStones) {
    const [x, z] = CR(lx, lz);
    G.place('runestone_' + g, x, gN(x, z), z, (lx * 3) % 6.28, { scale: 1.8, mask: 2 });
    G.interact({
      pos: [x, 7.2, CR.z(94.4)], r: 2.6, world: 'n', label: 'Осмотреть руну', icon: 'eye', cond: () => G.chapter === 5,
      run: async () => {
        await G.inspect('runestone_' + g, 'Руна «' + runeInfo[g][0] + '»', 'Камень на дне сухого русла. Знак светится ' + runeInfo[g][1] + '.', 'сухое русло');
        G.flags['rune_' + g] = 1;
        if (once('runeSeen')) G.objective('Ввести знаки на каменной плите у старого моста');
      },
    });
  }
  return { START, compassProp };
}

// the rockface cave on the forest trail: the shovel, the blocked passage and the buried chest
function placeCave({ G, addClue, gD, say }) {
  // Forest trail rockface cave & physical shovel excavation
  const SC = P.startCave;
  const caveEntrance = [(SC.blockX0 + 0.5) * VS, SC.y0 * VS, ((SC.z0 + SC.z1) * 0.5) * VS];
  const [SHX, SHZ] = [caveEntrance[0] - 2.2, caveEntrance[2] + 2.4];
  const [CHX, CHZ] = [(SC.x0 + SC.x1) * 0.5 * VS, ((SC.z0 + SC.z1) * 0.5) * VS];
  const shovelY = gD(SHX, SHZ);
  const caveShovelY = gD(caveEntrance[0] - 0.7, caveEntrance[2] - 1.2);
  const chestY = SC.y0 * VS;
  const chestProp = G.place('chest_buried', CHX, chestY, CHZ, 0.4, { scale: 1.15, mask: 3 });
  const shovelProp = G.place('tool_shovel', SHX, shovelY, SHZ, 0.6, { scale: 1.2, mask: 3, pitch: 0.18 });
  G.light({ pos: [CHX, chestY + 1.2, CHZ], r: 6.5, col: [1.0, 0.75, 0.4], k: 2.2, mask: 3 });

  G.interact({
    pos: [SHX, shovelY + 0.6, SHZ], r: 2.4, hold: 0.8,
    label: () => (G.flags.hasShovel ? 'Сапёрная лопата' : 'Взять сапёрную лопату у раскопок'),
    icon: 'hand', prop: shovelProp,
    cond: () => G.chapter === 5 && !G.flags.hasShovel && !G.flags.chestDug,
    run: async () => {
      G.flags.hasShovel = true;
      shovelProp.show(false);
      G.player.holdingTool = G.models.tool_shovel;
      G.audio.sfx('click'); G.vibrate(35);
      say('Взял сапёрную лопату. Теперь можно расчистить завал у входа в штольню и откопать сундук.', 4.2);
      G.objective('Расчистить завал штольни лопатой и откопать сундук');
    },
  });

  G.interact({
    pos: [caveEntrance[0], caveEntrance[1] + 0.8, caveEntrance[2]], r: 2.5,
    label: () => (G.flags.chestDug ? 'Расчищенный проход в пещеру' : G.flags.hasShovel ? 'Расчистить завал лопатой (откопать сундук)' : 'Осмотреть заблокированный проход в пещеру'),
    icon: 'eye',
    cond: () => G.chapter === 5 && !G.flags.chestDug,
    run: async () => {
      if (!G.flags.hasShovel) {
        G.flags.sawCaveCrevice = true;
        G.audio.sfx('click');
        await G.ui.inspect({
          model: G.models.chest_buried,
          kicker: 'завал штольни',
          title: 'Засыпанный сундук дорожников',
          desc: 'За обвалившимся грунтом виден стальной сундук дорожной службы с ключом от механизма моста. Нужна сапёрная лопата у входа.',
          buttons: [{ label: 'Отойти и взять лопату', primary: true, value: true }]
        });
        say('Внутри завала — сундук с ключом от моста. Возьму лопату рядом у входа.', 4.0);
        G.objective('Взять сапёрную лопату рядом со входом в штольню');
        return;
      }
      G.lock(true);
      G.audio.sfx('click'); G.vibrate(35);
      const toCaveYaw = Math.atan2(caveEntrance[0] - G.player.pos[0], caveEntrance[2] - G.player.pos[2]);
      G.player.yaw = toCaveYaw;
      G.player.pose = 'dig';
      G.player.lockPose = true;
      for (let stroke = 0; stroke < 2; stroke++) {
        G.audio.sfx('footstep'); G.vibrate(45);
        await G.wait(0.55);
      }
      G.audio.sfx('rumble', { dur: 1.2 });
      await G.setEdit('startCave', true);
      G.flags.chestDug = true;
      G.flags.caveDug = true;
      chestProp.setModel('chest_unburied');
      G.player.pose = 'idle';
      G.player.lockPose = false;
      G.player.holdingTool = 0;
      shovelProp.pos = [caveEntrance[0] - 0.7, caveShovelY, caveEntrance[2] - 1.2];
      shovelProp.pitch = 0.35;
      shovelProp.yaw = toCaveYaw + Math.PI / 2;
      shovelProp.show(true);
      say('Завал расчищен! Стальной сундук топографов открыт для осмотра.', 4.2);
      G.objective('Открыть сундук дорожников внутри штольни');
      G.lock(false);
    },
  });

  G.interact({
    pos: [CHX, chestY + 0.5, CHZ], r: 2.4,
    label: () => (!G.flags.chestDug ? 'Засыпанный сундук дорожников' : (!G.flags.chestOpened ? 'Открыть сундук дорожников' : 'Осмотреть пустой сундук')),
    icon: 'hand', prop: chestProp,
    cond: () => G.chapter === 5 && !G.flags.chestOpened,
    run: async () => {
      if (!G.flags.chestDug) {
        say('Сундук в глубине завала. Сначала нужно расчистить проход лопатой.', 4.0);
        return;
      }
      G.audio.sfx('click'); G.vibrate(30);
      chestProp.setModel('chest_open');
      G.flags.chestOpened = true;
      await G.pickup('chest_key');
      if (!G.has('rune_map')) {
        await G.wait(0.4);
        await G.pickup('rune_map');
      }
      addClue('c5_rune_map');
      say('Ключ и инженерный чертёж переправы у меня. Теперь можно запустить плиту у разрушенного моста.', 4.2);
      G.objective('Подойти к каменной плите у моста и восстановить переправу');
    },
  });
}

// the crossing: the rune plate, the lock, the engineer's sketch and restoring the bridge
function placeCrossing({ G, S, addClue, gD, gN, say }) {
  const [PLX, PLZ] = CR(70.6, 95.7);
  const plateY = gD(PLX, PLZ);
  const plateD = G.place('rune_plate_moss', PLX, plateY, PLZ, 0, { scale: 1.3, mask: 1 });
  G.place('rune_plate', PLX, gN(PLX, PLZ), PLZ, 0, { scale: 1.3, mask: 2 });
  const lockProp = G.place('terminal_lock', PLX, plateY + 0.35, PLZ, 0, { scale: 1.1, mask: 3 });

  G.interact({
    pos: [PLX, plateY + 0.5, PLZ + 0.2], r: 3.0,
    label: () => (!G.flags.terminalUnlocked ? (G.has('chest_key') ? 'Отопереть замок ключом и расчистить мох' : 'Заблокированная каменная плита у моста') : 'Ввести знаки на каменной плите у моста'),
    icon: 'hand', prop: plateD,
    cond: () => G.chapter === 5 && !G.edits.bridge1,
    run: async () => {
      if (!G.flags.terminalUnlocked) {
        if (!G.has('chest_key')) {
          say('Плита заросла мхом и заперта замком. Ключ и чертёж лежат в сундуке дорожников в засыпанной штольне у берега.', 4.5);
          return;
        }
        G.audio.sfx('click'); G.vibrate(40);
        G.flags.terminalUnlocked = true;
        lockProp.show(false);
        plateD.setModel('rune_plate');
        say('Замок снят, мох счищен с каменной плиты. Теперь видны четыре кнопки со знаками.', 3.8);
      }
      const ok = await G.ui.runePuzzle({
        kicker: 'каменная плита у моста',
        title: 'Четыре знака переправы',
        text: 'Инженерный чертёж переправы указывает порядок четырёх знаков (с юга на север). Выберите четыре знака по порядку:',
        solution: ['sun', 'moon', 'wave', 'leaf'],
        solutions: [['sun', 'moon', 'wave', 'leaf']],
      });
      if (ok) {
        G.flags.terminalUnlocked = true;
        lockProp.show(false);
        plateD.setModel('rune_plate');
        await S.restoreBridge();
      }
    },
  });

  const [RMX, RMZ] = CR(71.7, 96.9);
  const runeMap = G.place('item_rune_map', RMX, gN(RMX, RMZ) + 0.03, RMZ, 0.4, { scale: 2.4, mask: 2, pitch: -Math.PI / 2, highlight: true });
  G.interact({
    pos: [RMX, 7.3, RMZ], r: 1.8, world: 'n', label: 'Поднять бумагу', icon: 'hand', cond: () => G.chapter === 5 && !G.has('rune_map'),
    run: async () => { if (await G.pickup('rune_map')) { runeMap.show(false); addClue('c5_rune_map'); say('Старый инженерный набросок переправы.', 3); } },
  });
  S.restoreBridge = async () => {
    G.audio.sfx('success'); G.audio.sfx('rumble', { dur: 1.8 });
    await G.setEdit('bridge1', true);
    G.set('bridgeSolved');
    addClue('c5_bridge_mechanism');
    say('Механизм сработал — широкий настил моста встал на место! Осталось опросить свидетелей у переправы и сделать вывод Пятницы.', 4.5);
    G.objective('Зафиксировать вывод Пятницы на Доске выводов (J) и перейти по мосту на северный берег');
  };
  return { plateD, lockProp, runeMap };
}
