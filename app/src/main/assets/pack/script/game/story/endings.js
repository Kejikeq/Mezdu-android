// The four adaptive endings, the credits and the epilogue

export function setupEndings(ctx) {
  const { B, G, S, gD } = ctx;
  const credits = async (endingSubtitle) => {
    G.ui.skipButton(null);
    G.fadeCol = [0, 0, 0];
    G.ui.setCinemaLight(false);
    await G.ui.cineLine('<span style="font-size:1.6em;letter-spacing:.2em">МЕЖДУ</span>', 3.2);
    if (endingSubtitle) await G.ui.cineLine(endingSubtitle, 3.0);
    await G.ui.cineLine('10 глав реконструкции памяти · Каждый выбор изменил вашу историю.', 3.4);
    await G.ui.cineLine('Спасибо, что дошли до конца.', 3.0);
  };
  const finish = async () => {
    G.ui.cinema(false);
    G.ui.hud(true);
    await G.ui.domFade(1, 1);
    G.fadeV = 0; G.fadeTo = 0;
    G.resetRun();
    await S.restore();
    G.enterMenu();
    await G.ui.domFade(0, 1.2);
  };

  // Ending 1: TRUTH — «Пробуждение в Палате № 7»
  S.endingTruth = async () => {
    G.ui.hud(false);
    G.set('ended');
    G.lock(true);
    G.player.pose = 'reach'; G.player.lockPose = true;
    G.heartOverride = 0.7;
    await G.wait(1.4);
    await G.fade(1, 2.4, [1, 1, 1]);
    G.ui.cinema(true);
    G.ui.setCinemaLight(true);
    G.audio.update({ mode: 'ending' });
    for (let i = 0; i < 3; i++) { G.audio.sfx('heart'); await G.wait(0.85); }
    G.heartOverride = 0;
    await G.ui.cineLine('Белый потолок Палаты № 7. Мерный ритм кардиомонитора.', 3.2);
    G.audio.sfx('beep', { n: 4 });
    await G.ui.cineLine('Чей-то тёплый голос рядом:<br>«Элиас! Он открыл глаза!»', 3.4);
    await G.ui.cineLine('У окна стоит Михаил с рукой на перевязи и устало, но светло улыбается тебе.', 3.8);
    G.ui.setCinemaLight(false);
    await G.ui.inspect({
      model: G.models.item_photo_final,
      kicker: 'тумбочка в Палате № 7',
      title: 'Прощение и Возвращение',
      desc: 'Ты восстановил подлинную картину всех семи дней, принял свою ответственность за ту ночь и вернулся к тем, кто боролся за твою жизнь.',
      buttons: [{ label: 'Сделать вдох', primary: true, value: true }],
    });
    await credits('Концовка Истины · «Пробуждение в Палате № 7»');
    await S.epilogue();
    await finish();
  };

  // Ending 2: DENIAL — «Вечный Понедельник» (Игра подыгрывает иллюзии покоя)
  S.endingDenial = async () => {
    G.ui.hud(false);
    G.set('ended');
    G.lock(true);
    G.mike.visible = false;
    await G.fade(1, 2.4, [1, 0.96, 0.88]);
    G.ui.cinema(true);
    G.ui.setCinemaLight(true);
    G.audio.update({ mode: 'ending' });
    await G.ui.cineLine('Шум водопада и писк больничных приборов стихают.', 3.2);
    await G.ui.cineLine('Наступает тёплое, солнечное утро понедельника.', 3.2);
    await G.ui.cineLine('На столе в твоей комнате ждёт горячий кофе, а на календаре — вечное начало недели перед поездкой, которая никогда не случится.', 4.2);
    G.ui.setCinemaLight(false);
    await G.ui.inspect({
      model: G.models.item_student_card,
      kicker: 'письменный стол · понедельник',
      title: 'Вечный Понедельник',
      desc: 'Игра приняла твою версию памяти: ты выбрал покой вместо боли, и мир снов бережно замкнул для тебя безмятежное утро.',
      buttons: [{ label: 'Остаться во сне', primary: true, value: true }],
    });
    await credits('Концовка Иллюзии · «Вечный Понедельник»');
    await finish();
  };

  // Ending 3: PROJECTION — «Лабиринт Теней» (Игра подыгрывает паранойе и обвинению)
  S.endingProjection = async () => {
    G.ui.hud(false);
    G.set('ended');
    G.lock(true);
    G.mike.visible = false;
    await G.fade(1, 2.4, [0.08, 0.04, 0.05]);
    G.ui.cinema(true);
    G.ui.setCinemaLight(false);
    G.audio.update({ mode: 'ending' });
    await G.ui.cineLine('Ты отворачиваешься от протянутой руки и уходишь прочь по холодным ступеням.', 3.5);
    await G.ui.cineLine('Ты доказал себе, что во всём виноват чужой умысел — и теперь никто не смеет тебя судить.', 3.8);
    await G.ui.cineLine('Но улицы города пусты, а в каждом тёмном окне за твоей спиной стоит безмолвная тень.', 3.8);
    await G.ui.inspect({
      model: G.models.mike_head_black,
      kicker: 'холодное зеркало',
      title: 'Лабиринт Теней',
      desc: 'Твоя память выстроила безупречную защиту из подозрений, но за стеной недоверия ты остался совершенно один.',
      buttons: [{ label: 'Идти дальше одному', primary: true, value: true }],
    });
    await credits('Концовка Проекции · «Лабиринт Теней»');
    await finish();
  };

  // Ending 4: MIXED — «Хрупкое Равновесие»
  S.endingMixed = async () => {
    G.ui.hud(false);
    G.set('ended');
    G.lock(true);
    await G.fade(1, 2.4, [0.92, 0.94, 0.98]);
    G.ui.cinema(true);
    G.ui.setCinemaLight(true);
    G.audio.update({ mode: 'ending' });
    G.audio.sfx('beep', { n: 3 });
    await G.ui.cineLine('Свет больничной лампы пробивается сквозь лесной туман.', 3.2);
    await G.ui.cineLine('Ты очнулся в Палате № 7, но правда и вымысел в твоей памяти переплелись навсегда.', 3.8);
    G.ui.setCinemaLight(false);
    await G.ui.inspect({
      model: G.models.item_petal_pink,
      kicker: 'на ладони после пробуждения',
      title: 'Хрупкое Равновесие',
      desc: 'Часть недели ты вспомнил честно, а часть — укрыл за защитной иллюзией. Но главное — ты вернулся в мир живых.',
      buttons: [{ label: 'Сохранить в памяти', primary: true, value: true }],
    });
    await credits('Концовка Границы · «Хрупкое Равновесие»');
    await finish();
  };

  S.endingLie = S.endingDenial;

  S.epilogue = async () => {
    G.ui.cinema(false);
    G.ui.setCinemaLight(false);
    G.headache = 0;
    G.chapter = 6; G.duality.baseNight = false; G.duality.base = 0; G.duality.wave.active = false;
    await G.streamer.burst(B[0], B[1], 48);
    await S.sitBench(true);
    const seat = [B[0] - 0.04, gD(...B), B[1]];
    Object.assign(G.mike, { visible: true, pos: [seat[0], seat[1], seat[2] + 0.36], yaw: -Math.PI / 2, pose: 'sit', seat: 'bench', mask: 3 });
    G.player.place(seat[0], seat[1], seat[2] - 0.36, -Math.PI / 2);
    G.player.pose = 'sit';
    G.player.seat = 'bench';
    G.player.lockPose = true;
    S.sitting = 'bench';
    G.camOverride = { pos: [seat[0] - 5.2, seat[1] + 1.75, seat[2] + 2.0], target: [seat[0], seat[1] + 0.88, seat[2]], fov: 0.8 };
    G.audio.update({ mode: 'game' });
    await G.fade(0, 2.8, [1, 1, 1]);
    G.ui.cinema(true);
    await G.ui.cineLine('Тихий лес в воспоминании. Скамейка под деревом.', 3.2);
    await G.ui.cineLine('Двое друзей снова улыбаются без тени вины.', 3.2);
    await G.fade(1, 2.2);
    G.player.lockPose = false;
    G.mike.visible = false; G.camOverride = null;
  };
}
