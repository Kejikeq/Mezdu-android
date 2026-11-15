// NPC dialogue and the play-along system: real and phantom witnesses of chapters 1-9
import { CHAPTERS_DATA } from '../chapters_data.js';

export function setupDialogue(ctx) {
  const { G, addTestimony, gD, gN, pl, voice } = ctx;
  const openNpcDialog = (npc) => runNpcDialog(ctx, npc);
  // Registers interactive handlers for all Real & Phantom NPCs across Chapters 1..9
  for (let ch = 1; ch <= 9; ch++) {
    const cd = CHAPTERS_DATA[ch];
    if (!cd || !cd.npcs) continue;
    for (const npc of cd.npcs) {
      const [nx, nz] = npc.pos;
      const ny = npc.y !== undefined ? npc.y : (npc.world === 'n' ? gN(nx, nz) : gD(nx, nz));
      G.interact({
        pos: [nx, ny + 1.0, nz],
        r: 2.5,
        world: npc.world || 'any',
        label: () => `Поговорить: ${npc.name}`,
        icon: 'hand',
        cond: () => G.chapter === ch,
        run: async () => {
          if (npc.dialogTree) {
            await openNpcDialog(npc);
            return;
          }
          G.lock(true);
          const p = pl();
          G.player.yaw = Math.atan2(nx - p[0], nz - p[2]);
          for (const [line, speaker] of npc.lines) {
            voice(line, 4.2, speaker || npc.name);
            await G.wait(3.8);
          }
          // Play-Along adaptive remark if player already formed conclusions in earlier chapters
          const prof = G.memoryBoard ? G.memoryBoard.getProfile() : { total: 0, dominant: 'TRUTH' };
          if (prof.total > 0) {
            if (npc.type === 'real' && prof.dominant === 'DENIAL') {
              voice('«Ты улыбаешься так, будто ничего не случилось… Но от правды не спрятаться во сне, Элиас».', 3.8, npc.name);
              await G.wait(3.5);
            } else if (npc.type === 'real' && prof.dominant === 'PROJECTION') {
              voice('«Зачем ты ищешь заговор там, где была наша общая беда? Михаил не враг тебе».', 3.8, npc.name);
              await G.wait(3.5);
            } else if (npc.type === 'phantom_denial' && prof.dominant === 'DENIAL') {
              voice('«Вот видишь, ты и сам уже понимаешь, как здесь спокойно. Продолжай держаться за этот светлый день».', 3.8, npc.name);
              await G.wait(3.5);
            } else if (npc.type === 'phantom_projection' && prof.dominant === 'PROJECTION') {
              voice('«Твои прежние догадки подтверждаются! Ты правильно делаешь, что не веришь его оправданиям».', 3.8, npc.name);
              await G.wait(3.5);
            }
          }
          if (npc.testimony) {
            addTestimony(npc.testimony.id);
          }
          G.lock(false);
          if (G.memoryBoard && G.memoryBoard.getChapterClues(ch).length > 0 && !G.memoryBoard.getConclusion(ch)) {
            G.objective('Откройте «Выводы» (J / кнопка сверху), чтобы связать улику и показание');
          }
        },
      });
    }
  }
}

// Interactive branching dialogue runner with story narration and question choices; resolves when it closes.
// The logic is here, the window is the client's: G.ui.dialog(view) shows a view and returns the player's choice
// ({ ask: index } | { record: true } | { leave: true }) — the web (ui.js) and the native client draw it.
async function runNpcDialog({ G, addTestimony, pl }, npc) {
  G.lock(true);
  const p = pl();
  G.player.yaw = Math.atan2(npc.pos[0] - p[0], npc.pos[1] - p[2]);
  const dt = npc.dialogTree;
  let currentSpeech = dt.greeting;
  let currentContext = dt.context;
  const askedQuestions = new Set();
  let testimonyRecorded = npc.testimony ? G.memoryBoard.hasTestimony(npc.testimony.id) : false;
  for (;;) {
    const act = await G.ui.dialog({
      role: npc.role, name: npc.name, context: currentContext, speech: currentSpeech,
      questions: dt.questions.map((qObj, idx) => ({ q: qObj.q, asked: askedQuestions.has(idx) })),
      testimony: npc.testimony ? (testimonyRecorded ? 'recorded' : 'offer') : null,
    });
    if (act && act.ask !== undefined && dt.questions[act.ask]) {
      const qObj = dt.questions[act.ask];
      askedQuestions.add(act.ask);
      currentSpeech = qObj.a;
      currentContext = `Элиас спрашивает: ${qObj.q}`;
      G.audio.sfx('paper');
      continue;
    }
    if (act && act.record) {
      if (npc.testimony && !testimonyRecorded) {
        addTestimony(npc.testimony.id);
        testimonyRecorded = true;
        G.audio.sfx('success');
        G.ui.toast(`Записано показание: ${npc.name}`);
      }
      continue;
    }
    break;
  }
  G.lock(false);
  if (G.memoryBoard && G.memoryBoard.getChapterClues(G.chapter).length > 0 && !G.memoryBoard.getConclusion(G.chapter)) {
    G.objective('Откройте «Выводы» (J / кнопка сверху), чтобы связать улику и показание');
  }
}
