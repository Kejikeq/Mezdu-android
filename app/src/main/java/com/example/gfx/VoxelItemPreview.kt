package com.example.gfx

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

private data class VoxelBlock(
    val x: Float,
    val y: Float,
    val z: Float,
    val sx: Float,
    val sy: Float,
    val sz: Float,
    val color: Color
)

private fun buildPreviewBlocks(modelId: String): List<VoxelBlock> {
    return when {
        modelId.contains("key") -> {
            val metal = when {
                modelId.contains("gold") -> Color(0xFFF2C879)
                modelId.contains("car_key_rust") -> Color(0xFF7B4836)
                modelId.contains("car_key") -> Color(0xFFC8CDD4)
                else -> Color(0xFF9C7B52)
            }
            val list = mutableListOf(
                VoxelBlock(0f, 0f, -0.45f, 0.42f, 0.14f, 0.42f, metal), // Bow ring
                VoxelBlock(0f, 0f, 0.18f, 0.14f, 0.12f, 0.85f, metal),  // Shaft
                VoxelBlock(0.14f, 0f, 0.45f, 0.22f, 0.12f, 0.12f, metal), // Tooth 1
                VoxelBlock(0.12f, 0f, 0.26f, 0.18f, 0.12f, 0.10f, metal)  // Tooth 2
            )
            if (modelId.contains("car_key")) {
                // Deer fob
                list.add(VoxelBlock(-0.18f, 0.05f, -0.78f, 0.24f, 0.10f, 0.26f, Color(0xFFD4A259)))
            }
            list
        }

        modelId.contains("photo") -> listOf(
            VoxelBlock(0f, 0f, 0f, 0.96f, 0.08f, 0.76f, Color(0xFF6B472C)), // Frame
            VoxelBlock(0f, 0.05f, 0f, 0.80f, 0.04f, 0.60f, if (modelId.contains("final")) Color(0xFFEBD9BA) else Color(0xFFB4C5D4)),
            VoxelBlock(-0.14f, 0.08f, 0f, 0.18f, 0.04f, 0.26f, Color(0xFF3E6A96)),
            VoxelBlock(0.16f, 0.08f, 0.04f, 0.16f, 0.04f, 0.24f, if (modelId.contains("photo_2")) Color(0xFF8C2A2A) else Color(0xFFD98B6C))
        )

        modelId.contains("letter") || modelId.contains("note") || modelId.contains("student_card") || modelId.contains("rune_map") || modelId.contains("map") -> {
            val paper = when {
                modelId.contains("night") && !modelId.contains("student") -> Color(0xFF34242A)
                modelId.contains("student_card") -> Color(0xFFD9E3ED)
                modelId.contains("map_night") -> Color(0xFF282028)
                else -> Color(0xFFEDE0C4)
            }
            val accent = when {
                modelId.contains("map") -> Color(0xFFE0503F)
                modelId.contains("student_card") -> Color(0xFF3D6FA3)
                else -> Color(0xFF8C3B32)
            }
            listOf(
                VoxelBlock(0f, 0f, 0f, 0.92f, 0.05f, 1.12f, paper),
                VoxelBlock(-0.12f, 0.04f, -0.22f, 0.50f, 0.02f, 0.08f, accent),
                VoxelBlock(0.02f, 0.04f, 0.04f, 0.62f, 0.02f, 0.06f, Color(0xFF5C4E42)),
                VoxelBlock(-0.08f, 0.04f, 0.26f, 0.44f, 0.02f, 0.06f, Color(0xFF5C4E42))
            )
        }

        modelId.contains("locket") -> listOf(
            VoxelBlock(0f, 0f, 0f, 0.58f, 0.16f, 0.58f, Color(0xFFF2C879)),
            VoxelBlock(0f, 0.10f, 0f, 0.36f, 0.04f, 0.36f, Color(0xFF8E5538)),
            VoxelBlock(0f, 0.02f, -0.36f, 0.14f, 0.08f, 0.16f, Color(0xFFD4A259))
        )

        modelId.contains("petal") -> {
            val col = if (modelId.contains("black")) Color(0xFF241C22) else Color(0xFFF6A6B9)
            listOf(
                VoxelBlock(0f, 0f, 0f, 0.36f, 0.08f, 0.68f, col),
                VoxelBlock(0.08f, 0.05f, -0.14f, 0.24f, 0.06f, 0.34f, col.copy(alpha = 0.9f))
            )
        }

        modelId.contains("cassette") -> listOf(
            VoxelBlock(0f, 0f, 0f, 0.96f, 0.18f, 0.62f, Color(0xFF2C2A32)),
            VoxelBlock(0f, 0.10f, -0.05f, 0.78f, 0.04f, 0.34f, Color(0xFFE6D4B8)),
            VoxelBlock(-0.22f, 0.13f, -0.05f, 0.16f, 0.04f, 0.16f, Color(0xFFF2C879)),
            VoxelBlock(0.22f, 0.13f, -0.05f, 0.16f, 0.04f, 0.16f, Color(0xFFF2C879))
        )

        modelId.contains("flashlight") -> {
            val lit = modelId.contains("lit")
            listOf(
                VoxelBlock(0f, 0f, 0.1f, 0.24f, 0.24f, 0.78f, Color(0xFF3E444D)),
                VoxelBlock(0f, 0f, -0.34f, 0.36f, 0.36f, 0.20f, Color(0xFF636B75)),
                VoxelBlock(0f, 0f, -0.46f, 0.28f, 0.28f, 0.05f, if (lit) Color(0xFFFFE599) else Color(0xFF8FA0B0))
            )
        }

        modelId.contains("license_plate") -> listOf(
            VoxelBlock(0f, 0f, 0f, 1.15f, 0.42f, 0.08f, Color(0xFFCFD6DC)),
            VoxelBlock(-0.34f, 0f, 0.05f, 0.14f, 0.24f, 0.03f, Color(0xFF1F2329)),
            VoxelBlock(-0.12f, 0f, 0.05f, 0.14f, 0.24f, 0.03f, Color(0xFFE0503F)),
            VoxelBlock(0.10f, 0f, 0.05f, 0.14f, 0.24f, 0.03f, Color(0xFF1F2329)),
            VoxelBlock(0.32f, 0f, 0.05f, 0.14f, 0.24f, 0.03f, Color(0xFF1F2329))
        )

        modelId.contains("shard") || modelId.contains("crowbar") -> listOf(
            VoxelBlock(0f, 0f, 0f, 0.24f, 0.08f, 0.98f, Color(0xFF98A0AA)),
            VoxelBlock(0.08f, 0.02f, -0.18f, 0.18f, 0.08f, 0.42f, if (modelId.contains("shiny")) Color(0xFFE0503F) else Color(0xFF8C2E28))
        )

        modelId.contains("carved_stone") || modelId.contains("runestone") -> {
            val glow = when {
                modelId.contains("sun") -> Color(0xFFE05544)
                modelId.contains("moon") -> Color(0xFF4C8BE0)
                modelId.contains("wave") -> Color(0xFFE8C44C)
                modelId.contains("leaf") -> Color(0xFF54B868)
                modelId.contains("plain") -> Color(0xFF888C92)
                else -> Color(0xFFE0503F)
            }
            listOf(
                VoxelBlock(0f, 0f, 0f, 0.68f, 0.34f, 0.68f, Color(0xFF5A5D66)),
                VoxelBlock(0f, 0.19f, 0f, 0.34f, 0.06f, 0.34f, glow)
            )
        }

        modelId.contains("mike_head") -> {
            val isBlack = modelId.contains("black")
            val skin = if (isBlack) Color(0xFF33272E) else Color(0xFFE8C4A8)
            val hair = if (isBlack) Color(0xFF151015) else Color(0xFF473022)
            val eyes = if (isBlack) Color(0xFFE0503F) else Color(0xFF2B3A4A)
            listOf(
                VoxelBlock(0f, 0f, 0f, 0.62f, 0.62f, 0.62f, skin),
                VoxelBlock(0f, 0.26f, -0.02f, 0.66f, 0.22f, 0.66f, hair),
                VoxelBlock(-0.15f, 0.06f, 0.32f, 0.10f, 0.09f, 0.05f, eyes),
                VoxelBlock(0.15f, 0.06f, 0.32f, 0.10f, 0.09f, 0.05f, eyes)
            )
        }

        modelId.contains("chest") -> listOf(
            VoxelBlock(0f, -0.08f, 0f, 0.92f, 0.46f, 0.64f, Color(0xFF6B472B)),
            VoxelBlock(0f, 0.20f, 0f, 0.96f, 0.16f, 0.68f, Color(0xFF8C5F3B)),
            VoxelBlock(0f, 0.12f, 0.34f, 0.18f, 0.16f, 0.06f, Color(0xFFF2C879))
        )

        modelId.contains("firewood") -> listOf(
            VoxelBlock(-0.16f, 0f, 0f, 0.22f, 0.22f, 0.88f, Color(0xFF8A5D3B)),
            VoxelBlock(0.16f, 0f, 0f, 0.22f, 0.22f, 0.88f, Color(0xFF754D2E)),
            VoxelBlock(0f, 0.20f, 0f, 0.24f, 0.22f, 0.88f, Color(0xFFD9CDB8))
        )

        else -> listOf(
            VoxelBlock(0f, 0f, 0f, 0.56f, 0.56f, 0.56f, Color(0xFFF2C879)),
            VoxelBlock(0f, 0.32f, 0f, 0.34f, 0.12f, 0.34f, Color(0xFFD4A259))
        )
    }
}

@Composable
fun VoxelItemPreviewCanvas(
    modelId: String,
    modifier: Modifier = Modifier,
    interactive: Boolean = true
) {
    var yaw by remember(modelId) { mutableFloatStateOf(0.55f) }
    var pitch by remember(modelId) { mutableFloatStateOf(-0.42f) }
    val blocks = remember(modelId) { buildPreviewBlocks(modelId) }

    Canvas(
        modifier = modifier.then(
            if (interactive) {
                Modifier.pointerInput(modelId) {
                    detectDragGestures { change, dragAmount ->
                        change.consume()
                        yaw += dragAmount.x * 0.012f
                        pitch = (pitch - dragAmount.y * 0.010f).coerceIn(-1.25f, 0.45f)
                    }
                }
            } else Modifier
        )
    ) {
        val scale = min(size.width, size.height) * 0.42f
        val cx = size.width * 0.5f
        val cy = size.height * 0.54f

        val cosY = cos(yaw); val sinY = sin(yaw)
        val cosP = cos(pitch); val sinP = sin(pitch)

        fun project(x: Float, y: Float, z: Float): Pair<Offset, Float> {
            val rx = x * cosY + z * sinY
            val rz1 = -x * sinY + z * cosY
            val ry = y * cosP - rz1 * sinP
            val rz = y * sinP + rz1 * cosP
            return Offset(cx + rx * scale, cy - ry * scale) to rz
        }

        data class Face(val pts: List<Offset>, val depth: Float, val color: Color)

        val faces = mutableListOf<Face>()
        for (b in blocks) {
            val hx = b.sx * 0.5f; val hy = b.sy * 0.5f; val hz = b.sz * 0.5f
            val x0 = b.x - hx; val x1 = b.x + hx
            val y0 = b.y - hy; val y1 = b.y + hy
            val z0 = b.z - hz; val z1 = b.z + hz

            val corners = listOf(
                floatArrayOf(x0, y0, z0), floatArrayOf(x1, y0, z0),
                floatArrayOf(x1, y1, z0), floatArrayOf(x0, y1, z0),
                floatArrayOf(x0, y0, z1), floatArrayOf(x1, y0, z1),
                floatArrayOf(x1, y1, z1), floatArrayOf(x0, y1, z1)
            ).map { project(it[0], it[1], it[2]) }

            fun addFace(i0: Int, i1: Int, i2: Int, i3: Int, nx: Float, ny: Float, nz: Float, shade: Float) {
                // Backface check in rotated view space
                val rnx = nx * cosY + nz * sinY
                val rnz1 = -nx * sinY + nz * cosY
                val rnz = ny * sinP + rnz1 * cosP
                if (rnz < -0.05f) return
                val avgDepth = (corners[i0].second + corners[i1].second + corners[i2].second + corners[i3].second) * 0.25f
                faces.add(
                    Face(
                        listOf(corners[i0].first, corners[i1].first, corners[i2].first, corners[i3].first),
                        avgDepth,
                        Color(
                            red = (b.color.red * shade).coerceIn(0f, 1f),
                            green = (b.color.green * shade).coerceIn(0f, 1f),
                            blue = (b.color.blue * shade).coerceIn(0f, 1f),
                            alpha = b.color.alpha
                        )
                    )
                )
            }

            addFace(3, 2, 6, 7, 0f, 1f, 0f, 1.0f)   // Top
            addFace(0, 1, 5, 4, 0f, -1f, 0f, 0.55f) // Bottom
            addFace(4, 5, 6, 7, 0f, 0f, 1f, 0.88f)  // Front
            addFace(1, 0, 3, 2, 0f, 0f, -1f, 0.72f) // Back
            addFace(5, 1, 2, 6, 1f, 0f, 0f, 0.82f)  // Right
            addFace(0, 4, 7, 3, -1f, 0f, 0f, 0.68f) // Left
        }

        faces.sortBy { it.depth }
        for (f in faces) {
            val path = Path().apply {
                moveTo(f.pts[0].x, f.pts[0].y)
                lineTo(f.pts[1].x, f.pts[1].y)
                lineTo(f.pts[2].x, f.pts[2].y)
                lineTo(f.pts[3].x, f.pts[3].y)
                close()
            }
            drawPath(path, f.color)
        }
    }
}
