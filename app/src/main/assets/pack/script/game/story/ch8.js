// CHAPTER 8: СУББОТА, ВЕЧЕР — ВЕРХОВЬЕ РУЧЬЯ И ОБРЫВ
import { UPA, m } from './common.js';
import { P } from '../../world/layout.js';

export function setupChapter8(ctx) {
  const { G, S, addClue, gD, gN, night, pl, registerChapterExit, say } = ctx;
  const carPartY = Math.max(gD(UPA.x(22.6), UPA.z(46.3)), 7.02);
  const plateY2 = Math.max(gN(UPA.x(22.5), UPA.z(46.9)), 6.90);
  G.place('car_part', UPA.x(22.6), carPartY, UPA.z(46.3), 0.6, { mask: 1, pitch: -0.5, scale: 1.7 });
  const plate = G.place('item_license_plate', UPA.x(22.5), plateY2, UPA.z(46.9), 1.4, { mask: 2, pitch: -0.6, scale: 1.6, highlight: true });
  G.place('debris', UPA.x(25.2), gN(...UPA(25.2, 48.4)), UPA.z(48.4), 0.4, { mask: 2 });
  const shard = G.place('item_metal_shard', UPA.x(25.8), gN(...UPA(25.8, 47.7)) + 0.04, UPA.z(47.7), 0.8, { mask: 2, pitch: -Math.PI / 2, scale: 3, highlight: true });

  G.interact({
    pos: [UPA.x(22.8), 7.5, UPA.z(46.6)], r: 2.4, world: 'd',
    label: 'Осмотреть сорванный колпак колеса на дне (опц.)',
    icon: 'eye',
    cond: () => G.chapter === 8,
    run: async () => {
      await G.inspect('car_part', 'Сорванный колпак колеса', 'Колпак колеса с остатками стёртой шины на дне горного ручья.', 'дно ручья');
      addClue('c8_wheel_cap');
    },
  });
  G.interact({
    pos: [UPA.x(25.2), 7.6, UPA.z(44.6)], r: 2.4, world: 'd',
    label: 'Посмотреть в воду ручья',
    icon: 'eye',
    cond: () => G.chapter === 8 && !G.flags.reflection,
    run: () => S.reflection(),
  });
  S.reflection = async () => {
    G.lock(true);
    const p = pl();
    G.camOverride = { pos: [p[0] + 0.4, p[1] + 2.0, p[2] + 0.6], target: [p[0] - 1.6, p[1] - 0.3, p[2] - 0.2] };
    say('В воде — отражение. Я. Только я.', 3); await G.wait(3);
    G.toNight(15, { force: true, speed: 70 });
    const bx = p[0] + Math.sin(G.player.yaw) * -1.2, bz = p[2] + Math.cos(G.player.yaw) * -1.2;
    Object.assign(G.shadow, { visible: true, pos: [bx, p[1], bz], yaw: G.player.yaw, pose: 'stand_still', mask: 2 });
    G.audio.sfx('heart'); G.heartOverride = 0.9;
    say('…За моей спиной кто-то стоит.', 2.6); await G.wait(2.6);
    G.audio.sfx('glitch'); G.glitch = 1.4;
    await G.wait(0.25);
    G.camOverride = null; G.player.camYaw += Math.PI; G.shadow.visible = false;
    G.heartOverride = 0;
    G.set('reflection');
    addClue('c8_metal_shard');
    G.lock(false);
  };
  G.interact({
    pos: [UPA.x(23.1), 7.5, UPA.z(47.1)], r: 2.7, world: 'any',
    label: () => (!night() ? 'Вглядеться в чёрную воду (R / Глаз), чтобы достать номер' : (G.flashOn ? 'Достать погнутый номер «7319» со дна' : 'Включить фонарик (F) и достать номер со дна')),
    icon: 'flash', cond: () => G.chapter === 8 && !G.has('license_plate'), prop: plate,
    run: async () => {
      if (!night()) {
        G.peering = true;
        G.toNight(22, { force: true, speed: 45 });
        await G.wait(0.5);
      }
      if (!G.has('broken_flashlight')) G.give('broken_flashlight', true);
      if (!G.flashOn) { G.flashOn = true; G.refreshTools(); }
      say('Луч фонарика выхватывает буквы и цифры под водой…', 2.5); await G.wait(1.2);
      if (await G.pickup('license_plate')) {
        plate.show(false);
        addClue('c8_license_plate');
        say('Номерной знак «7319». Вторая цифра — тройка.', 4.5);
      }
    },
  });
  G.interact({
    pos: [UPA.x(25.8), 7.6, UPA.z(47.7)], r: 2.4, world: 'any',
    label: 'Поднять стальной обломок капота',
    icon: 'hand', cond: () => G.chapter === 8 && !G.has('metal_shard'), prop: shard,
    run: async () => {
      if (!night()) {
        G.peering = true;
        G.toNight(18, { force: true, speed: 45 });
        await G.wait(0.4);
      }
      if (await G.pickup('metal_shard')) {
        shard.show(false);
        addClue('c8_metal_shard');
        say('Искорёженная сталь со следами удара о береговые валуны.', 3.8);
      }
    },
  });

  // Cliff & Chapter 8 Exit Gateway
  const CL = [m(P.cliff[0]), m(P.cliff[1])];
  registerChapterExit(
    8,
    [CL[0] - 0.5, gD(CL[0] - 0.5, CL[1] - 0.5) + 0.8, CL[1] - 0.5],
    'Скальный карниз: подняться к мосту над пропастью (Глава 9 →)',
    'Скальный обрыв (достаньте номер «7319» и обломок из ручья и зафиксируйте вывод в Дневнике)'
  );
  return { plate, shard, CL };
}
