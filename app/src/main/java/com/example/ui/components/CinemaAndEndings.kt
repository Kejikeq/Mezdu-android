package com.example.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.R
import com.example.data.EndingState
import com.example.data.GameUiState
import com.example.data.MemoryVector
import com.example.gfx.VoxelItemPreviewCanvas
import com.example.ui.theme.DenialColor
import com.example.ui.theme.DreamGold
import com.example.ui.theme.DreamRose
import com.example.ui.theme.InkPrimary
import com.example.ui.theme.InkSecondary
import com.example.ui.theme.ObsidianPanel
import com.example.ui.theme.ObsidianVoid
import com.example.ui.theme.PanelBorder
import com.example.ui.theme.ProjectionColor
import com.example.ui.theme.TruthColor

@Composable
fun CinemaOverlay(
    state: GameUiState,
    onSkip: () -> Unit
) {
    val bgColor by animateColorAsState(
        targetValue = if (state.cinemaLight) Color(0xFFF3EBDD) else ObsidianVoid,
        label = "cinema_bg"
    )
    val textColor = if (state.cinemaLight) Color(0xFF1E1915) else InkPrimary
    val accent = if (state.cinemaLight) Color(0xFF8C6226) else DreamGold

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(bgColor.copy(alpha = if (state.showChapterCard && !state.cinemaLight) 0.92f else 0.96f))
            .safeDrawingPadding()
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier.align(Alignment.Center).widthIn(max = 580.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (state.isLoadingChapter) {
                CircularProgressIndicator(color = DreamGold)
            }

            if (state.showChapterCard) {
                Text(
                    text = state.chapterKicker.uppercase(),
                    style = MaterialTheme.typography.labelLarge,
                    color = accent
                )
                Text(
                    text = state.chapterTitle,
                    style = MaterialTheme.typography.displaySmall,
                    color = textColor,
                    textAlign = TextAlign.Center
                )
            }

            state.cinemaLines.forEach { line ->
                Text(
                    text = line,
                    style = MaterialTheme.typography.headlineSmall,
                    color = textColor,
                    textAlign = TextAlign.Center
                )
            }

            state.subtitleText?.let { sub ->
                Text(
                    text = sub,
                    style = MaterialTheme.typography.bodyLarge,
                    color = textColor,
                    textAlign = TextAlign.Center
                )
            }
        }

        if (state.cinemaCanSkip) {
            OutlinedButton(
                onClick = onSkip,
                border = BorderStroke(1.dp, accent.copy(alpha = 0.6f)),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .height(48.dp)
                    .testTag("btn_skip_intro")
            ) {
                Text("Пропустить", color = textColor)
            }
        }
    }
}

@Composable
fun EndingOverlay(
    ending: EndingState,
    onFinish: () -> Unit
) {
    val accent = when (ending.vector) {
        MemoryVector.TRUTH -> TruthColor
        MemoryVector.DENIAL -> DenialColor
        MemoryVector.PROJECTION -> ProjectionColor
        null -> DreamRose
    }

    Box(modifier = Modifier.fillMaxSize()) {
        if (ending.isTruthWithEpilogue) {
            Image(
                painter = painterResource(id = R.drawable.img_ward_dawn),
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
                                ObsidianVoid.copy(alpha = 0.62f),
                                ObsidianVoid.copy(alpha = 0.88f)
                            )
                        )
                    )
            )
        } else {
            Box(modifier = Modifier.fillMaxSize().background(ObsidianVoid))
        }

        Surface(
            shape = RoundedCornerShape(26.dp),
            color = ObsidianPanel.copy(alpha = 0.92f),
            border = BorderStroke(1.dp, accent.copy(alpha = 0.55f)),
            modifier = Modifier
                .align(Alignment.Center)
                .safeDrawingPadding()
                .padding(20.dp)
                .widthIn(max = 520.dp)
                .fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = ending.kicker.uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    color = accent,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = ending.title,
                    style = MaterialTheme.typography.headlineMedium,
                    color = InkPrimary,
                    textAlign = TextAlign.Center
                )
                Text(
                    text = ending.subtitle,
                    style = MaterialTheme.typography.labelMedium,
                    color = InkSecondary,
                    textAlign = TextAlign.Center
                )

                Surface(
                    shape = RoundedCornerShape(18.dp),
                    color = ObsidianVoid.copy(alpha = 0.85f),
                    border = BorderStroke(1.dp, PanelBorder),
                    modifier = Modifier.fillMaxWidth().height(170.dp)
                ) {
                    VoxelItemPreviewCanvas(modelId = ending.modelId, modifier = Modifier.fillMaxSize())
                }

                Text(
                    text = ending.description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = InkPrimary,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(4.dp))

                Button(
                    onClick = onFinish,
                    colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = ObsidianVoid),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(52.dp).testTag("btn_ending_finish")
                ) {
                    Text(ending.buttonLabel, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}
