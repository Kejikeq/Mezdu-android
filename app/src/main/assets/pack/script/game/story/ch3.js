// CHAPTER 3: СРЕДА — ПЕРРОН И МАСТЕРСКАЯ
import { P } from '../../world/layout.js';
import { m } from './common.js';

export function setupChapter3(ctx) {
  const { G, adapt, addClue, gD, night, registerChapterExit, say } = ctx;
  const CH3_G = P.ch3Garage;
  const ch3PlatY = 7.25;
  const ch3FloorY = 7.5;
  const ch3DoorX = m(CH3_G.door + 4), ch3DoorZ = m(CH3_G.z0);
  // Platform & Garage lights & props (platform floor top surface is y = 58 * 0.125 = 7.25m)
  G.place('lantern_post', m(674), ch3PlatY, m(2126), 0, { mask: 3 });
  G.light({ pos: [m(674), ch3PlatY + 2.2, m(2126)], r: 8, col: [1, 0.76, 0.44], k: 2.0, mask: 3 });
  G.light({ pos: [m(680), 9.2, m(2184)], r: 9, col: [0.95, 0.75, 0.45], k: 2.2, mask: 3 });
  G.place('drawers', m(668), ch3PlatY, m(2134), Math.PI / 2, { mask: 3 });
  const ch3KeyProp = G.place('item_car_key', m(668), ch3PlatY + 0.88, m(2134), 0.4, { mask: 3, scale: 2.5, highlight: true });
  G.place('bench', m(688), ch3PlatY, m(2132), -Math.PI / 2, { mask: 3 });
  const ch3TicketProp = G.place('item_bear_note', m(688), ch3PlatY + 0.46, m(2132), 0.2, { mask: 3, scale: 2.0, highlight: true });
  G.place('workbench', m(680), ch3FloorY, m(2188), 0, { mask: 3 });
  const ch3WrenchProp = G.place('tool_crowbar', m(682.5), ch3FloorY + 0.86, m(2188), 0.5, { mask: 3, scale: 1.2 });
  const ch3DoorOpenProp = G.place('door_open', ch3DoorX - 0.5, ch3FloorY, ch3DoorZ - 0.25, Math.PI / 2, { mask: 3, visible: false });

  // Mandatory 3A: Spare garage key at the train platform
  G.interact({
    pos: [m(668), ch3PlatY + 0.88, m(2134)], r: 2.4, world: 'any',
    label: 'Железный шкафчик на перроне: достать запасной ключ от гаража',
    icon: 'key', prop: ch3KeyProp,
    cond: () => G.chapter === 3 && !G.has('garage_key'),
    run: async () => {
      if (await G.pickup('garage_key', { kicker: 'тайник у колонны перрона' })) {
        ch3KeyProp.show(false);
        addClue('c3_garage_key');
        say('Тяжёлый ключ от мастерской Михаила. На металлической бирке выбито «7319».', 4.0);
        G.objective('Открыть дверь гаража-мастерской Михаила к югу от перрона');
      }
    },
  });

  // Optional 3B: Unused train ticket on platform bench
  G.interact({
    pos: [m(688), ch3PlatY + 0.6, m(2132)], r: 2.2, world: 'any',
    label: 'Скамья перрона: взять неиспользованный ж/д билет (опц.)',
    icon: 'hand', prop: ch3TicketProp,
    cond: () => G.chapter === 3 && !G.has('train_ticket'),
    run: async () => {
      if (await G.pickup('train_ticket', { kicker: 'скамья на перроне' })) {
        ch3TicketProp.show(false);
        addClue('c3_train_ticket');
        say('Билеты на утренний поезд… Мы могли добраться по железной дороге, но почему-то поехали на машине.', 4.2);
      }
    },
  });

  // Mandatory Gate 3: Garage Door
  G.interact({
    pos: [ch3DoorX, ch3FloorY + 0.8, ch3DoorZ - 0.5], r: 2.4, world: 'any',
    label: () => (G.has('garage_key') ? 'Отпереть ворота мастерской Михаила' : 'Запертая мастерская Михаила (ключ в ящике у перрона)'),
    icon: 'door',
    cond: () => G.chapter === 3 && !G.edits.ch3Door,
    run: async () => {
      if (!G.has('garage_key')) {
        G.audio.sfx('click');
        say('Ворота мастерской заперты. Михаил всегда прятал запасной ключ у колонны старого перрона.', 4.0);
        return;
      }
      G.audio.sfx('door');
      await G.setEdit('ch3Door', true);
      ch3DoorOpenProp.show(true);
      say('Замок поддался. Внутри гаража непривычно пусто — машины на месте нет.', 4.0);
      G.objective('Осмотреть верстак и следы на полу внутри мастерской Михаила');
    },
  });

  // Mandatory 3C: Empty parking spot & workbench inside Michael's garage
  G.interact({
    pos: [m(680), ch3FloorY + 0.8, m(2188)], r: 2.5, world: 'any',
    label: 'Верстак в гараже: осмотреть аптечку, следы масла и записку',
    icon: 'eye',
    cond: () => G.chapter === 3 && !G.flags.ch3GarageInspected,
    run: async () => {
      G.flags.ch3GarageInspected = true;
      addClue('c3_oil_stain');
      await G.read([
        '«Элиас, меня с самого обеда бьёт озноб, температура под тридцать девять.',
        'Я подтянул трос тормоза как смог. Ключи оставляю тебе — веди машину сам, только, прошу, не гони ночью по мокрому серпантину».',
      ], night(), '— Михаил, среда');
      say(adapt({
        default: 'У Михаила был сильный жар… Значит, начиная со среды за рулём нашего универсала сидел я.',
        TRUTH: 'Сосед Игнат сказал правду: Михаил доверил машину мне, потому что сам едва стоял на ногах.',
        DENIAL: 'Машину просто отогнали на плановую проверку. Ничего страшного не случилось.',
        PROJECTION: 'А что если эта записка о болезни — лишь предлог, чтобы усадить меня за руль неисправной машины?',
      }), 4.5);
      G.objective('Сделать вывод Среды на Доске выводов (J) и выйти к выезду на ночное шоссе');
    },
  });

  // Optional 3D: Wrench & brake cable on garage floor
  G.interact({
    pos: [m(684.5), ch3FloorY + 0.6, m(2185)], r: 2.1, world: 'any',
    label: 'Осмотреть тормозной трос и инструмент (опц.)',
    icon: 'eye', prop: ch3WrenchProp,
    cond: () => G.chapter === 3 && !G.memoryBoard.hasClue('c3_wrench'),
    run: async () => {
      await G.inspect('tool_crowbar', 'Инструмент у смотровой ямы', 'Следы свежей смазки: тормозной контур пытались отрегулировать в последнюю минуту перед выездом.', 'мастерская');
      addClue('c3_wrench');
    },
  });

  // Chapter 3 Exit Gateway (south of Garage toward Highway)
  registerChapterExit(
    3,
    [m(680), gD(m(680), m(2204)) + 1.0, m(2204)],
    'Выезд из кооператива: выехать на ночное шоссе к мотелю (Глава 4 →)',
    'Выезд на шоссе (осмотрите верстак в гараже и зафиксируйте вывод Среды в Дневнике)'
  );
  return { ch3KeyProp, ch3TicketProp, ch3DoorOpenProp };
}
