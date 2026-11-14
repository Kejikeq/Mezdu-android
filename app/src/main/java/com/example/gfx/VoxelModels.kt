package com.example.gfx

import android.graphics.Color
import com.example.data.SceneProp
import com.example.data.VoxelShape
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin

/**
 * Generates batched 3D voxel geometry (positions, normals, Dream RGB, Nightmare RGB, mask & emissive)
 * for OpenGL ES 3.0 rendering.
 * Vertex stride = 14 floats:
 * [px, py, pz, nx, ny, nz, dr, dg, db, nr, ng, nb, maskFloat, emissiveFloat]
 */
object VoxelMeshBuilder {
    const val FLOATS_PER_VERTEX = 14

    private fun darken(col: Int, factor: Float): Int {
        val r = ((Color.red(col) * factor).toInt()).coerceIn(0, 255)
        val g = ((Color.green(col) * factor).toInt()).coerceIn(0, 255)
        val b = ((Color.blue(col) * factor).toInt()).coerceIn(0, 255)
        return Color.rgb(r, g, b)
    }

    private fun lighten(col: Int, factor: Float): Int {
        val r = ((Color.red(col) + (255 - Color.red(col)) * factor).toInt()).coerceIn(0, 255)
        val g = ((Color.green(col) + (255 - Color.green(col)) * factor).toInt()).coerceIn(0, 255)
        val b = ((Color.blue(col) + (255 - Color.blue(col)) * factor).toInt()).coerceIn(0, 255)
        return Color.rgb(r, g, b)
    }

    class MeshAccumulator {
        private var data = FloatArray(16384)
        var vertexCount = 0
            private set

        fun clear() {
            vertexCount = 0
        }

        private fun ensure(extraVerts: Int) {
            val needed = (vertexCount + extraVerts) * FLOATS_PER_VERTEX
            if (needed > data.size) {
                var newCap = data.size * 2
                while (newCap < needed) newCap *= 2
                data = data.copyOf(newCap)
            }
        }

        private fun putVert(
            x: Float, y: Float, z: Float,
            nx: Float, ny: Float, nz: Float,
            dr: Float, dg: Float, db: Float,
            nr: Float, ng: Float, nb: Float,
            mask: Float, emissive: Float
        ) {
            val i = vertexCount * FLOATS_PER_VERTEX
            data[i] = x; data[i + 1] = y; data[i + 2] = z
            data[i + 3] = nx; data[i + 4] = ny; data[i + 5] = nz
            data[i + 6] = dr; data[i + 7] = dg; data[i + 8] = db
            data[i + 9] = nr; data[i + 10] = ng; data[i + 11] = nb
            data[i + 12] = mask; data[i + 13] = emissive
            vertexCount++
        }

        fun addBox(
            cx: Float, baseY: Float, cz: Float,
            sx: Float, sy: Float, sz: Float,
            yaw: Float, dreamCol: Int, nightCol: Int,
            mask: Int, emissive: Boolean
        ) {
            ensure(36)
            val hx = sx * 0.5f
            val hz = sz * 0.5f
            val cy = cos(yaw)
            val syaw = sin(yaw)

            fun tx(lx: Float, lz: Float) = cx + lx * cy + lz * syaw
            fun tz(lx: Float, lz: Float) = cz - lx * syaw + lz * cy

            val dr = Color.red(dreamCol) / 255f
            val dg = Color.green(dreamCol) / 255f
            val db = Color.blue(dreamCol) / 255f
            val nr = Color.red(nightCol) / 255f
            val ng = Color.green(nightCol) / 255f
            val nb = Color.blue(nightCol) / 255f
            val mf = mask.toFloat()
            val ef = if (emissive) 1f else 0f

            val y0 = baseY
            val y1 = baseY + sy

            val p000 = floatArrayOf(tx(-hx, -hz), y0, tz(-hx, -hz))
            val p100 = floatArrayOf(tx(hx, -hz), y0, tz(hx, -hz))
            val p101 = floatArrayOf(tx(hx, hz), y0, tz(hx, hz))
            val p001 = floatArrayOf(tx(-hx, hz), y0, tz(-hx, hz))

            val p010 = floatArrayOf(tx(-hx, -hz), y1, tz(-hx, -hz))
            val p110 = floatArrayOf(tx(hx, -hz), y1, tz(hx, -hz))
            val p111 = floatArrayOf(tx(hx, hz), y1, tz(hx, hz))
            val p011 = floatArrayOf(tx(-hx, hz), y1, tz(-hx, hz))

            fun quad(a: FloatArray, b: FloatArray, c: FloatArray, d: FloatArray, nx: Float, ny: Float, nz: Float, shade: Float) {
                val rnx = nx * cy + nz * syaw
                val rnz = -nx * syaw + nz * cy
                val dR = dr * shade; val dG = dg * shade; val dB = db * shade
                val nR = nr * shade; val nG = ng * shade; val nB = nb * shade
                putVert(a[0], a[1], a[2], rnx, ny, rnz, dR, dG, dB, nR, nG, nB, mf, ef)
                putVert(b[0], b[1], b[2], rnx, ny, rnz, dR, dG, dB, nR, nG, nB, mf, ef)
                putVert(c[0], c[1], c[2], rnx, ny, rnz, dR, dG, dB, nR, nG, nB, mf, ef)
                putVert(a[0], a[1], a[2], rnx, ny, rnz, dR, dG, dB, nR, nG, nB, mf, ef)
                putVert(c[0], c[1], c[2], rnx, ny, rnz, dR, dG, dB, nR, nG, nB, mf, ef)
                putVert(d[0], d[1], d[2], rnx, ny, rnz, dR, dG, dB, nR, nG, nB, mf, ef)
            }

            // Top (+Y)
            quad(p010, p011, p111, p110, 0f, 1f, 0f, 1.0f)
            // Bottom (-Y)
            quad(p000, p100, p101, p001, 0f, -1f, 0f, 0.55f)
            // Front (+Z)
            quad(p001, p101, p111, p011, 0f, 0f, 1f, 0.88f)
            // Back (-Z)
            quad(p100, p000, p010, p110, 0f, 0f, -1f, 0.78f)
            // Right (+X)
            quad(p101, p100, p110, p111, 1f, 0f, 0f, 0.84f)
            // Left (-X)
            quad(p000, p001, p011, p010, -1f, 0f, 0f, 0.72f)
        }

        fun addProp(prop: SceneProp, timeSec: Float) {
            if (!prop.visible) return
            val x = prop.x; val y = prop.y; val z = prop.z
            val sx = prop.sx; val sy = prop.sy; val sz = prop.sz
            val yaw = prop.yaw
            val d = prop.dreamColor; val n = prop.nightColor
            val m = prop.mask

            when (prop.shape) {
                VoxelShape.BOX, VoxelShape.WATER_PLANE, VoxelShape.BRIDGE_DECK, VoxelShape.DOOR_LEAF -> {
                    addBox(x, y, z, sx, sy, sz, yaw, d, n, m, prop.emissive)
                }

                VoxelShape.LAMP -> {
                    addBox(x, y, z, 0.22f, sy - 0.3f, 0.22f, yaw, d, n, m, false)
                    addBox(x, y, z, 0.48f, 0.25f, 0.48f, yaw, darken(d, 0.8f), darken(n, 0.8f), m, false)
                }

                VoxelShape.TREE_OAK -> {
                    val trunkH = sy * 0.45f
                    addBox(x, y, z, sx * 0.34f, trunkH, sz * 0.34f, yaw, 0xFF5C3B24.toInt(), 0xFF201316.toInt(), m, false)
                    addBox(x, y + trunkH * 0.8f, z, sx * 1.45f, sy * 0.36f, sz * 1.45f, yaw + 0.2f, d, n, m, false)
                    addBox(x, y + trunkH * 0.8f + sy * 0.28f, z, sx * 1.0f, sy * 0.28f, sz * 1.0f, yaw - 0.3f, lighten(d, 0.12f), darken(n, 0.85f), m, false)
                }

                VoxelShape.TREE_PINE -> {
                    val trunkH = sy * 0.32f
                    addBox(x, y, z, sx * 0.28f, trunkH, sz * 0.28f, yaw, 0xFF4F3320.toInt(), 0xFF1D1215.toInt(), m, false)
                    addBox(x, y + trunkH * 0.7f, z, sx * 1.35f, sy * 0.28f, sz * 1.35f, yaw, d, n, m, false)
                    addBox(x, y + trunkH * 0.7f + sy * 0.24f, z, sx * 0.95f, sy * 0.28f, sz * 0.95f, yaw + 0.4f, lighten(d, 0.08f), n, m, false)
                    addBox(x, y + trunkH * 0.7f + sy * 0.48f, z, sx * 0.52f, sy * 0.26f, sz * 0.52f, yaw, lighten(d, 0.16f), darken(n, 0.85f), m, false)
                }

                VoxelShape.HOUSE_SHELL -> {
                    // Main exterior shell + pitched roof tiers
                    addBox(x, y, z, sx, sy * 0.72f, sz, yaw, d, n, m, false)
                    addBox(x, y + sy * 0.72f, z, sx * 1.08f, sy * 0.16f, sz * 1.08f, yaw, darken(d, 0.55f), darken(n, 0.6f), m, false)
                    addBox(x, y + sy * 0.88f, z, sx * 0.72f, sy * 0.16f, sz * 0.72f, yaw, darken(d, 0.48f), darken(n, 0.52f), m, false)
                    // Warm glowing front windows
                    addBox(x - sx * 0.24f, y + sy * 0.28f, z - sz * 0.505f, 0.9f, 0.9f, 0.1f, yaw, 0xFFFFD88E.toInt(), 0xFFB83A32.toInt(), m, true)
                    addBox(x + sx * 0.24f, y + sy * 0.28f, z - sz * 0.505f, 0.9f, 0.9f, 0.1f, yaw, 0xFFFFD88E.toInt(), 0xFFB83A32.toInt(), m, true)
                }

                VoxelShape.TABLE -> {
                    val topY = y + sy * 0.85f
                    addBox(x, topY, z, sx, sy * 0.15f, sz, yaw, d, n, m, false)
                    val dx = sx * 0.4f; val dz = sz * 0.4f
                    val cy = cos(yaw); val sY = sin(yaw)
                    for ((ox, oz) in listOf(-dx to -dz, dx to -dz, -dx to dz, dx to dz)) {
                        addBox(x + ox * cy + oz * sY, y, z - ox * sY + oz * cy, 0.12f, sy * 0.85f, 0.12f, yaw, darken(d, 0.8f), darken(n, 0.8f), m, false)
                    }
                }

                VoxelShape.SOFA -> {
                    addBox(x, y, z, sx, sy * 0.48f, sz, yaw, d, n, m, false)
                    val cy = cos(yaw); val sY = sin(yaw)
                    val bz = sz * 0.36f
                    addBox(x + bz * sY, y + sy * 0.48f, z + bz * cy, sx, sy * 0.52f, sz * 0.26f, yaw, darken(d, 0.85f), darken(n, 0.85f), m, false)
                }

                VoxelShape.BED -> {
                    addBox(x, y, z, sx, sy * 0.42f, sz, yaw, 0xFF6B472B.toInt(), 0xFF281918.toInt(), m, false)
                    addBox(x, y + sy * 0.42f, z, sx * 0.94f, sy * 0.32f, sz * 0.94f, yaw, d, n, m, false)
                }

                VoxelShape.BOOKSHELF, VoxelShape.DRAWERS -> {
                    addBox(x, y, z, sx, sy, sz, yaw, d, n, m, false)
                    addBox(x, y + sy * 0.2f, z, sx * 0.9f, sy * 0.6f, sz * 1.04f, yaw, darken(d, 0.72f), darken(n, 0.72f), m, false)
                }

                VoxelShape.FIREPLACE -> {
                    addBox(x, y, z, sx, sy, sz, yaw, d, n, m, false)
                    addBox(x, y + 0.15f, z, sx * 0.55f, sy * 0.45f, sz * 1.05f, yaw, 0xFFFF8C38.toInt(), 0xFFCC3322.toInt(), m, true)
                }

                VoxelShape.BENCH -> {
                    addBox(x, y + sy * 0.45f, z, sx, 0.14f, sz, yaw, d, n, m, false)
                    addBox(x, y, z, sx * 0.85f, sy * 0.45f, sz * 0.7f, yaw, darken(d, 0.75f), darken(n, 0.75f), m, false)
                }

                VoxelShape.CAR -> {
                    addBox(x, y + 0.22f, z, sx, sy * 0.48f, sz, yaw, d, n, m, false)
                    addBox(x, y + 0.22f + sy * 0.48f, z, sx * 0.55f, sy * 0.42f, sz * 0.88f, yaw, lighten(d, 0.12f), darken(n, 0.85f), m, false)
                    // 4 dark wheels
                    val cy = cos(yaw); val sY = sin(yaw)
                    val wx = sx * 0.34f; val wz = sz * 0.48f
                    for ((ox, oz) in listOf(-wx to -wz, wx to -wz, -wx to wz, wx to wz)) {
                        addBox(x + ox * cy + oz * sY, y, z - ox * sY + oz * cy, 0.55f, 0.48f, 0.28f, yaw, 0xFF1F2126.toInt(), 0xFF121015.toInt(), m, false)
                    }
                }

                VoxelShape.STONE_FACE, VoxelShape.RUNESTONE -> {
                    addBox(x, y, z, sx, sy, sz, yaw, d, n, m, prop.emissive)
                    addBox(x, y + sy * 0.68f, z, sx * 0.6f, 0.22f, sz * 1.08f, yaw, lighten(d, 0.2f), 0xFFFF4D38.toInt(), m, true)
                }

                VoxelShape.FIGURE -> {
                    // Legs, torso, head
                    addBox(x, y, z, 0.46f, 0.78f, 0.32f, yaw, darken(d, 0.65f), darken(n, 0.65f), m, false)
                    addBox(x, y + 0.78f, z, 0.58f, 0.64f, 0.36f, yaw, d, n, m, false)
                    addBox(x, y + 1.44f, z, 0.38f, 0.38f, 0.38f, yaw, 0xFFE5C4A8.toInt(), 0xFF8B6A75.toInt(), m, false)
                }

                VoxelShape.DEER -> {
                    addBox(x, y + 0.7f, z, 0.55f, 0.55f, 1.15f, yaw, d, n, m, prop.emissive)
                    val cy = cos(yaw); val sY = sin(yaw)
                    addBox(x + 0.45f * sY, y + 1.15f, z + 0.45f * cy, 0.32f, 0.55f, 0.35f, yaw, d, n, m, prop.emissive)
                    // Antlers (golden/crimson emissive highlights)
                    addBox(x + 0.48f * sY, y + 1.7f, z + 0.48f * cy, 0.9f, 0.45f, 0.22f, yaw, 0xFFF2C879.toInt(), 0xFFE0503F.toInt(), m, true)
                }

                VoxelShape.RABBIT -> {
                    addBox(x, y, z, sx, sy * 0.75f, sz, yaw, d, n, m, false)
                    addBox(x, y + sy * 0.75f, z, sx * 0.55f, sy * 0.45f, sz * 0.4f, yaw, lighten(d, 0.08f), n, m, false)
                }

                VoxelShape.CHEST -> {
                    addBox(x, y, z, sx, sy, sz, yaw, d, n, m, false)
                    addBox(x, y + sy * 0.55f, z, sx * 1.04f, 0.14f, sz * 1.04f, yaw, 0xFFF2C879.toInt(), 0xFF8B362C.toInt(), m, false)
                }

                VoxelShape.PHONE_BOOTH -> {
                    addBox(x, y, z, sx, sy, sz, yaw, d, n, m, false)
                    addBox(x, y + sy * 0.45f, z, sx * 0.72f, sy * 0.45f, sz * 1.03f, yaw, 0xFFC7E6F5.toInt(), 0xFF551D26.toInt(), m, true)
                }

                VoxelShape.ITEM_ORB -> {
                    val bob = sin(timeSec * 3.1f + x * 1.7f) * 0.10f
                    addBox(x, y + bob, z, sx, sy, sz, timeSec * 1.4f, d, n, m, true)
                }
            }
        }

        fun toFloatBuffer(): FloatBuffer {
            val byteBuf = ByteBuffer.allocateDirect(vertexCount * FLOATS_PER_VERTEX * 4)
            byteBuf.order(ByteOrder.nativeOrder())
            val fb = byteBuf.asFloatBuffer()
            fb.put(data, 0, vertexCount * FLOATS_PER_VERTEX)
            fb.position(0)
            return fb
        }
    }
}
