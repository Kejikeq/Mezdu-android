package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Backpack
import androidx.compose.material.icons.rounded.Chair
import androidx.compose.material.icons.rounded.DashboardCustomize
import androidx.compose.material.icons.rounded.DoorFront
import androidx.compose.material.icons.rounded.FlashlightOn
import androidx.compose.material.icons.rounded.Hearing
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.example.data.GameUiState
import com.example.data.InteractIcon
import com.example.ui.theme.DreamGold
import com.example.ui.theme.DreamRose
import com.example.ui.theme.DreamSky
import com.example.ui.theme.InkPrimary
import com.example.ui.theme.InkSecondary
import com.example.ui.theme.NightmareCrimson
import com.example.ui.theme.ObsidianElevated
import com.example.ui.theme.ObsidianPanel
import com.example.ui.theme.ObsidianVoid
import kotlinx.coroutines.delay
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin

private fun iconForInteract(icon: InteractIcon): ImageVector = when (icon) {
    InteractIcon.HAND -> Icons.Rounded.TouchApp
    InteractIcon.EYE -> Icons.Rounded.Visibility
    InteractIcon.KEY -> Icons.Rounded.Key
    InteractIcon.DOOR -> Icons.Rounded.DoorFront
    InteractIcon.FIRE -> Icons.Rounded.LocalFireDepartment
    InteractIcon.SOUND -> Icons.Rounded.Hearing
    InteractIcon.READ -> Icons.AutoMirrored.Rounded.MenuBook
    InteractIcon.PHOTO -> Icons.Rounded.PhotoCamera
    InteractIcon.FLASH -> Icons.Rounded.FlashlightOn
    InteractIcon.BAG -> Icons.Rounded.Backpack
    InteractIcon.COMBINE -> Icons.Rounded.DashboardCustomize
    InteractIcon.SIT -> Icons.Rounded.Chair
    InteractIcon.SUN -> Icons.Rounded.WbSunny
}

@Composable
fun HudOverlay(
    state: GameUiState,
    onJoystickMove: (Float, Float) -> Unit,
    onLookDrag: (Float, Float) -> Unit,
    onActionStart: () -> Unit,
    onActionEnd: () -> Unit,
    onToggleEye: () -> Unit,
    onToggleFlash: () -> Unit,
    onUsePhoto: () -> Unit,
    onOpenInventory: () -> Unit,
    onOpenBoard: () -> Unit,
    onTogglePause: () -> Unit
) {
    val accent = if (state.isNight) NightmareCrimson else DreamGold

    Box(modifier = Modifier.fillMaxSize()) {
        // 1. Touch Movement + Camera Look Layer
        Row(modifier = Modifier.fillMaxSize()) {
            // Left half: Look drag fallback above joystick + joystick zone at bottom-left
            Box(
                modifier = Modifier
                    .weight(0.45f)
                    .fillMaxHeight()
                    .pointerInput(Unit) {
                        detectDragGestures { change, drag ->
                            change.consume()
                            onLookDrag(drag.x, drag.y)
                        }
                    }
            )
            // Right half: Smooth camera look drag
            Box(
                modifier = Modifier
                    .weight(0.55f)
                    .fillMaxHeight()
                    .pointerInput(Unit) {
                        detectDragGestures { change, drag ->
                            change.consume()
                            onLookDrag(drag.x, drag.y)
                        }
                    }
            )
        }

        // 2. Headache / Nightmare Crimson Vignette
        if (state.headache > 0.04f || state.isNight) {
            val alpha = ((state.headache * 0.42f) + if (state.isNight) 0.16f else 0f).coerceIn(0f, 0.56f)
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.radialGradient(
                            colors = listOf(Color.Transparent, NightmareCrimson.copy(alpha = alpha)),
                            radius = 1200f
                        )
                    )
            )
        }

        // 3. Projected Screen-Space Interactable Glints
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val density = LocalDensity.current
            val wPx = with(density) { maxWidth.toPx() }
            val hPx = with(density) { maxHeight.toPx() }
            val badgePx = with(density) { 28.dp.toPx() }

            state.glints.forEach { g ->
                val xPx = (g.nx * wPx - badgePx * 0.5f).roundToInt()
                val yPx = (g.ny * hPx - badgePx * 0.5f).roundToInt()
                val glintColor = if (g.active) accent else InkPrimary.copy(alpha = 0.65f)
                Surface(
                    modifier = Modifier
                        .offset { IntOffset(xPx, yPx) }
                        .size(if (g.active) 30.dp else 22.dp),
                    shape = CircleShape,
                    color = ObsidianVoid.copy(alpha = 0.65f),
                    border = BorderStroke(if (g.active) 1.5.dp else 1.dp, glintColor)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = iconForInteract(g.icon),
                            contentDescription = null,
                            tint = glintColor,
                            modifier = Modifier.size(if (g.active) 16.dp else 12.dp)
                        )
                    }
                }
            }
        }

        // 4. Subtle Center Reticle Dot
        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .size(5.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = 0.55f))
        )

        // 5. Top HUD Row (ECG Stability + Nav Pills)
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                // ECG & World Pill
                EcgStabilityPill(state = state, accent = accent)

                // Top-right Navigation & Quick Panels
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (state.settings.showFps) {
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = ObsidianPanel.copy(alpha = 0.85f),
                            border = BorderStroke(1.dp, InkSecondary.copy(alpha = 0.25f))
                        ) {
                            Text(
                                text = "${state.fps} FPS",
                                style = MaterialTheme.typography.labelSmall,
                                color = DreamSky,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)
                            )
                        }
                    }

                    HudTopButton(
                        icon = Icons.Rounded.Backpack,
                        label = "Вещи",
                        tag = "btn_inventory",
                        accent = accent,
                        badgeCount = 0,
                        highlight = false,
                        onClick = onOpenInventory
                    )

                    HudTopButton(
                        icon = Icons.Rounded.Psychology,
                        label = "Выводы",
                        tag = "btn_board",
                        accent = accent,
                        badgeCount = state.unreadBoardCount,
                        highlight = state.canFormConclusionNow,
                        onClick = onOpenBoard
                    )

                    Surface(
                        onClick = onTogglePause,
                        shape = RoundedCornerShape(14.dp),
                        color = ObsidianPanel.copy(alpha = 0.88f),
                        border = BorderStroke(1.dp, accent.copy(alpha = 0.4f)),
                        modifier = Modifier
                            .size(48.dp)
                            .testTag("btn_pause")
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.Pause,
                                contentDescription = "Пауза",
                                tint = InkPrimary,
                                modifier = Modifier.size(22.dp)
                            )
                        }
                    }
                }
            }

            // Current Objective Banner
            if (state.objective.isNotBlank()) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = ObsidianVoid.copy(alpha = 0.72f),
                    border = BorderStroke(1.dp, accent.copy(alpha = 0.30f)),
                    modifier = Modifier.widthIn(max = 520.dp)
                ) {
                    Text(
                        text = state.objective,
                        style = MaterialTheme.typography.bodySmall,
                        color = InkPrimary.copy(alpha = 0.94f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp)
                    )
                }
            }
        }

        // 6. Toasts Stack (right below top bar)
        Column(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 74.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.End
        ) {
            state.toasts.forEach { msg ->
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = ObsidianElevated.copy(alpha = 0.92f),
                    border = BorderStroke(1.dp, DreamGold.copy(alpha = 0.45f))
                ) {
                    Text(
                        text = msg,
                        style = MaterialTheme.typography.labelMedium,
                        color = DreamGold,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp)
                    )
                }
            }
        }

        // 7. Dialogue / Narrative Subtitles
        AnimatedVisibility(
            visible = !state.subtitleText.isNullOrBlank(),
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 148.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = ObsidianVoid.copy(alpha = 0.86f),
                border = BorderStroke(1.dp, accent.copy(alpha = 0.35f)),
                modifier = Modifier.widthIn(max = 560.dp)
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    if (!state.subtitleSpeaker.isNullOrBlank()) {
                        Text(
                            text = state.subtitleSpeaker.uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            color = accent,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                    }
                    Text(
                        text = state.subtitleText.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = InkPrimary,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }

        // 8. Bottom-Left Virtual Movement Joystick
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .navigationBarsPadding()
                .padding(start = 24.dp, bottom = 24.dp)
        ) {
            VirtualJoystick(
                accent = accent,
                onMove = onJoystickMove
            )
        }

        // 9. Bottom-Right Interaction & Ability Cluster
        Column(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 20.dp, bottom = 24.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Contextual Action Button
            if (state.nearbyPrompt != null) {
                PrimaryActionButton(
                    prompt = state.nearbyPrompt,
                    icon = iconForInteract(state.nearbyIcon),
                    holdDuration = state.nearbyHoldDuration,
                    holdProgress = state.holdProgress,
                    accent = accent,
                    onPressStart = onActionStart,
                    onPressEnd = onActionEnd
                )
            }

            // Ability Buttons Row
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (state.hasMemoryPhoto) {
                    AbilityPillButton(
                        icon = Icons.Rounded.PhotoCamera,
                        label = "Фото",
                        tag = "btn_photo",
                        active = false,
                        activeColor = DreamRose,
                        onClick = onUsePhoto
                    )
                }
                if (state.hasFlashlight) {
                    AbilityPillButton(
                        icon = Icons.Rounded.FlashlightOn,
                        label = "Свет",
                        tag = "btn_flash",
                        active = state.flashOn,
                        activeColor = DreamGold,
                        onClick = onToggleFlash
                    )
                }
                if (state.canPeerEye) {
                    AbilityPillButton(
                        icon = if (state.peering) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                        label = if (state.peering) "Закрыть" else "Глаз",
                        tag = "btn_eye",
                        active = state.peering || state.isNight,
                        activeColor = NightmareCrimson,
                        onClick = onToggleEye
                    )
                }
            }
        }

        // 10. Chapter Title Card Overlay
        AnimatedVisibility(
            visible = state.showChapterCard,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Surface(
                shape = RoundedCornerShape(22.dp),
                color = ObsidianVoid.copy(alpha = 0.88f),
                border = BorderStroke(1.dp, DreamGold.copy(alpha = 0.45f)),
                modifier = Modifier.padding(horizontal = 24.dp)
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 22.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = state.chapterKicker.uppercase(),
                        style = MaterialTheme.typography.labelMedium,
                        color = DreamGold
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = state.chapterTitle,
                        style = MaterialTheme.typography.headlineMedium,
                        color = InkPrimary,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
    }
}

@Composable
private fun EcgStabilityPill(state: GameUiState, accent: Color) {
    var phase by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(state.heartRateBpm) {
        while (true) {
            delay(32L)
            val step = (state.heartRateBpm / 60f) * 0.08f
            phase = (phase + step) % 1f
        }
    }

    Surface(
        shape = RoundedCornerShape(16.dp),
        color = ObsidianPanel.copy(alpha = 0.88f),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.45f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Canvas(modifier = Modifier.size(width = 48.dp, height = 24.dp)) {
                val p = Path()
                val mid = size.height * 0.55f
                for (i in 0..24) {
                    val t = i / 24f
                    val u = ((t - phase) + 1f) % 1f
                    val spike = when {
                        u in 0.18f..0.24f -> -0.25f
                        u in 0.24f..0.30f -> -0.95f
                        u in 0.30f..0.36f -> 0.55f
                        u in 0.44f..0.54f -> -0.20f * sin((u - 0.44f) * 31.4f)
                        else -> 0f
                    }
                    val x = t * size.width
                    val y = mid + spike * (size.height * 0.45f)
                    if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
                }
                drawPath(p, color = accent, style = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round))
            }

            Column {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = if (state.isNight) "КОШМАР" else "СОН",
                        style = MaterialTheme.typography.labelSmall,
                        color = accent,
                        fontWeight = FontWeight.Bold
                    )
                    if (state.nightTimerRemaining > 0.1f) {
                        Text(
                            text = "${state.nightTimerRemaining.roundToInt()}с",
                            style = MaterialTheme.typography.labelSmall,
                            color = NightmareCrimson
                        )
                    }
                }
                Text(
                    text = "${state.stability.roundToInt()}% · ${state.heartRateBpm} уд/м",
                    style = MaterialTheme.typography.labelMedium,
                    color = InkPrimary
                )
            }
        }
    }
}

@Composable
private fun HudTopButton(
    icon: ImageVector,
    label: String,
    tag: String,
    accent: Color,
    badgeCount: Int,
    highlight: Boolean,
    onClick: () -> Unit
) {
    val borderColor = if (highlight) DreamRose else accent.copy(alpha = 0.4f)
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        color = ObsidianPanel.copy(alpha = 0.88f),
        border = BorderStroke(if (highlight) 1.5.dp else 1.dp, borderColor),
        modifier = Modifier
            .height(48.dp)
            .testTag(tag)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            BadgedBox(
                badge = {
                    if (badgeCount > 0 || highlight) {
                        Badge(containerColor = DreamRose, contentColor = ObsidianVoid) {
                            Text(if (badgeCount > 0) "$badgeCount" else "!")
                        }
                    }
                }
            ) {
                Icon(imageVector = icon, contentDescription = label, tint = accent, modifier = Modifier.size(20.dp))
            }
            Text(text = label, style = MaterialTheme.typography.labelMedium, color = InkPrimary)
        }
    }
}

@Composable
private fun PrimaryActionButton(
    prompt: String,
    icon: ImageVector,
    holdDuration: Float,
    holdProgress: Float,
    accent: Color,
    onPressStart: () -> Unit,
    onPressEnd: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = ObsidianElevated.copy(alpha = 0.94f),
        border = BorderStroke(1.5.dp, accent),
        modifier = Modifier
            .height(54.dp)
            .testTag("btn_action")
            .pointerInput(prompt, holdDuration) {
                detectTapGestures(
                    onPress = {
                        onPressStart()
                        tryAwaitRelease()
                        onPressEnd()
                    }
                )
            }
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(30.dp)) {
                if (holdDuration > 0f && holdProgress > 0f) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        drawArc(
                            color = accent,
                            startAngle = -90f,
                            sweepAngle = 360f * holdProgress.coerceIn(0f, 1f),
                            useCenter = false,
                            style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round)
                        )
                    }
                }
                Icon(imageVector = icon, contentDescription = prompt, tint = accent, modifier = Modifier.size(20.dp))
            }
            Text(
                text = if (holdDuration > 0f) "$prompt (удерживать)" else prompt,
                style = MaterialTheme.typography.labelLarge,
                color = InkPrimary
            )
        }
    }
}

@Composable
private fun AbilityPillButton(
    icon: ImageVector,
    label: String,
    tag: String,
    active: Boolean,
    activeColor: Color,
    onClick: () -> Unit
) {
    FilledTonalButton(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = if (active) activeColor.copy(alpha = 0.25f) else ObsidianPanel.copy(alpha = 0.88f),
            contentColor = if (active) activeColor else InkPrimary
        ),
        border = BorderStroke(1.dp, if (active) activeColor else InkSecondary.copy(alpha = 0.35f)),
        modifier = Modifier
            .height(48.dp)
            .testTag(tag)
    ) {
        Icon(imageVector = icon, contentDescription = label, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(6.dp))
        Text(text = label, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
private fun VirtualJoystick(
    accent: Color,
    onMove: (Float, Float) -> Unit
) {
    val radiusDp = 58.dp
    val knobDp = 44.dp
    var knobOffset by remember { mutableStateOf(Offset.Zero) }
    val maxRadiusPx = with(LocalDensity.current) { 38.dp.toPx() }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(radiusDp * 2)
            .clip(CircleShape)
            .background(ObsidianVoid.copy(alpha = 0.48f))
            .border(1.5.dp, accent.copy(alpha = 0.40f), CircleShape)
            .testTag("virtual_joystick")
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { },
                    onDragEnd = {
                        knobOffset = Offset.Zero
                        onMove(0f, 0f)
                    },
                    onDragCancel = {
                        knobOffset = Offset.Zero
                        onMove(0f, 0f)
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        val raw = knobOffset + dragAmount
                        val len = hypot(raw.x, raw.y)
                        knobOffset = if (len > maxRadiusPx && len > 0.001f) {
                            raw * (maxRadiusPx / len)
                        } else {
                            raw
                        }
                        onMove((knobOffset.x / maxRadiusPx).coerceIn(-1f, 1f), (knobOffset.y / maxRadiusPx).coerceIn(-1f, 1f))
                    }
                )
            }
    ) {
        Surface(
            modifier = Modifier
                .offset { IntOffset(knobOffset.x.roundToInt(), knobOffset.y.roundToInt()) }
                .size(knobDp),
            shape = CircleShape,
            color = accent.copy(alpha = 0.85f),
            shadowElevation = 6.dp
        ) {}
    }
}
