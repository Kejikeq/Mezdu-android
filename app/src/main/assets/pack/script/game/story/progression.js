// Chapter exits and progression rules: what each chapter requires before its exit opens, and the move to the next one
import { CHAPTERS_DATA } from '../chapters_data.js';

export function setupProgression(ctx) {
  const { G, S, gD, say } = ctx;
  // Checks whether the mandatory world progression + Deduction Board conclusion for chapter `ch` are complete
  S.isMandatoryWorldDone = (ch = G.chapter) => {
    switch (ch) {
      case 1: return !!G.edits.ch1Door && G.has('student_pass');
      case 2: return !!G.edits.ch2Door && G.has('wet_photo');
      case 3: return !!G.edits.ch3Door && !!G.flags.ch3GarageInspected;
      case 4: return !!G.edits.ch4Door && G.has('guestbook_page');
      case 5: return !!G.edits.bridge1 || !!G.flags.bridgeSolved;
      case 6: return G.has('letter_full') && G.has('photo_2') && G.has('locket');
      case 7: return G.has('map_combined') && G.has('photo_3');
      case 8: return G.has('license_plate') && G.has('metal_shard');
      case 9: return !!G.edits.grate && !!G.edits.tunnelWall;
      case 10: return G.has('car_key');
      default: return false;
    }
  };

  S.isChapterExitReady = (ch = G.chapter) => {
    if (ch >= 10) return S.isMandatoryWorldDone(10);
    const hasConc = !!(G.memoryBoard && G.memoryBoard.getConclusion(ch));
    return S.isMandatoryWorldDone(ch) && hasConc;
  };

  S.onConclusionLocked = (ch, vector) => {
    const react = {
      TRUTH: 'Память обретает резкость. Сквозь туман сна проступает горькая, но честная картина.',
      DENIAL: 'Сознание выбирает покой. Тревожные детали отступают, уступая место мягкому свету.',
      PROJECTION: 'Подозрение пускает корни. Теперь каждая улика кажется частью чужого замысла.',
    }[vector] || 'Вывод зафиксирован в дневнике.';
    say(react, 4.0);
    if (S.isMandatoryWorldDone(ch) && ch < 10) {
      G.objective(`Вывод главы зафиксирован. Пройдите к выходу из локации или нажмите «Перейти к Главе ${ch + 1}» в Дневнике (J).`);
    }
  };

  // Smooth one-shot transition to the next chapter location
  S.advanceToChapter = async (nextCh) => {
    if (G.TransitioningChapter || nextCh < 1 || nextCh > 10) return;
    G.TransitioningChapter = true;
    G.lock(true);
    S.sitting = null;
    G.player.seat = null;
    G.player.lockPose = false;
    G.player.pose = 'idle';
    G.ui.hud(false);
    G.ui.cinema(true);

    const cd = CHAPTERS_DATA[nextCh] || CHAPTERS_DATA[1];
    const prof = G.memoryBoard ? G.memoryBoard.getProfile() : { dominant: 'TRUTH', total: 0 };

    // Play-Along narrative bridge line before entering the new chapter
    const bridgeLines = {
      TRUTH: `Шаг за шагом я приближаюсь к тому, что действительно случилось в ту неделю…`,
      DENIAL: `Ничего страшного не произошло. Нужно просто прожить эту неделю спокойно…`,
      PROJECTION: `Кто-то вёл меня по этому маршруту с самого начала. Я найду все улики…`,
    };
    if (prof.total > 0) {
      say(bridgeLines[prof.dominant] || bridgeLines.TRUTH, 3.2);
      await G.wait(1.2);
    }

    await G.fade(1, 0.9);
    G.voidMode = false;
    G.shadow.visible = false;
    G.heartOverride = 0;
    G.headache = 0;
    G.duality.base = nextCh >= 9 ? 1 : 0;
    G.duality.wave.active = false;
    G.duality.nightTimer = 0;
    G.duality.flicker = 0;
    G.duality.stability = Math.max(75, G.duality.stability);

    G.chapter = nextCh;
    // One-shot generation & cache of the entire chapter location
    if (G.streamer && G.streamer.loadChapter) {
      await G.streamer.loadChapter(nextCh);
    } else if (G.streamer) {
      await G.streamer.burst(cd.spawn[0], cd.spawn[1], 44);
    }

    S.applyChapter(nextCh);
    const sp = cd.spawn;
    const py = G.placeSafe(sp[0], nextCh === 1 ? 10.75 : gD(sp[0], sp[1]), sp[1], sp[2] ?? Math.PI);
    G.player.camYaw = sp[2] ?? Math.PI;
    G.player.camDistCur = G.player.camDist;
    G.player.updateCamera(0.016, null, G.world, G.duality.base ? 1 : 0, G.settings.sens, G.settings.invertY, null);

    await G.wait(0.4);
    await G.fade(0, 1.5);
    await G.ui.chapterCard(cd.kicker, cd.title, 2.8);
    G.ui.cinema(false);
    G.ui.hud(true);
    G.lock(false);
    G.TransitioningChapter = false;
    G.checkpoint('ch' + nextCh, [sp[0], py, sp[1]], sp[2] ?? Math.PI, cd.sceneName);
  };

  // Helper for Chapter Exit Gateways (doors / archways / trail exits)
  const registerChapterExit = (ch, pos, labelOpen, labelLocked) => {
    G.interact({
      pos, r: 2.8, world: 'any',
      label: () => (S.isChapterExitReady(ch) ? labelOpen : labelLocked),
      icon: 'door',
      cond: () => G.chapter === ch,
      run: async () => {
        if (!S.isMandatoryWorldDone(ch)) {
          const cd = CHAPTERS_DATA[ch];
          say(cd ? cd.mandatoryGateHint : 'Сначала нужно осмотреть ключевые предметы в этой локации.', 4.2);
          return;
        }
        if (!G.memoryBoard.getConclusion(ch)) {
          say('Прежде чем покинуть это место, нужно связать улики и показания на Доске выводов в дневнике.', 4.0);
          await G.wait(0.4);
          await G.memoryBoard.openBoard('current');
          return;
        }
        await S.advanceToChapter(ch + 1);
      },
    });
  };
  return { registerChapterExit };
}
