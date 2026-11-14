package com.example.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.data.ActiveModal
import com.example.data.ChaptersCatalog2
import com.example.data.CustomLinkData
import com.example.data.GameUiState
import com.example.data.MemoryProfile
import com.example.data.MemoryVector
import com.example.ui.theme.DenialColor
import com.example.ui.theme.DreamGold
import com.example.ui.theme.DreamRose
import com.example.ui.theme.InkMuted
import com.example.ui.theme.InkPrimary
import com.example.ui.theme.InkSecondary
import com.example.ui.theme.ObsidianElevated
import com.example.ui.theme.ObsidianSurface
import com.example.ui.theme.ObsidianVoid
import com.example.ui.theme.PanelBorder
import com.example.ui.theme.ProjectionColor
import com.example.ui.theme.TruthColor

private fun vectorLabel(v: MemoryVector): String = when (v) {
    MemoryVector.TRUTH -> "Истина"
    MemoryVector.DENIAL -> "Отрицание"
    MemoryVector.PROJECTION -> "Проекция"
}

private fun vectorColor(v: MemoryVector): Color = when (v) {
    MemoryVector.TRUTH -> TruthColor
    MemoryVector.DENIAL -> DenialColor
    MemoryVector.PROJECTION -> ProjectionColor
}

@Composable
fun NpcDialogueModal(
    modal: ActiveModal.NpcDialogue,
    onAskQuestion: (Int) -> Unit,
    onRecordTestimony: () -> Unit,
    onClose: () -> Unit
) {
    BackHandler { onClose() }
    val npc = modal.npc
    val dt = npc.dialogTree

    ModalBackdrop(onDismiss = onClose, maxWidthDp = 640) {
        Column(
            modifier = Modifier
                .padding(20.dp)
                .heightIn(max = 540.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ModalHeader(
                title = npc.name,
                subtitle = npc.role,
                accent = when (npc.type) {
                    "phantom_denial" -> DenialColor
                    "phantom_projection" -> ProjectionColor
                    "real" -> TruthColor
                    else -> DreamGold
                },
                onDismiss = onClose
            )

            Text(
                text = modal.currentContext,
                style = MaterialTheme.typography.labelMedium,
                color = InkSecondary
            )

            Surface(
                shape = RoundedCornerShape(16.dp),
                color = ObsidianSurface,
                border = BorderStroke(1.dp, PanelBorder),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = modal.currentSpeech,
                    style = MaterialTheme.typography.bodyMedium,
                    color = InkPrimary,
                    modifier = Modifier.padding(16.dp)
                )
            }

            if (dt != null && dt.questions.isNotEmpty()) {
                Text("Спросить:", style = MaterialTheme.typography.labelMedium, color = DreamGold)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    dt.questions.forEachIndexed { idx, qObj ->
                        val asked = modal.askedIndices.contains(idx)
                        Surface(
                            onClick = { onAskQuestion(idx) },
                            shape = RoundedCornerShape(14.dp),
                            color = if (asked) ObsidianSurface else ObsidianElevated,
                            border = BorderStroke(1.dp, if (asked) InkMuted.copy(alpha = 0.3f) else DreamGold.copy(alpha = 0.45f)),
                            modifier = Modifier.fillMaxWidth().testTag("btn_npc_q_$idx")
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = qObj.q,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (asked) InkSecondary else InkPrimary,
                                    modifier = Modifier.weight(1f)
                                )
                                if (asked) {
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Icon(Icons.Rounded.CheckCircle, contentDescription = "Спрошено", tint = TruthColor, modifier = Modifier.size(18.dp))
                                }
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (npc.testimony != null) {
                    Button(
                        onClick = onRecordTestimony,
                        enabled = !modal.testimonyRecorded,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = vectorColor(npc.testimony.vector),
                            contentColor = ObsidianVoid
                        ),
                        shape = RoundedCornerShape(14.dp),
                        modifier = Modifier.weight(1f).height(50.dp).testTag("btn_record_testimony")
                    ) {
                        Icon(Icons.Rounded.EditNote, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(if (modal.testimonyRecorded) "Записано" else "Записать показание")
                    }
                }

                OutlinedButton(
                    onClick = onClose,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.height(50.dp).testTag("btn_close_dialogue")
                ) {
                    Text("Отойти")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MemoryBoardModal(
    state: GameUiState,
    profile: MemoryProfile,
    isChapterExitReady: (Int) -> Boolean,
    isMandatoryWorldDone: (Int) -> Boolean,
    onLockConclusion: (Int, MemoryVector, CustomLinkData) -> Unit,
    onAdvanceChapter: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    BackHandler { onDismiss() }
    var tabIndex by remember { mutableIntStateOf(0) }
    var viewChapter by remember(state.chapter) { mutableIntStateOf(state.chapter.coerceIn(1, 9)) }

    ModalBackdrop(onDismiss = onDismiss, maxWidthDp = 760) {
        Column(modifier = Modifier.padding(20.dp)) {
            ModalHeader(
                title = "Доска выводов и Хроника",
                subtitle = "Истина: ${profile.truth} · Отрицание: ${profile.denial} · Проекция: ${profile.projection}",
                onDismiss = onDismiss
            )
            Spacer(modifier = Modifier.height(8.dp))

            SecondaryTabRow(
                selectedTabIndex = tabIndex,
                containerColor = ObsidianSurface,
                contentColor = DreamGold
            ) {
                Tab(
                    selected = tabIndex == 0,
                    onClick = { tabIndex = 0 },
                    text = { Text("Доска выводов") }
                )
                Tab(
                    selected = tabIndex == 1,
                    onClick = { tabIndex = 1 },
                    text = { Text("Хроника (1–10)") }
                )
            }
            Spacer(modifier = Modifier.height(12.dp))

            if (tabIndex == 0) {
                DeductionBoardTab(
                    state = state,
                    viewChapter = viewChapter,
                    onSelectChapter = { viewChapter = it },
                    isExitReady = isChapterExitReady(state.chapter),
                    isWorldDone = isMandatoryWorldDone(viewChapter),
                    onLockConclusion = onLockConclusion,
                    onAdvanceChapter = { onAdvanceChapter(state.chapter + 1) }
                )
            } else {
                ChronicleTab(state = state)
            }
        }
    }
}

@Composable
private fun DeductionBoardTab(
    state: GameUiState,
    viewChapter: Int,
    onSelectChapter: (Int) -> Unit,
    isExitReady: Boolean,
    isWorldDone: Boolean,
    onLockConclusion: (Int, MemoryVector, CustomLinkData) -> Unit,
    onAdvanceChapter: () -> Unit
) {
    val chDef = ChaptersCatalog2.get(viewChapter)
    val lockedVector = state.conclusions[viewChapter]
    val discoveredClues = chDef.clues.filter { state.clues.contains(it.id) }
    val recordedTests = chDef.npcs.mapNotNull { it.testimony }.filter { state.testimonies.contains(it.id) }

    var pickedClue by remember(viewChapter, discoveredClues) { mutableStateOf(discoveredClues.firstOrNull()?.id) }
    var pickedTest by remember(viewChapter, recordedTests) { mutableStateOf(recordedTests.firstOrNull()?.id) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 430.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Chapter selector pills (1..9)
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            for (c in 1..9) {
                val done = state.conclusions.containsKey(c)
                FilterChip(
                    selected = viewChapter == c,
                    onClick = { onSelectChapter(c) },
                    label = { Text("Гл. $c${if (done) " ✓" else ""}") }
                )
            }
        }

        Text("${chDef.kicker} — ${chDef.title}", style = MaterialTheme.typography.titleMedium, color = DreamGold)

        if (lockedVector != null) {
            val matched = chDef.conclusions.firstOrNull { it.vector == lockedVector }
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = vectorColor(lockedVector).copy(alpha = 0.14f),
                border = BorderStroke(1.dp, vectorColor(lockedVector)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = "ВЫВОД ЗАФИКСИРОВАН · ${vectorLabel(lockedVector).uppercase()}",
                        style = MaterialTheme.typography.labelSmall,
                        color = vectorColor(lockedVector),
                        fontWeight = FontWeight.Bold
                    )
                    Text(matched?.title ?: vectorLabel(lockedVector), style = MaterialTheme.typography.titleSmall, color = InkPrimary)
                    Text(matched?.text ?: "Версия событий закреплена в дневнике.", style = MaterialTheme.typography.bodySmall, color = InkSecondary)
                }
            }
        } else {
            Text("1. Выберите найденную улику:", style = MaterialTheme.typography.labelMedium, color = DreamGold)
            if (discoveredClues.isEmpty()) {
                Text("Улики этой главы ещё не найдены. Осматривайте мир и подбирайте предметы.", style = MaterialTheme.typography.bodySmall, color = InkMuted)
            } else {
                discoveredClues.forEach { c ->
                    val sel = pickedClue == c.id
                    Surface(
                        onClick = { pickedClue = c.id },
                        shape = RoundedCornerShape(12.dp),
                        color = if (sel) DreamGold.copy(alpha = 0.16f) else ObsidianElevated,
                        border = BorderStroke(1.dp, if (sel) DreamGold else InkMuted.copy(alpha = 0.25f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text(c.title, style = MaterialTheme.typography.bodySmall, color = if (sel) DreamGold else InkPrimary, fontWeight = FontWeight.SemiBold)
                            Text(c.desc, style = MaterialTheme.typography.labelSmall, color = InkSecondary)
                        }
                    }
                }
            }

            Text("2. Выберите показание свидетеля:", style = MaterialTheme.typography.labelMedium, color = DreamGold)
            if (recordedTests.isEmpty()) {
                Text("Показания ещё не записаны. Поговорите с персонажами в мире и сохраните их версию.", style = MaterialTheme.typography.bodySmall, color = InkMuted)
            } else {
                recordedTests.forEach { t ->
                    val sel = pickedTest == t.id
                    val vCol = vectorColor(t.vector)
                    Surface(
                        onClick = { pickedTest = t.id },
                        shape = RoundedCornerShape(12.dp),
                        color = if (sel) vCol.copy(alpha = 0.16f) else ObsidianElevated,
                        border = BorderStroke(1.dp, if (sel) vCol else InkMuted.copy(alpha = 0.25f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text("${t.speaker} · ${vectorLabel(t.vector)}", style = MaterialTheme.typography.bodySmall, color = vCol, fontWeight = FontWeight.SemiBold)
                            Text(t.summary, style = MaterialTheme.typography.labelSmall, color = InkPrimary)
                        }
                    }
                }
            }

            val canCommit = pickedClue != null && pickedTest != null
            if (canCommit) {
                val chosenTest = recordedTests.firstOrNull { it.id == pickedTest }
                val exactMatch = chDef.conclusions.firstOrNull { it.reqClue == pickedClue && it.reqTestimony == pickedTest }
                val vector = exactMatch?.vector ?: chosenTest?.vector ?: MemoryVector.TRUTH
                val previewTitle = exactMatch?.title ?: "Версия памяти: ${vectorLabel(vector)}"
                val previewText = exactMatch?.text ?: "${discoveredClues.first { it.id == pickedClue }.title} + показание (${chosenTest?.speaker})"

                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = ObsidianSurface,
                    border = BorderStroke(1.dp, vectorColor(vector).copy(alpha = 0.7f)),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(previewTitle, style = MaterialTheme.typography.titleSmall, color = vectorColor(vector))
                        Text(previewText, style = MaterialTheme.typography.bodySmall, color = InkPrimary)
                        Button(
                            onClick = {
                                onLockConclusion(viewChapter, vector, CustomLinkData(pickedClue!!, pickedTest!!))
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = vectorColor(vector), contentColor = ObsidianVoid),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_lock_conclusion")
                        ) {
                            Icon(Icons.Rounded.Lock, contentDescription = null)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("Зафиксировать вывод главы $viewChapter")
                        }
                    }
                }
            }
        }

        if (!isWorldDone && viewChapter == state.chapter) {
            Text(
                text = "Условие главы: ${chDef.mandatoryGateHint}",
                style = MaterialTheme.typography.labelSmall,
                color = DreamRose
            )
        }

        if (isExitReady && state.chapter < 10) {
            Button(
                onClick = onAdvanceChapter,
                colors = ButtonDefaults.buttonColors(containerColor = DreamGold, contentColor = ObsidianVoid),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(50.dp).testTag("btn_advance_chapter")
            ) {
                Text("Перейти к Главе ${state.chapter + 1}")
                Spacer(modifier = Modifier.width(8.dp))
                Icon(Icons.AutoMirrored.Rounded.ArrowForward, contentDescription = null)
            }
        }
    }
}

@Composable
private fun ChronicleTab(state: GameUiState) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 420.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        for (c in 1..10) {
            val ch = ChaptersCatalog2.get(c)
            val conc = state.conclusions[c]
            val current = state.chapter == c
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = if (current) DreamGold.copy(alpha = 0.10f) else ObsidianElevated,
                border = BorderStroke(1.dp, if (current) DreamGold else InkMuted.copy(alpha = 0.25f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("${ch.kicker} · ${ch.title}", style = MaterialTheme.typography.titleSmall, color = if (current) DreamGold else InkPrimary)
                        if (conc != null) {
                            Text(vectorLabel(conc), style = MaterialTheme.typography.labelSmall, color = vectorColor(conc), fontWeight = FontWeight.Bold)
                        } else if (c < state.chapter) {
                            Text("пройдено", style = MaterialTheme.typography.labelSmall, color = InkSecondary)
                        }
                    }
                    Text(ch.subtitle, style = MaterialTheme.typography.bodySmall, color = InkSecondary)
                }
            }
        }
    }
}
