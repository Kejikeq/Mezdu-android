package com.example.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.data.ActiveModal
import com.example.data.ItemsCatalog
import com.example.gfx.VoxelItemPreviewCanvas
import com.example.ui.theme.DreamGold
import com.example.ui.theme.DreamRose
import com.example.ui.theme.InkMuted
import com.example.ui.theme.InkPrimary
import com.example.ui.theme.InkSecondary
import com.example.ui.theme.NightmareCrimson
import com.example.ui.theme.ObsidianElevated
import com.example.ui.theme.ObsidianSurface
import com.example.ui.theme.ObsidianVoid
import com.example.ui.theme.PanelBorder

@Composable
fun InventoryModal(
    itemIds: List<String>,
    isNight: Boolean,
    onInspect: (String, String, String) -> Unit,
    onUseItem: (String) -> Unit,
    onDismiss: () -> Unit
) {
    BackHandler { onDismiss() }
    var selectedId by remember(itemIds) { mutableStateOf(itemIds.firstOrNull()) }

    ModalBackdrop(onDismiss = onDismiss, maxWidthDp = 760) {
        Column(modifier = Modifier.padding(20.dp)) {
            ModalHeader(
                title = "Вещи Элиаса",
                subtitle = if (isNight) "восприятие кошмара" else "дневная память",
                accent = if (isNight) NightmareCrimson else DreamGold,
                onDismiss = onDismiss
            )
            Spacer(modifier = Modifier.height(12.dp))

            if (itemIds.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxWidth().height(160.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text("Карманы пока пусты.", style = MaterialTheme.typography.bodyMedium, color = InkSecondary)
                }
            } else {
                val activeDef = selectedId?.let { ItemsCatalog.ITEMS[it] } ?: ItemsCatalog.ITEMS[itemIds.first()]
                val modelId = if (isNight && activeDef?.nightVariant != null) {
                    activeDef.nightVariant.invModel
                } else {
                    activeDef?.invModel ?: "default"
                }
                val desc = if (isNight && activeDef?.nightVariant != null) {
                    activeDef.nightVariant.desc
                } else {
                    activeDef?.desc.orEmpty()
                }

                BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                    val wide = maxWidth > 540.dp
                    if (wide) {
                        Row(
                            modifier = Modifier.fillMaxWidth().heightIn(max = 380.dp),
                            horizontalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            ItemSelectorList(
                                itemIds = itemIds,
                                selectedId = activeDef?.id,
                                onSelect = { selectedId = it },
                                modifier = Modifier.weight(0.45f)
                            )
                            ItemDetailPane(
                                modelId = modelId,
                                name = activeDef?.name.orEmpty(),
                                desc = desc,
                                hint = activeDef?.hint.orEmpty(),
                                useAction = activeDef?.useAction,
                                onInspect = {
                                    if (activeDef != null) onInspect(modelId, activeDef.name, desc)
                                },
                                onUse = { if (activeDef != null) onUseItem(activeDef.id) },
                                modifier = Modifier.weight(0.55f)
                            )
                        }
                    } else {
                        Column(
                            modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            ItemSelectorList(
                                itemIds = itemIds,
                                selectedId = activeDef?.id,
                                onSelect = { selectedId = it },
                                modifier = Modifier.fillMaxWidth().heightIn(max = 150.dp)
                            )
                            ItemDetailPane(
                                modelId = modelId,
                                name = activeDef?.name.orEmpty(),
                                desc = desc,
                                hint = activeDef?.hint.orEmpty(),
                                useAction = activeDef?.useAction,
                                onInspect = {
                                    if (activeDef != null) onInspect(modelId, activeDef.name, desc)
                                },
                                onUse = { if (activeDef != null) onUseItem(activeDef.id) },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ItemSelectorList(
    itemIds: List<String>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        items(itemIds, key = { it }) { id ->
            val def = ItemsCatalog.ITEMS[id]
            val selected = id == selectedId
            Surface(
                onClick = { onSelect(id) },
                shape = RoundedCornerShape(12.dp),
                color = if (selected) DreamGold.copy(alpha = 0.16f) else ObsidianElevated,
                border = BorderStroke(1.dp, if (selected) DreamGold else InkMuted.copy(alpha = 0.25f)),
                modifier = Modifier.fillMaxWidth().testTag("inv_item_$id")
            ) {
                Text(
                    text = def?.name ?: id,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (selected) DreamGold else InkPrimary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp)
                )
            }
        }
    }
}

@Composable
private fun ItemDetailPane(
    modelId: String,
    name: String,
    desc: String,
    hint: String,
    useAction: String?,
    onInspect: () -> Unit,
    onUse: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = ObsidianSurface,
        border = BorderStroke(1.dp, PanelBorder),
        modifier = modifier
    ) {
        Column(
            modifier = Modifier.padding(14.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(130.dp)
                    .background(ObsidianVoid.copy(alpha = 0.65f), RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center
            ) {
                VoxelItemPreviewCanvas(modelId = modelId, modifier = Modifier.fillMaxWidth().height(120.dp))
                Text(
                    text = "покрутите модель",
                    style = MaterialTheme.typography.labelSmall,
                    color = InkMuted,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp)
                )
            }

            Text(name, style = MaterialTheme.typography.titleMedium, color = DreamGold)
            Text(desc, style = MaterialTheme.typography.bodySmall, color = InkPrimary)
            Text(hint, style = MaterialTheme.typography.labelSmall, color = DreamRose)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = onInspect,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f).height(48.dp)
                ) {
                    Icon(Icons.Rounded.Visibility, contentDescription = null)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Осмотр")
                }
                if (useAction != null) {
                    val actionLabel = when (useAction) {
                        "photo" -> "Якорь"
                        "read" -> "Прочесть"
                        "flash" -> "Фонарь"
                        else -> "Применить"
                    }
                    Button(
                        onClick = onUse,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.weight(1f).height(48.dp).testTag("btn_use_item")
                    ) {
                        Text(actionLabel)
                    }
                }
            }
        }
    }
}

@Composable
fun InspectModal(
    modal: ActiveModal.Inspect,
    onConfirm: () -> Unit
) {
    BackHandler { onConfirm() }

    ModalBackdrop(onDismiss = onConfirm, maxWidthDp = 520) {
        Column(
            modifier = Modifier.padding(22.dp).verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ModalHeader(title = modal.title, subtitle = modal.kicker, onDismiss = onConfirm)

            Surface(
                shape = RoundedCornerShape(18.dp),
                color = ObsidianVoid,
                border = BorderStroke(1.dp, PanelBorder),
                modifier = Modifier.fillMaxWidth().height(200.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    VoxelItemPreviewCanvas(modelId = modal.modelId, modifier = Modifier.fillMaxWidth().height(190.dp))
                    Text(
                        text = "Потяните, чтобы рассмотреть со всех сторон",
                        style = MaterialTheme.typography.labelSmall,
                        color = InkMuted,
                        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)
                    )
                }
            }

            Text(
                text = modal.desc,
                style = MaterialTheme.typography.bodyMedium,
                color = InkPrimary,
                textAlign = TextAlign.Center
            )

            Button(
                onClick = onConfirm,
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(50.dp).testTag("btn_inspect_close")
            ) {
                Text(modal.buttonLabel)
            }
        }
    }
}

@Composable
fun ReaderModal(
    modal: ActiveModal.Reader,
    onDismiss: () -> Unit
) {
    BackHandler { onDismiss() }
    var pageIndex by remember(modal) { mutableIntStateOf(0) }
    val paperBg = if (modal.isNightPaper) Color(0xFF23181C) else Color(0xFFEDE0C8)
    val inkColor = if (modal.isNightPaper) Color(0xFFF2D7D3) else Color(0xFF2A2118)
    val borderColor = if (modal.isNightPaper) NightmareCrimson.copy(alpha = 0.6f) else DreamGold.copy(alpha = 0.7f)

    ModalBackdrop(onDismiss = onDismiss, maxWidthDp = 540) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            ModalHeader(
                title = modal.title,
                subtitle = if (modal.pages.size > 1) "Страница ${pageIndex + 1} из ${modal.pages.size}" else "Документ",
                accent = if (modal.isNightPaper) NightmareCrimson else DreamGold,
                onDismiss = onDismiss
            )

            Surface(
                shape = RoundedCornerShape(16.dp),
                color = paperBg,
                border = BorderStroke(1.dp, borderColor),
                modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp, max = 300.dp)
            ) {
                Box(modifier = Modifier.padding(18.dp).verticalScroll(rememberScrollState())) {
                    Text(
                        text = modal.pages.getOrElse(pageIndex) { "" },
                        style = MaterialTheme.typography.bodyLarge,
                        color = inkColor,
                        fontWeight = FontWeight.Normal
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (modal.pages.size > 1) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = { if (pageIndex > 0) pageIndex-- },
                            enabled = pageIndex > 0,
                            contentPadding = PaddingValues(horizontal = 12.dp),
                            modifier = Modifier.height(48.dp)
                        ) {
                            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад")
                        }
                        OutlinedButton(
                            onClick = { if (pageIndex < modal.pages.lastIndex) pageIndex++ },
                            enabled = pageIndex < modal.pages.lastIndex,
                            contentPadding = PaddingValues(horizontal = 12.dp),
                            modifier = Modifier.height(48.dp)
                        ) {
                            Icon(Icons.AutoMirrored.Rounded.ArrowForward, contentDescription = "Далее")
                        }
                    }
                } else {
                    Spacer(modifier = Modifier.width(1.dp))
                }

                Button(
                    onClick = onDismiss,
                    colors = ButtonDefaults.buttonColors(containerColor = DreamGold, contentColor = ObsidianVoid),
                    modifier = Modifier.height(48.dp).testTag("btn_reader_close")
                ) {
                    Text("Закрыть")
                }
            }
        }
    }
}
