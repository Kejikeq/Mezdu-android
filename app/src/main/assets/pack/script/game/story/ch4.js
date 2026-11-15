// CHAPTER 4: ЧЕТВЕРГ — НОЧНОЕ ШОССЕ И МОТЕЛЬ «ПОВОРОТ»
import { P } from '../../world/layout.js';
import { m } from './common.js';

export function setupChapter4(ctx) {
  const { G, adapt, addClue, gD, registerChapterExit, say, voice } = ctx;
  const CH4_M = P.ch4Motel;
  const ch4FloorY = 7.5;
  const ch4DoorX = m(CH4_M.door + 1), ch4DoorZ = m(CH4_M.z0);
  // Gas station & Motel lights & props
  G.place('lantern_post', m(674), gD(m(674), m(1904)), m(1904), 0, { mask: 3 });
  G.light({ pos: [m(674), gD(m(674), m(1904)) + 2.2, m(1904)], r: 8.5, col: [1, 0.78, 0.45], k: 2.1, mask: 3 });
  G.light({ pos: [m(680), 9.2, m(1944)], r: 9.0, col: [1, 0.68, 0.36], k: 2.2, mask: 3 });
  const ch4KeyProp = G.place('item_rusty_key', m(680), gD(m(680), m(1904)) + 0.55, m(1904), 0.3, { mask: 3, scale: 2.5, highlight: true });
  G.place('sofa', m(674.5), ch4FloorY, m(1946), Math.PI / 2, { mask: 3 });
  G.place('table', m(684.5), ch4FloorY, m(1944), 0, { mask: 3 });
  const ch4BookProp = G.place('item_letter_full', m(684.5), ch4FloorY + 0.65, m(1944), 0.2, { mask: 3, scale: 2.2, pitch: -Math.PI / 2, highlight: true });
  const ch4RadioProp = G.place('item_cassette', m(674.5), ch4FloorY + 0.65, m(1940), 0.4, { mask: 3, scale: 2.0, highlight: true });
  const ch4DoorOpenProp = G.place('door_open', ch4DoorX - 0.5, ch4FloorY, ch4DoorZ - 0.25, Math.PI / 2, { mask: 3, visible: false });

  // Mandatory 4A: Gas Station fusebox & Room 4 key
  G.interact({
    pos: [m(680), gD(m(680), m(1904)) + 0.8, m(1904)], r: 2.4, world: 'any',
    label: 'Щиток бензоколонки: подать питание и забрать ключ от Номера 4',
    icon: 'key', prop: ch4KeyProp,
    cond: () => G.chapter === 4 && !G.has('motel_key'),
    run: async () => {
      G.audio.sfx('click');
      if (await G.pickup('motel_key', { kicker: 'колонка АЗС' })) {
        ch4KeyProp.show(false);
        addClue('c4_motel_key');
        say('Латунный брелок «Мотель Поворот · Номер 4». На квитанции колонки — полный бак бензина, залитый в четверг ближе к полуночи.', 4.4);
        G.objective('Открыть дверь Номера 4 мотеля к югу от заправки');
      }
    },
  });

  // Optional 4B: Payphone coin by the gas station pillar
  G.interact({
    pos: [m(686), gD(m(686), m(1904)) + 0.8, m(1904)], r: 2.2, world: 'any',
    label: 'Таксофон у АЗС: осмотреть возврат монет (опц.)',
    icon: 'eye',
    cond: () => G.chapter === 4 && !G.memoryBoard.hasClue('c4_payphone_coin'),
    run: async () => {
      await G.inspect('item_locket', 'Междугородний таксофон', 'В лотке остался жетон. С этого аппарата в четверг вечером звонили домой, обещая вернуться к воскресенью.', 'таксофон у трассы');
      addClue('c4_payphone_coin');
    },
  });

  // Mandatory Gate 4: Motel Room 4 Door
  G.interact({
    pos: [ch4DoorX, ch4FloorY + 0.8, ch4DoorZ - 0.5], r: 2.4, world: 'any',
    label: () => (G.has('motel_key') ? 'Отпереть дверь Номера 4 ключом с ромбом' : 'Дверь Номера 4 мотеля «Поворот» (ключ у щитка АЗС)'),
    icon: 'door',
    cond: () => G.chapter === 4 && !G.edits.ch4Door,
    run: async () => {
      if (!G.has('motel_key')) {
        G.audio.sfx('click');
        say('Четвёртый номер заперт. Ключ на латунном ромбе висит у щитка под навесом АЗС.', 3.8);
        return;
      }
      G.audio.sfx('door');
      await G.setEdit('ch4Door', true);
      ch4DoorOpenProp.show(true);
      say('Дверь четвёртого номера открылась. Постель внутри даже не разобрана — будто мы уехали в ту же ночь.', 4.2);
      G.objective('Осмотреть журнал постояльцев на столе внутри Номера 4');
    },
  });

  // Mandatory 4C: Guestbook inside Motel Room 4
  G.interact({
    pos: [m(684.5), ch4FloorY + 0.8, m(1944)], r: 2.4, world: 'any',
    label: 'Стол в Номере 4: изучить выписку из книги постояльцев',
    icon: 'read', prop: ch4BookProp,
    cond: () => G.chapter === 4 && !G.has('guestbook_page'),
    run: async () => {
      if (await G.pickup('guestbook_page', { kicker: 'стол в Номере 4' })) {
        ch4BookProp.show(false);
        addClue('c4_guestbook');
        say(adapt({
          default: 'Запись от четверга, 23:40: «Синий универсал 7319. Не остались до утра — выехали в ущелье в самый ливень».',
          TRUTH: 'Дежурный сказал правду: Михаил просил переждать бурю в мотеле, но я завёл мотор и повёл машину в ночь.',
          DENIAL: 'Дежурный наверняка перепутал время. Мы спокойно отдохнули и вышли к реке только утром в пятницу.',
          PROJECTION: 'После того звонка с таксофона атмосфера накалилась — вот почему мы сорвались с места среди ночи.',
        }), 4.6);
        G.objective('Зафиксировать вывод Четверга на Доске выводов (J) и пройти к спуску в речную долину');
      }
    },
  });

  // Optional 4D: Weather radio inside Motel Room 4
  G.interact({
    pos: [m(674.5), ch4FloorY + 0.8, m(1940)], r: 2.1, world: 'any',
    label: 'Тумбочка: включить дорожный радиоприёмник (опц.)',
    icon: 'sound', prop: ch4RadioProp,
    cond: () => G.chapter === 4 && !G.memoryBoard.hasClue('c4_weather_radio'),
    run: async () => {
      G.audio.sfx('click');
      addClue('c4_weather_radio');
      voice('«Внимание водителям: из-за затяжного ливня движение по верхнему карнизу Северного ущелья закрыто…»', 4.4, 'Радиоэфир');
    },
  });

  // Chapter 4 Exit Gateway (south of Motel toward the Valley / Chapter 5)
  registerChapterExit(
    4,
    [m(680), gD(m(680), m(1964)) + 1.0, m(1964)],
    'Шлагбаум долины: спуститься к песчаному берегу ручья (Глава 5 →)',
    'Спуск в горную долину (изучите книгу постояльцев в Номере 4 и зафиксируйте вывод Четверга)'
  );
  return { ch4KeyProp, ch4BookProp, ch4DoorOpenProp };
}
