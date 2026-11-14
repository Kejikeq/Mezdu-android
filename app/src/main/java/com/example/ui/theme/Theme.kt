package com.example.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

private val MezhduColorScheme = darkColorScheme(
    primary = DreamGold,
    onPrimary = ObsidianVoid,
    primaryContainer = ObsidianElevated,
    onPrimaryContainer = DreamGold,
    secondary = DreamRose,
    onSecondary = ObsidianVoid,
    secondaryContainer = ObsidianPanel,
    onSecondaryContainer = DreamRose,
    tertiary = NightmareCrimson,
    onTertiary = InkPrimary,
    background = ObsidianVoid,
    onBackground = InkPrimary,
    surface = ObsidianSurface,
    onSurface = InkPrimary,
    surfaceVariant = ObsidianPanel,
    onSurfaceVariant = InkSecondary,
    outline = PanelBorder,
    outlineVariant = PanelBorderSubtle,
    error = NightmareCrimson,
    onError = InkPrimary
)

private val MezhduShapes = Shapes(
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp)
)

@Composable
fun MezhduTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = MezhduColorScheme,
        typography = MezhduTypography,
        shapes = MezhduShapes,
        content = content
    )
}
