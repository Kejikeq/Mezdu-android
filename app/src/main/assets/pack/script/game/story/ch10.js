// CHAPTER 10: МЕЖДУ — ПОДЗЕМНЫЙ ГРОТ И ПАЛАТА № 7
import { P } from '../../world/layout.js';
import { NO, m } from './common.js';

export function setupChapter10(ctx) {
  const { G, S, adapt, addClue, pl, say } = ctx;
  const C = P.cave, PL = [m(P.pool.x) + 0.25, m(P.pool.z) + 0.25];
  G.place('car_wreck', PL[0], 8.55, PL[1], 0.5, { mask: 2, roll: Math.PI - 0.12 });
  G.light({ pos: [m(C.x), 11, m(C.z)], r: 15, col: [1, 0.1, 0.05], k: 2.2, mask: 2, cond: () => G.chapter === 10 });
  G.light({ pos: [m(C.x), 12, m(C.z)], r: 12, col: [0.9, 0.85, 0.7], k: 1.2, mask: 1, cond: () => G.chapter === 10 });
  G.light({ pos: [NO.x(92.6), 9, NO.z(7.8)], r: 14, col: [1, 0.96, 0.9], k: 3.5, mask: 3, cond: () => G.chapter === 10 });
  G.light({ pos: [NO.x(61.0), 9.2, NO.z(7.75)], r: 8, col: [0.55, 0.75, 1.0], k: 2.6, mask: 3, cond: () => G.chapter === 10 && G.has('car_key') });
  const carKey = G.place('item_car_key', PL[0], 8.03, PL[1] + 3.6, 0.3, { mask: 3, scale: 3, pitch: -Math.PI / 2, highlight: true, visible: false });

  G.trigger({ pos: [PL[0], 0, PL[1]], r: 5.5, cond: () => G.chapter === 10 && !G.flags.flashback, run: () => S.source() });
  G.interact({
    pos: [PL[0], 8.2, PL[1] + 2.8], r: 3.6, label: 'Посмотреть в зеркальную воду Источника', icon: 'eye', cond: () => G.chapter === 10 && !G.flags.flashback,
    run: () => S.source(),
  });
  S.source = async () => {
    G.set('flashback');
    G.lock(true);
    const p = pl();
    const prof = G.memoryBoard ? G.memoryBoard.getProfile() : { dominant: 'TRUTH', truth: 0, denial: 0, projection: 0 };
    G.camOverride = { pos: [p[0], p[1] + 2.2, p[2] + 1.2], target: [PL[0], 7.2, PL[1]] };
    say('Я смотрю в воду — и вся прошедшая неделя от понедельника до воскресенья складывается в единую картину.', 4.2);
    await G.wait(3.8);

    await G.ui.inspect({
      model: prof.dominant === 'PROJECTION' ? G.models.mike_head_black : G.models.mike_head,
      kicker: 'отражение в воде Источника',
      title: 'Михаил',
      desc: adapt({
        TRUTH: 'Мой лучший друг. В ту ночь у него был жар, но когда машина рухнула в реку, он со сломанной рукой вытащил меня на берег.',
        DENIAL: 'Он спокойно улыбается мне, будто мы всё ещё сидим в университетской лаборатории в тихий понедельник.',
        PROJECTION: 'Его взгляд кажется чужим и холодным — точно таким, каким я рисовал его в своих подозрениях всю дорогу.',
      }),
      buttons: [{ label: 'Вспомнить до конца', primary: true, value: true }],
      tint: [0.85, 0.8, 0.9],
    });

    G.player.pose = 'kneel'; G.player.lockPose = true;
    await G.fade(1, 1.0);
    G.ui.cinema(true);
    G.audio.update({ mode: 'ending' });
    await G.ui.cineLine(adapt({
      TRUTH: 'Четверг, полночь. Я за рулём универсала 7319. Михаил рядом просит сбавить скорость.',
      DENIAL: 'Солнечный лес. Тёплый чай на столе. Никакого дождя и никакого обрыва.',
      PROJECTION: 'Тени у телефонной будки. Исправленные карты. Чужие голоса в ночи.',
    }), 3.6);
    G.audio.sfx('rain', { dur: 5 });
    await G.ui.cineLine('Мокрый карниз над водопадом. Скрежет тормозов.', 2.6);
    G.audio.sfx('crash'); G.vibrate(400);
    await G.ui.cineLine('Ледяная вода ручья — и мерный писк приборов в Палате № 7.', 3.0);
    G.ui.cinema(false);
    G.audio.update({ mode: 'game' });
    G.player.lockPose = false; G.player.pose = 'idle';
    G.camOverride = null;
    carKey.show(true);
    await G.fade(0, 1.8);
    say('У кромки воды блестит ключ зажигания.', 3.5);
    G.lock(false);
    G.objective('Поднять ключ зажигания у воды');
  };

  G.interact({
    pos: [PL[0], 8.4, PL[1] + 3.6], r: 2.0, label: 'Поднять ключ зажигания с брелоком', icon: 'key', cond: () => G.chapter === 10 && G.flags.flashback && !G.has('car_key'), prop: carKey,
    run: async () => {
      if (await G.pickup('car_key')) {
        carKey.show(false);
        addClue('c10_car_key');
        S.showMike();
        const prof = G.memoryBoard ? G.memoryBoard.getProfile() : { dominant: 'TRUTH' };
        say(adapt({
          TRUTH: 'Слева у воды стоит Михаил и протягивает мне руку, чтобы вывести в реальную Палату № 7. Справа — тёплый туман сна.',
          DENIAL: 'Справа сияет тёплый выход обратно в наш безмятежный Понедельник. Слева — голос из холодной больницы.',
          PROJECTION: 'Справа — выход в одиночество, прочь от чужих голосов. Слева у воды ждёт Михаил.',
        }), 5.0);
        G.objective(`Сделать финальный выбор (Ваш профиль памяти: ${prof.dominant === 'TRUTH' ? 'Принятие правды' : prof.dominant === 'DENIAL' ? 'Иллюзия покоя' : 'Отрицание и тень'})`);
      }
    },
  });

  S.showMike = () => Object.assign(G.mike, { visible: true, pos: [NO.x(63.8), 8.0, NO.z(7.75)], yaw: Math.PI / 2, pose: 'reach', reach: 1, mask: 3 });

  // East Portal: Denial ("Вечный Понедельник") or Projection ("Лабиринт Теней") depending on player's memory profile
  G.interact({
    pos: [NO.x(90.5), 8.9, NO.z(7.8)], r: 3.2,
    label: () => {
      const dom = G.memoryBoard ? G.memoryBoard.getProfile().dominant : 'DENIAL';
      return dom === 'PROJECTION'
        ? 'Уйти в тень в одиночку (отвергнуть всех — Концовка Проекции)'
        : 'Шагнуть в тёплый свет иллюзии (вернуться в Вечный Понедельник)';
    },
    icon: 'sun', hold: 1.2,
    cond: () => G.chapter === 10 && G.has('car_key') && !G.flags.ended,
    run: () => {
      const dom = G.memoryBoard ? G.memoryBoard.getProfile().dominant : 'DENIAL';
      if (dom === 'PROJECTION') return S.endingProjection();
      return S.endingDenial();
    },
  });

  // West Portal (Michael): Truth ("Пробуждение в Палате № 7") or Mixed ("Хрупкое Равновесие")
  G.interact({
    pos: [NO.x(63.8), 8.9, NO.z(7.75)], r: 3.0, world: 'any',
    label: () => {
      const prof = G.memoryBoard ? G.memoryBoard.getProfile() : { truth: 5, total: 5 };
      return prof.truth >= prof.denial && prof.truth >= prof.projection
        ? 'Взять Михаила за руку (принять правду и очнуться в Палате № 7)'
        : 'Протянуть руку сквозь сомнения (Хрупкое пробуждение)';
    },
    icon: 'hand', hold: 1.2,
    cond: () => G.chapter === 10 && G.has('car_key') && !G.flags.ended,
    run: () => {
      const prof = G.memoryBoard ? G.memoryBoard.getProfile() : { truth: 5, denial: 0, projection: 0 };
      if (prof.truth >= prof.denial && prof.truth >= prof.projection) return S.endingTruth();
      return S.endingMixed();
    },
  });
  return { carKey };
}
