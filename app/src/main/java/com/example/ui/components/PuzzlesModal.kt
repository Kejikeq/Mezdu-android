package com.example.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material.icons.rounded.Flip
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RotateLeft
import androidx.compose.material.icons.rounded.RotateRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.data.ActiveModal
import com.example.engine.MapGenerator
import com.example.ui.theme.DreamGold
import com.example.ui.theme.DreamRose
import com.example.ui.theme.DreamSage
import com.example.ui.theme.DreamSky
import com.example.ui.theme.InkMuted
import com.example.ui.theme.InkPrimary
import com.example.ui.theme.InkSecondary
import com.example.ui.theme.NightmareCrimson
import com.example.ui.theme.ObsidianElevated
import com.example.ui.theme.ObsidianSurface
import com.example.ui.theme.ObsidianVoid
import com.example.ui.theme.PanelBorder

private data class RuneDef(val id: String, val glyph: String, val label: String, val color: Color)

private val RUNES = listOf(
    RuneDef("sun", "☀", "Солнце", DreamGold),
    RuneDef("moon", "☾", "Луна", DreamSky),
    RuneDef("wave", "≈", "Волна", DreamRose),
    RuneDef("leaf", "❦", "Лист", DreamSage)
)

@Composable
fun RunePuzzleModal(
    modal: ActiveModal.RunePuzzle,
    onComplete: (Boolean) -> Unit
) {
    BackHandler { onComplete(false) }
    val sequence = remember(modal) { mutableStateListOf<String>() }
    var wrongHint by remember(modal) { mutableStateOf(false) }

    ModalBackdrop(onDismiss = { onComplete(false) }, maxWidthDp = 520) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ModalHeader(title = modal.title, subtitle = modal.kicker, onDismiss = { onComplete(false) })
            Text(modal.text, style = MaterialTheme.typography.bodySmall, color = InkSecondary)

            // Current 4-rune slot display
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for (i in 0 until 4) {
                    val rid = sequence.getOrNull(i)
                    val rdef = RUNES.firstOrNull { it.id == rid }
                    Surface(
                        shape = RoundedCornerShape(14.dp),
                        color = ObsidianVoid,
                        border = BorderStroke(1.5.dp, rdef?.color ?: InkMuted.copy(alpha = 0.3f)),
                        modifier = Modifier.weight(1f).height(62.dp)
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                text = rdef?.glyph ?: "·",
                                style = MaterialTheme.typography.headlineMedium,
                                color = rdef?.color ?: InkMuted
                            )
                        }
                    }
                }
            }

            if (wrongHint) {
                Text(
                    text = "Механизм не поддался — порядок рун неверен.",
                    style = MaterialTheme.typography.labelSmall,
                    color = NightmareCrimson
                )
            }

            // 4 clickable rune buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                RUNES.forEach { rune ->
                    Surface(
                        onClick = {
                            wrongHint = false
                            if (sequence.size < 4) sequence.add(rune.id)
                        },
                        shape = RoundedCornerShape(14.dp),
                        color = ObsidianElevated,
                        border = BorderStroke(1.dp, rune.color.copy(alpha = 0.65f)),
                        modifier = Modifier.weight(1f).height(64.dp).testTag("btn_rune_${rune.id}")
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Text(rune.glyph, style = MaterialTheme.typography.titleLarge, color = rune.color)
                            Text(rune.label, style = MaterialTheme.typography.labelSmall, color = InkPrimary)
                        }
                    }
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = {
                        sequence.clear()
                        wrongHint = false
                    },
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.height(48.dp)
                ) {
                    Icon(Icons.Rounded.Refresh, contentDescription = "Сброс")
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Сброс")
                }

                Button(
                    onClick = {
                        val current = sequence.toList()
                        val matched = modal.solutions.any { it == current }
                        if (matched) {
                            onComplete(true)
                        } else {
                            wrongHint = true
                            sequence.clear()
                        }
                    },
                    enabled = sequence.size == 4,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.weight(1f).height(48.dp).testTag("btn_rune_confirm")
                ) {
                    Text("Активировать")
                }
            }
        }
    }
}

@Composable
fun LetterPuzzleModal(
    modal: ActiveModal.LetterPuzzle,
    onComplete: (Boolean) -> Unit
) {
    BackHandler { onComplete(false) }
    val shuffledOrder = remember(modal) { listOf(2, 0, 4, 1, 5, 3) }
    val chosenOrder = remember(modal) { mutableStateListOf<Int>() }
    var wrongHint by remember(modal) { mutableStateOf(false) }

    ModalBackdrop(onDismiss = { onComplete(false) }, maxWidthDp = 620) {
        Column(
            modifier = Modifier
                .padding(20.dp)
                .heightIn(max = 540.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            ModalHeader(
                title = "Сложить разорванное письмо",
                subtitle = "Соберите 6 обрывков в правильном порядке",
                onDismiss = { onComplete(false) }
            )

            // Assembled preview
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = ObsidianSurface,
                border = BorderStroke(1.dp, PanelBorder),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (chosenOrder.isEmpty()) {
                        Text("Нажимайте на обрывки ниже по очереди…", style = MaterialTheme.typography.bodySmall, color = InkMuted)
                    } else {
                        chosenOrder.forEachIndexed { pos, fragIdx ->
                            val frag = modal.fragments[fragIdx]
                            Surface(
                                onClick = {
                                    chosenOrder.removeAt(pos)
                                    wrongHint = false
                                },
                                shape = RoundedCornerShape(10.dp),
                                color = if (frag.isNight) Color(0xFF2B1C20) else Color(0xFF312A22),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = "${pos + 1}. ${frag.text}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = InkPrimary,
                                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)
                                )
                            }
                        }
                    }
                    Text(modal.tail, style = MaterialTheme.typography.bodySmall, color = DreamGold, fontWeight = FontWeight.SemiBold)
                }
            }

            if (wrongHint) {
                Text("Смысл строк не сходится. Попробуйте другой порядок.", style = MaterialTheme.typography.labelSmall, color = NightmareCrimson)
            }

            // Remaining fragments
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                shuffledOrder.forEach { fragIdx ->
                    if (!chosenOrder.contains(fragIdx)) {
                        val frag = modal.fragments[fragIdx]
                        Surface(
                            onClick = {
                                wrongHint = false
                                chosenOrder.add(fragIdx)
                            },
                            shape = RoundedCornerShape(12.dp),
                            color = if (frag.isNight) Color(0xFF28191E) else ObsidianElevated,
                            border = BorderStroke(1.dp, if (frag.isNight) NightmareCrimson.copy(alpha = 0.5f) else DreamGold.copy(alpha = 0.45f)),
                            modifier = Modifier.fillMaxWidth().testTag("frag_$fragIdx")
                        ) {
                            Text(
                                text = frag.text,
                                style = MaterialTheme.typography.bodySmall,
                                color = InkPrimary,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)
                            )
                        }
                    }
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = {
                        chosenOrder.clear()
                        wrongHint = false
                    },
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.height(48.dp)
                ) {
                    Text("Очистить")
                }

                Button(
                    onClick = {
                        if (chosenOrder.toList() == listOf(0, 1, 2, 3, 4, 5)) {
                            onComplete(true)
                        } else {
                            wrongHint = true
                        }
                    },
                    enabled = chosenOrder.size == modal.fragments.size,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.weight(1f).height(48.dp).testTag("btn_letter_confirm")
                ) {
                    Text("Скрепить письмо")
                }
            }
        }
    }
}

@Composable
fun CodePuzzleModal(
    modal: ActiveModal.CodePuzzle,
    onComplete: (Boolean) -> Unit
) {
    BackHandler { onComplete(false) }
    val digits = remember(modal) { mutableStateListOf(0, 0, 0, 0) }
    var wrongHint by remember(modal) { mutableStateOf(false) }

    ModalBackdrop(onDismiss = { onComplete(false) }, maxWidthDp = 460) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ModalHeader(title = modal.title, subtitle = "Кодовый замок", onDismiss = { onComplete(false) })
            Text(modal.text, style = MaterialTheme.typography.bodySmall, color = InkSecondary)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                for (i in 0 until 4) {
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = ObsidianElevated,
                        border = BorderStroke(1.dp, PanelBorder),
                        modifier = Modifier.weight(1f)
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier.padding(vertical = 6.dp)
                        ) {
                            IconButton(
                                onClick = {
                                    wrongHint = false
                                    digits[i] = (digits[i] + 1) % 10
                                },
                                modifier = Modifier.size(48.dp).testTag("code_up_$i")
                            ) {
                                Icon(Icons.Rounded.KeyboardArrowUp, contentDescription = "Увеличить цифру", tint = DreamGold)
                            }
                            Text(
                                text = "${digits[i]}",
                                style = MaterialTheme.typography.headlineLarge,
                                color = InkPrimary
                            )
                            IconButton(
                                onClick = {
                                    wrongHint = false
                                    digits[i] = (digits[i] + 9) % 10
                                },
                                modifier = Modifier.size(48.dp).testTag("code_dn_$i")
                            ) {
                                Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = "Уменьшить цифру", tint = DreamGold)
                            }
                        }
                    }
                }
            }

            if (wrongHint) {
                Text("Щелчка нет — код неверный.", style = MaterialTheme.typography.labelSmall, color = NightmareCrimson)
            }

            Button(
                onClick = {
                    val code = digits.joinToString("")
                    if (code == modal.targetCode) onComplete(true) else wrongHint = true
                },
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(50.dp).testTag("btn_code_confirm")
            ) {
                Text("Открыть замок")
            }
        }
    }
}

@Composable
fun MapPuzzleModal(
    modal: ActiveModal.MapPuzzle,
    onComplete: (Boolean) -> Unit
) {
    BackHandler { onComplete(false) }
    var rotDeg by remember(modal) { mutableIntStateOf(if (modal.isReadOnlyView) 0 else 90) }
    var flipped by remember(modal) { mutableStateOf(!modal.isReadOnlyView) }
    var wrongHint by remember(modal) { mutableStateOf(false) }

    val dreamMap = remember { MapGenerator.buildDreamMapBitmap().asImageBitmap() }
    val nightMap = remember { MapGenerator.buildNightTracingBitmap().asImageBitmap() }

    ModalBackdrop(onDismiss = { onComplete(false) }, maxWidthDp = 540) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ModalHeader(
                title = if (modal.isReadOnlyView) "Совмещённая карта" else "Совмещение карт",
                subtitle = "Поверните кальку так, чтобы костры и русло совпали",
                onDismiss = { onComplete(false) }
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 260.dp)
                    .aspectRatio(1f)
                    .align(Alignment.CenterHorizontally)
                    .clip(RoundedCornerShape(16.dp))
                    .background(ObsidianVoid),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    bitmap = dreamMap,
                    contentDescription = "Дневная карта леса",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize()
                )
                Image(
                    bitmap = nightMap,
                    contentDescription = "Калька подземных ходов",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            rotationZ = rotDeg.toFloat()
                            scaleX = if (flipped) -1f else 1f
                        }
                )
            }

            if (wrongHint) {
                Text(
                    text = "Калька перевёрнута или смещена — линии ручья и точка костра не совпадают.",
                    style = MaterialTheme.typography.labelSmall,
                    color = NightmareCrimson,
                    textAlign = TextAlign.Center
                )
            }

            if (!modal.isReadOnlyView) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { rotDeg -= 90; wrongHint = false },
                        modifier = Modifier.weight(1f).height(48.dp).testTag("btn_map_rot_left")
                    ) {
                        Icon(Icons.Rounded.RotateLeft, contentDescription = "Повернуть влево")
                    }
                    OutlinedButton(
                        onClick = { rotDeg += 90; wrongHint = false },
                        modifier = Modifier.weight(1f).height(48.dp).testTag("btn_map_rot_right")
                    ) {
                        Icon(Icons.Rounded.RotateRight, contentDescription = "Повернуть вправо")
                    }
                    OutlinedButton(
                        onClick = { flipped = !flipped; wrongHint = false },
                        modifier = Modifier.weight(1f).height(48.dp).testTag("btn_map_flip")
                    ) {
                        Icon(Icons.Rounded.Flip, contentDescription = "Отразить кальку")
                    }
                }

                Button(
                    onClick = {
                        if (MapGenerator.isAligned(rotDeg, flipped)) {
                            onComplete(true)
                        } else {
                            wrongHint = true
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = DreamGold, contentColor = ObsidianVoid),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(50.dp).testTag("btn_map_confirm")
                ) {
                    Text("Закрепить маршрут")
                }
            } else {
                Button(
                    onClick = { onComplete(true) },
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) {
                    Text("Закрыть")
                }
            }
        }
    }
}
