// Intro: chapter 1, Monday in Elias's apartment
import { CHAPTERS_DATA } from '../chapters_data.js';

export function setupIntro(ctx) {
  const { G, S, START, ch1Floor2Y, say } = ctx;
  S.intro = async () => {
    G.lock(true);
    G.fadeV = 1; G.fadeTo = 1;
    G.ui.domFade(0, 0.3);
    G.chapter = 1;
    const sp = CHAPTERS_DATA[1].spawn;
    const py = G.placeSafe(sp[0], ch1Floor2Y, sp[1], sp[2]);
    const px = G.player.pos[0], pz = G.player.pos[2];
    G.player.pos[1] = py;
    G.player.visY = py;
    G.player.pose = 'idle'; G.player.lockPose = false;

    let skipped = false;
    G.ui.cinema(true);
    G.ui.skipButton(() => {
      skipped = true;
      G.flushWaits();
    });

    await G.ui.chapterCard(CHAPTERS_DATA[1].kicker, CHAPTERS_DATA[1].title, 2.8);
    if (!skipped) {
      await G.fade(0, 2.0);
      say('Моя спальня… Кажется, сегодня понедельник. Мы с Михаилом только собираемся в экспедицию к Северному перевалу.', 4.5);
      await G.wait(4.2);
    }
    if (!skipped) {
      say('Но почему в воздухе стоит запах сырости и речной воды, а в висках стучит так, словно эта поездка уже случилась?..', 4.2);
      await G.wait(4.0);
    }

    G.ui.skipButton(null);
    G.ui.cinema(false);
    G.fadeV = 0; G.fadeTo = 0;
    G.give('memory_photo', true);
    G.set('eye');
    G.flags.hasWokenUp = true;
    G.lock(false);
    G.checkpoint('start', [px, py, pz], sp[2], CHAPTERS_DATA[1].sceneName);
    G.objective(CHAPTERS_DATA[1].defaultObjective);
  };

  // Rabbit interaction in Chapter 5
  G.interact({
    pos: [0, 0, 0], r: 1.9, world: 'd', label: 'Погладить кролика', icon: 'hand', cond: () => G.chapter === 5 && G.rabbit.visible && !G.flags.rabbitPet && !G.rabbit.target,
    run: async () => {
      G.set('rabbitPet');
      G.audio.sfx('glitch'); G.vibrate(40);
      G.toNight(0.4, { speed: 120, quiet: true });
      G.glitch = 1;
      G.stab(-5);
      await G.wait(0.45);
      G.toDream({ speed: 120, quiet: true });
      say('На долю секунды он стал тенью…', 3.5);
      G.rabbit.speed = 3.4; G.rabbit.target = [START[0] - 2, 0, START[1] - 14];
      G.rabbit.onArrive = () => { G.rabbit.visible = false; };
    },
  });
  const rabbitIt = G.interactables[G.interactables.length - 1];
  G.onUpdate(() => { rabbitIt.pos = [G.rabbit.pos[0], G.rabbit.pos[1] + 0.3, G.rabbit.pos[2]]; });
}
