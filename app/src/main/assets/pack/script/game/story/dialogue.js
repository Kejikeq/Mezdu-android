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

// Interactive branching dialogue runner with story narration and question choices; resolves when it closes
function runNpcDialog({ G, addTestimony, pl }, npc) {
  return new Promise((resolve) => {
    G.lock(true);
    const p = pl();
    G.player.yaw = Math.atan2(npc.pos[0] - p[0], npc.pos[1] - p[2]);
    const dt = npc.dialogTree;
    let currentSpeech = dt.greeting;
    let currentContext = dt.context;
    const askedQuestions = new Set();
    let testimonyRecorded = npc.testimony ? G.memoryBoard.hasTestimony(npc.testimony.id) : false;

    const renderDialog = () => {
      G.ui.panel((c) => {
        const h = document.createElement('header');
        h.innerHTML = `<div><div class="kicker">${npc.role}</div><h2>${npc.name}</h2></div>`;
        const closeBtn = document.createElement('button');
        closeBtn.className = 'round close';
        closeBtn.setAttribute('aria-label', 'Закрыть');
        closeBtn.onclick = () => {
          G.ui.closePanel();
          G.lock(false);
          if (G.memoryBoard && G.memoryBoard.getChapterClues(G.chapter).length > 0 && !G.memoryBoard.getConclusion(G.chapter)) {
            G.objective('Откройте «Выводы» (J / кнопка сверху), чтобы связать улику и показание');
          }
          resolve();
        };
        h.appendChild(closeBtn);
        c.appendChild(h);

        const ctxDiv = document.createElement('div');
        ctxDiv.className = 'note';
        ctxDiv.style.fontStyle = 'italic';
        ctxDiv.style.marginBottom = '12px';
        ctxDiv.style.color = '#c8d4e4';
        ctxDiv.textContent = currentContext;
        c.appendChild(ctxDiv);

        const speechBubble = document.createElement('div');
        speechBubble.className = 'paper';
        speechBubble.style.padding = '14px 18px';
        speechBubble.style.background = 'rgba(25, 33, 48, 0.75)';
        speechBubble.style.borderRadius = '8px';
        speechBubble.style.borderLeft = '3px solid #d4a259';
        speechBubble.style.marginBottom = '16px';
        speechBubble.innerHTML = `<p style="margin:0; font-size:14px; line-height:1.55; color:#f6f8fb;">${currentSpeech}</p>`;
        c.appendChild(speechBubble);

        const qTitle = document.createElement('div');
        qTitle.style.fontSize = '12px';
        qTitle.style.fontWeight = '600';
        qTitle.style.textTransform = 'uppercase';
        qTitle.style.letterSpacing = '0.05em';
        qTitle.style.color = '#8a95a8';
        qTitle.style.marginBottom = '8px';
        qTitle.textContent = 'Вопросы для выяснения правды:';
        c.appendChild(qTitle);

        const qList = document.createElement('div');
        qList.style.display = 'flex';
        qList.style.flexDirection = 'column';
        qList.style.gap = '8px';
        qList.style.marginBottom = '16px';

        dt.questions.forEach((qObj, idx) => {
          const qBtn = document.createElement('button');
          const isAsked = askedQuestions.has(idx);
          qBtn.className = 'mbtn small';
          qBtn.style.textAlign = 'left';
          qBtn.style.justifyContent = 'flex-start';
          qBtn.style.padding = '8px 12px';
          qBtn.style.background = isAsked ? 'rgba(255, 255, 255, 0.04)' : 'rgba(212, 162, 89, 0.12)';
          qBtn.style.borderColor = isAsked ? 'rgba(255, 255, 255, 0.12)' : 'rgba(212, 162, 89, 0.45)';
          qBtn.style.color = isAsked ? '#a0aec0' : '#ffd8a8';
          qBtn.innerHTML = `<span>${isAsked ? '✓ ' : '▸ '}${qObj.q}</span>`;
          qBtn.onclick = () => {
            askedQuestions.add(idx);
            currentSpeech = qObj.a;
            currentContext = `Элиас спрашивает: ${qObj.q}`;
            G.audio.sfx('paper');
            renderDialog();
          };
          qList.appendChild(qBtn);
        });
        c.appendChild(qList);

        const actRow = document.createElement('div');
        actRow.className = 'btnRow';
        actRow.style.justifyContent = 'space-between';

        if (npc.testimony) {
          const recBtn = document.createElement('button');
          recBtn.className = 'mbtn small' + (testimonyRecorded ? '' : ' primary');
          recBtn.innerHTML = testimonyRecorded ? '<span>✓ Показание записано в Дневник</span>' : '<span>Записать показание в Дневник</span>';
          recBtn.onclick = () => {
            if (!testimonyRecorded) {
              addTestimony(npc.testimony.id);
              testimonyRecorded = true;
              G.audio.sfx('success');
              G.ui.toast(`Записано показание: ${npc.name}`);
              renderDialog();
            }
          };
          actRow.appendChild(recBtn);
        }

        const leaveBtn = document.createElement('button');
        leaveBtn.className = 'mbtn small';
        leaveBtn.textContent = 'Отойти';
        leaveBtn.onclick = () => {
          G.ui.closePanel();
          G.lock(false);
          if (G.memoryBoard && G.memoryBoard.getChapterClues(G.chapter).length > 0 && !G.memoryBoard.getConclusion(G.chapter)) {
            G.objective('Откройте «Выводы» (J / кнопка сверху), чтобы связать улику и показание');
          }
          resolve();
        };
        actRow.appendChild(leaveBtn);
        c.appendChild(actRow);
      });
    };
    renderDialog();
  });
}
