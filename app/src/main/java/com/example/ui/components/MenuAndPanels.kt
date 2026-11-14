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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ExitToApp
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.R
import com.example.data.GameSettings
import com.example.data.SaveSlotInfo
import com.example.ui.theme.DreamGold
import com.example.ui.theme.DreamRose
import com.example.ui.theme.InkMuted
import com.example.ui.theme.InkPrimary
import com.example.ui.theme.InkSecondary
import com.example.ui.theme.NightmareCrimson
import com.example.ui.theme.ObsidianElevated
import com.example.ui.theme.ObsidianPanel
import com.example.ui.theme.ObsidianVoid
import com.example.ui.theme.PanelBorder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun MainMenuScreen(
    hasAutoSave: Boolean,
    onContinue: () -> Unit,
    onNewGame: () -> Unit,
    onOpenLoad: () -> Unit,
    onOpenSettings: () -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(id = R.drawable.img_menu_backdrop),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            ObsidianVoid.copy(alpha = 0.55f),
                            ObsidianVoid.copy(alpha = 0.72f),
                            ObsidianVoid.copy(alpha = 0.94f)
                        )
                    )
                )
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(top = 24.dp)
            ) {
                Text(
                    text = stringResource(id = R.string.app_subtitle).uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    color = DreamGold
                )
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    text = stringResource(id = R.string.app_name),
                    style = MaterialTheme.typography.displayLarge,
                    color = InkPrimary
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = stringResource(id = R.string.app_tagline),
                    style = MaterialTheme.typography.bodyMedium,
                    color = InkSecondary,
                    textAlign = TextAlign.Center
                )
            }

            Surface(
                shape = RoundedCornerShape(24.dp),
                color = ObsidianPanel.copy(alpha = 0.88f),
                border = BorderStroke(1.dp, PanelBorder),
                modifier = Modifier.widthIn(max = 380.dp).fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    if (hasAutoSave) {
                        Button(
                            onClick = onContinue,
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = DreamGold, contentColor = ObsidianVoid),
                            modifier = Modifier.fillMaxWidth().height(52.dp).testTag("btn_continue")
                        ) {
                            Icon(Icons.Rounded.PlayArrow, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Продолжить", style = MaterialTheme.typography.labelLarge)
                        }
                    }

                    Button(
                        onClick = onNewGame,
                        shape = RoundedCornerShape(14.dp),
                        colors = if (hasAutoSave) {
                            ButtonDefaults.buttonColors(containerColor = ObsidianElevated, contentColor = InkPrimary)
                        } else {
                            ButtonDefaults.buttonColors(containerColor = DreamGold, contentColor = ObsidianVoid)
                        },
                        modifier = Modifier.fillMaxWidth().height(52.dp).testTag("btn_new_game")
                    ) {
                        Text(stringResource(id = R.string.action_new_game), style = MaterialTheme.typography.labelLarge)
                    }

                    OutlinedButton(
                        onClick = onOpenLoad,
                        shape = RoundedCornerShape(14.dp),
                        border = BorderStroke(1.dp, PanelBorder),
                        modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_load_menu")
                    ) {
                        Icon(Icons.Rounded.FolderOpen, contentDescription = null, tint = DreamGold)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(stringResource(id = R.string.action_load_game), color = InkPrimary)
                    }

                    OutlinedButton(
                        onClick = onOpenSettings,
                        shape = RoundedCornerShape(14.dp),
                        border = BorderStroke(1.dp, PanelBorder),
                        modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_settings")
                    ) {
                        Icon(Icons.Rounded.Settings, contentDescription = null, tint = InkSecondary)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(stringResource(id = R.string.action_settings), color = InkPrimary)
                    }
                }
            }

            Text(
                text = "10 глав · два мира · четыре финала",
                style = MaterialTheme.typography.labelSmall,
                color = InkMuted
            )
        }
    }
}

@Composable
fun PauseOverlay(
    chapter: Int,
    chapterTitle: String,
    onResume: () -> Unit,
    onOpenSave: () -> Unit,
    onOpenLoad: () -> Unit,
    onOpenSettings: () -> Unit,
    onReturnMenu: () -> Unit
) {
    BackHandler { onResume() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(ObsidianVoid.copy(alpha = 0.78f))
            .safeDrawingPadding()
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = ObsidianPanel,
            border = BorderStroke(1.dp, PanelBorder),
            modifier = Modifier.widthIn(max = 400.dp).fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("ПАУЗА", style = MaterialTheme.typography.labelMedium, color = DreamGold)
                Text("Глава $chapter · $chapterTitle", style = MaterialTheme.typography.titleMedium, color = InkPrimary, textAlign = TextAlign.Center)
                Spacer(modifier = Modifier.height(6.dp))

                Button(
                    onClick = onResume,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(50.dp).testTag("btn_resume")
                ) {
                    Text("Продолжить игру")
                }

                OutlinedButton(
                    onClick = onOpenSave,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_save_menu")
                ) {
                    Icon(Icons.Rounded.Save, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Сохранить")
                }

                OutlinedButton(
                    onClick = onOpenLoad,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_load_pause")
                ) {
                    Icon(Icons.Rounded.FolderOpen, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Загрузить")
                }

                OutlinedButton(
                    onClick = onOpenSettings,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_pause_settings")
                ) {
                    Icon(Icons.Rounded.Settings, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Настройки")
                }

                HorizontalDivider(color = InkMuted.copy(alpha = 0.25f))

                OutlinedButton(
                    onClick = onReturnMenu,
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = NightmareCrimson),
                    border = BorderStroke(1.dp, NightmareCrimson.copy(alpha = 0.5f)),
                    modifier = Modifier.fillMaxWidth().height(48.dp).testTag("btn_exit_menu")
                ) {
                    Icon(Icons.AutoMirrored.Rounded.ExitToApp, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("В главное меню")
                }
            }
        }
    }
}

@Composable
fun SaveLoadModal(
    isSaving: Boolean,
    slots: List<SaveSlotInfo>,
    onSaveSlot: (String) -> Unit,
    onLoadSlot: (String) -> Unit,
    onDeleteSlot: (String) -> Unit,
    onDismiss: () -> Unit
) {
    BackHandler { onDismiss() }
    val fmt = remember { SimpleDateFormat("dd.MM HH:mm", Locale.getDefault()) }

    ModalBackdrop(onDismiss = onDismiss) {
        Column(modifier = Modifier.padding(20.dp)) {
            ModalHeader(
                title = if (isSaving) "Сохранение игры" else "Загрузка сохранения",
                subtitle = if (isSaving) "Выберите ячейку памяти" else "Выберите сохранённую точку",
                onDismiss = onDismiss
            )
            Spacer(modifier = Modifier.height(14.dp))

            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                slots.forEach { slot ->
                    if (isSaving && slot.slotId == "auto") return@forEach
                    val p = slot.payload
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = ObsidianElevated,
                        border = BorderStroke(1.dp, if (p != null) PanelBorder else InkMuted.copy(alpha = 0.2f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(slot.label, style = MaterialTheme.typography.titleSmall, color = DreamGold)
                                if (p != null) {
                                    Text(
                                        text = "Глава ${p.chapter} · ${p.sceneName}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = InkPrimary
                                    )
                                    Text(
                                        text = "${fmt.format(Date(p.timestamp))} · Рассудок ${p.stability.toInt()}%",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = InkSecondary
                                    )
                                } else {
                                    Text("Пустая ячейка", style = MaterialTheme.typography.bodySmall, color = InkMuted)
                                }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                if (p != null) {
                                    IconButton(
                                        onClick = { onDeleteSlot(slot.slotId) },
                                        modifier = Modifier.size(48.dp)
                                    ) {
                                        Icon(Icons.Rounded.DeleteOutline, contentDescription = "Удалить", tint = NightmareCrimson)
                                    }
                                }
                                Button(
                                    onClick = {
                                        if (isSaving) onSaveSlot(slot.slotId) else onLoadSlot(slot.slotId)
                                    },
                                    enabled = isSaving || p != null,
                                    shape = RoundedCornerShape(12.dp),
                                    modifier = Modifier.height(48.dp).testTag("slot_action_${slot.slotId}")
                                ) {
                                    Text(if (isSaving) "Сохранить" else "Загрузить")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsModal(
    settings: GameSettings,
    onUpdate: (GameSettings) -> Unit,
    onDismiss: () -> Unit
) {
    BackHandler { onDismiss() }
    var draft by remember(settings) { mutableStateOf(settings) }

    ModalBackdrop(onDismiss = onDismiss) {
        Column(
            modifier = Modifier
                .padding(20.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ModalHeader(title = "Настройки", subtitle = "Управление, камера и звук", onDismiss = onDismiss)

            SettingSliderRow(
                label = "Чувствительность камеры (${String.format(Locale.US, "%.1f", draft.sensitivity)})",
                value = draft.sensitivity,
                range = 0.4f..2.2f,
                onChange = {
                    draft = draft.copy(sensitivity = it)
                    onUpdate(draft)
                }
            )
            SettingSliderRow(
                label = "Громкость музыки (${(draft.musicVolume * 100).toInt()}%)",
                value = draft.musicVolume,
                range = 0f..1f,
                onChange = {
                    draft = draft.copy(musicVolume = it)
                    onUpdate(draft)
                }
            )
            SettingSliderRow(
                label = "Громкость эффектов (${(draft.sfxVolume * 100).toInt()}%)",
                value = draft.sfxVolume,
                range = 0f..1f,
                onChange = {
                    draft = draft.copy(sfxVolume = it)
                    onUpdate(draft)
                }
            )

            SettingToggleRow(
                label = "Вид от третьего лица",
                checked = draft.thirdPerson,
                tag = "switch_third_person",
                onToggle = {
                    draft = draft.copy(thirdPerson = it)
                    onUpdate(draft)
                }
            )
            SettingToggleRow(
                label = "Инверсия вертикальной оси Y",
                checked = draft.invertY,
                tag = "switch_invert_y",
                onToggle = {
                    draft = draft.copy(invertY = it)
                    onUpdate(draft)
                }
            )
            SettingToggleRow(
                label = "Показывать счётчик FPS",
                checked = draft.showFps,
                tag = "switch_show_fps",
                onToggle = {
                    draft = draft.copy(showFps = it)
                    onUpdate(draft)
                }
            )
        }
    }
}

@Composable
private fun SettingSliderRow(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit
) {
    Column {
        Text(label, style = MaterialTheme.typography.bodySmall, color = InkPrimary)
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = range,
            colors = SliderDefaults.colors(thumbColor = DreamGold, activeTrackColor = DreamGold)
        )
    }
}

@Composable
private fun SettingToggleRow(
    label: String,
    checked: Boolean,
    tag: String,
    onToggle: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = InkPrimary, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onToggle,
            modifier = Modifier.testTag(tag)
        )
    }
}

@Composable
fun ModalBackdrop(
    onDismiss: () -> Unit,
    maxWidthDp: Int = 620,
    content: @Composable () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(ObsidianVoid.copy(alpha = 0.78f))
            .safeDrawingPadding()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = ObsidianPanel,
            border = BorderStroke(1.dp, PanelBorder),
            modifier = Modifier.widthIn(max = maxWidthDp.dp).fillMaxWidth()
        ) {
            content()
        }
    }
}

@Composable
fun ModalHeader(
    title: String,
    subtitle: String? = null,
    accent: Color = DreamGold,
    onDismiss: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            if (!subtitle.isNullOrBlank()) {
                Text(subtitle.uppercase(), style = MaterialTheme.typography.labelSmall, color = accent, fontWeight = FontWeight.SemiBold)
            }
            Text(title, style = MaterialTheme.typography.titleLarge, color = InkPrimary)
        }
        IconButton(
            onClick = onDismiss,
            modifier = Modifier.size(48.dp).testTag("btn_modal_close")
        ) {
            Icon(Icons.Rounded.Close, contentDescription = stringResource(id = R.string.cd_close), tint = InkSecondary)
        }
    }
}
