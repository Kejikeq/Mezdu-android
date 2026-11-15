// CHAPTER 2: ВТОРНИК — КРАСНЫЙ СВЕТ (Archive & Darkroom)
import { P } from '../../world/layout.js';
import { m } from './common.js';

export function setupChapter2(ctx) {
  const { G, adapt, addClue, gD, registerChapterExit, say } = ctx;
  const CH2_B = P.ch2Lab;
  const ch2FloorY = 7.5;
  const ch2DoorX = m(CH2_B.door + 1), ch2DoorZ = m(CH2_B.z0);
  // Red darkroom light inside + warm courtyard lantern outside
  G.light({ pos: [m(400), 9.2, m(1920)], r: 10, col: [1.0, 0.12, 0.08], k: 2.8, mask: 3, flicker: true });
  G.place('lantern_post', m(400), gD(m(400), m(1884)), m(1884), 0, { mask: 3 });
  G.light({ pos: [m(400), gD(m(400), m(1884)) + 2.2, m(1884)], r: 7.5, col: [1, 0.76, 0.44], k: 2.0, mask: 3 });
  // Archive cabinet by courtyard entrance + Darkroom tables inside
  G.place('drawers', m(395), gD(m(395), m(1903)), m(1903), 0, { mask: 3 });
  const ch2KeyProp = G.place('item_rusty_key', m(395), gD(m(395), m(1903)) + 0.88, m(1903), 0.5, { mask: 3, scale: 2.4, highlight: true });
  G.place('table', m(400), ch2FloorY, m(1922), 0, { mask: 3 });
  G.place('bookshelf', m(392.5), ch2FloorY, m(1920), Math.PI / 2, { mask: 3 });
  G.place('bookshelf', m(407.5), ch2FloorY, m(1920), -Math.PI / 2, { mask: 3 });
  const ch2PhotoProp = G.place('item_photo_2', m(400), ch2FloorY + 0.65, m(1922), 0.1, { mask: 3, scale: 2.3, pitch: -Math.PI / 2, highlight: true });
  const ch2DoorOpenProp = G.place('door_open', ch2DoorX - 0.5, ch2FloorY, ch2DoorZ - 0.25, Math.PI / 2, { mask: 3, visible: false });

  // Mandatory 2A: Archive cabinet & route logbook outside the darkroom
  G.interact({
    pos: [m(395), gD(m(395), m(1903)) + 0.8, m(1903)], r: 2.3, world: 'any',
    label: 'Картотека архива: забрать ключ от проявочной и сверить журнал',
    icon: 'key', prop: ch2KeyProp,
    cond: () => G.chapter === 2 && !G.has('darkroom_key'),
    run: async () => {
      if (await G.pickup('darkroom_key', { kicker: 'картотека архива карт' })) {
        ch2KeyProp.show(false);
        addClue('c2_darkroom_key');
        say(adapt({
          default: 'В журнале выдачи карт стоит моя подпись: «Верхний карниз у водопада». Ключ от фотолаборатории у меня.',
          TRUTH: 'Значит, Павел прав — это я настоял на опасной дороге над водопадом.',
          DENIAL: 'Обычная запись в студенческом журнале. Ничего тревожного.',
          PROJECTION: 'Почерк в строке маршрута странно дрожит — будто кто-то вписал карниз позже.',
        }), 4.4);
        G.objective('Отопереть дверь фотолаборатории ключом и проявить снимок в красном свете');
      }
    },
  });

  // Mandatory Gate 2: Darkroom Door
  G.interact({
    pos: [ch2DoorX, ch2FloorY + 0.8, ch2DoorZ - 0.5], r: 2.3, world: 'any',
    label: () => (G.has('darkroom_key') ? 'Отпереть фотолабораторию ключом архива' : 'Запертая дверь фотолаборатории (нужен ключ из картотеки)'),
    icon: 'door',
    cond: () => G.chapter === 2 && !G.edits.ch2Door,
    run: async () => {
      if (!G.has('darkroom_key')) {
        G.audio.sfx('click');
        say('Дверь проявочной заперта. Ключ должен быть в картотеке архива слева от входа.', 3.8);
        return;
      }
      G.audio.sfx('door');
      await G.setEdit('ch2Door', true);
      ch2DoorOpenProp.show(true);
      say('Дверь открылась. Внутри горит багровый лабораторный фонарь.', 3.8);
      G.objective('Проявить снимок на центральном столе фотолаборатории');
    },
  });

  // Mandatory 2B: Developing tray inside the Red-Light Darkroom
  G.interact({
    pos: [m(400), ch2FloorY + 0.8, m(1922)], r: 2.4, world: 'any',
    label: 'Ванночка с проявителем: проявить снимок в красном свете',
    icon: 'photo', prop: ch2PhotoProp,
    cond: () => G.chapter === 2 && !G.has('wet_photo'),
    run: async () => {
      G.audio.sfx('splash');
      if (await G.pickup('wet_photo', {
        kicker: 'красный свет проявочной',
        desc: adapt({
          default: 'На мокрой фотобумаге проступает силуэт нашего универсала у края скалы над водопадом. На обороте проступают цифры «7319».',
          TRUTH: 'Кадр, ради которого я гнал машину в горы… На обороте проступил номер нашего кузова: 7319.',
          DENIAL: 'Просто учебный этюд горного пейзажа для кафедральной выставки.',
          PROJECTION: 'На кальке рядом со снимком видно, как кто-то жирным штрихом переправил безопасный брод на обрыв.',
        }),
      })) {
        ch2PhotoProp.show(false);
        addClue('c2_wet_photo');
        say('Снимок проявлен. Теперь нужно сопоставить улики со словами свидетелей на Доске выводов (J).', 4.2);
        G.objective('Сделать вывод Вторника в Дневнике (J) и пройти к северному выходу из лаборатории');
      }
    },
  });

  // Optional Clues 2C & 2D inside the Darkroom
  G.interact({
    pos: [m(393), ch2FloorY + 0.8, m(1920)], r: 2.1, world: 'any',
    label: 'Полка: осмотреть треснувший светофильтр (опц.)',
    icon: 'eye',
    cond: () => G.chapter === 2 && !G.memoryBoard.hasClue('c2_broken_lens'),
    run: async () => {
      await G.inspect('item_locket', 'Треснувший светофильтр', 'Стекло объектива расколото паутиной трещин, а на оправе застряли песчинки со дна реки.', 'полка лаборатории');
      addClue('c2_broken_lens');
    },
  });
  G.interact({
    pos: [m(407), ch2FloorY + 0.8, m(1920)], r: 2.1, world: 'any',
    label: 'Стенд: проверить штормовой барометр (опц.)',
    icon: 'eye',
    cond: () => G.chapter === 2 && !G.memoryBoard.hasClue('c2_barometer'),
    run: async () => {
      await G.inspect('item_rune_map', 'Сводка штормового барометра', 'Метеорологическая лента предупреждает о грозовом фронте и размыве дорог в Северном ущелье.', 'метеостенд');
      addClue('c2_barometer');
    },
  });

  // Chapter 2 Exit Gateway (north of Darkroom)
  registerChapterExit(
    2,
    [m(400), gD(m(400), m(1944)) + 1.0, m(1944)],
    'Выход из корпуса: отправиться к перрону и мастерской (Глава 3 →)',
    'Северный выход корпуса (проявите снимок и зафиксируйте вывод Вторника в Дневнике)'
  );
  return { ch2KeyProp, ch2PhotoProp, ch2DoorOpenProp };
}
