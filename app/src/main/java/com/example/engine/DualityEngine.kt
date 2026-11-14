package com.example.engine

import com.example.data.Vec3
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

data class WaveState(
    var active: Boolean = false,
    var from: Int = 0,
    var to: Int = 0,
    var cx: Float = 0f,
    var cy: Float = 0f,
    var cz: Float = 0f,
    var radius: Float = 0f,
    var speed: Float = 34f,
    var outerCx: Float = 0f,
    var outerCy: Float = 0f,
    var outerCz: Float = 0f,
    var outerRadius: Float = 0f
)

data class AnchorBubble(
    val x: Float,
    val y: Float,
    val z: Float,
    val r: Float,
    val cond: () -> Boolean = { true }
)

data class SkyPreset(
    val sunDir: FloatArray,
    val sunColor: FloatArray,
    val zenith: FloatArray,
    val horizon: FloatArray,
    val ground: FloatArray,
    val glow: FloatArray,
    val away: FloatArray,
    val fog: FloatArray, // r, g, b, density
    val dark: Float
)

object SkyPresets {
    private fun dir(x: Float, y: Float, z: Float): FloatArray {
        val l = hypot(hypot(x, y), z).coerceAtLeast(1e-4f)
        return floatArrayOf(x / l, y / l, z / l)
    }

    val MORNING = SkyPreset(
        sunDir = dir(0.78f, 0.30f, 0.55f),
        sunColor = floatArrayOf(1.35f, 1.18f, 0.92f),
        zenith = floatArrayOf(0.28f, 0.44f, 0.74f),
        horizon = floatArrayOf(0.86f, 0.80f, 0.72f),
        ground = floatArrayOf(0.16f, 0.14f, 0.11f),
        glow = floatArrayOf(1.0f, 0.80f, 0.50f),
        away = floatArrayOf(0.62f, 0.70f, 0.82f),
        fog = floatArrayOf(0.45f, 0.42f, 0.39f, 0.015f),
        dark = 0.0f
    )

    val DAY = SkyPreset(
        sunDir = dir(0.45f, 0.72f, 0.52f),
        sunColor = floatArrayOf(1.30f, 1.24f, 1.15f),
        zenith = floatArrayOf(0.24f, 0.46f, 0.85f),
        horizon = floatArrayOf(0.74f, 0.84f, 0.96f),
        ground = floatArrayOf(0.16f, 0.16f, 0.14f),
        glow = floatArrayOf(0.95f, 0.88f, 0.70f),
        away = floatArrayOf(0.68f, 0.80f, 0.94f),
        fog = floatArrayOf(0.42f, 0.45f, 0.49f, 0.014f),
        dark = 0.0f
    )

    val OVERCAST = SkyPreset(
        sunDir = dir(0.4f, 0.7f, 0.5f),
        sunColor = floatArrayOf(0.55f, 0.56f, 0.58f),
        zenith = floatArrayOf(0.38f, 0.41f, 0.46f),
        horizon = floatArrayOf(0.52f, 0.54f, 0.57f),
        ground = floatArrayOf(0.12f, 0.12f, 0.11f),
        glow = floatArrayOf(0.22f, 0.22f, 0.24f),
        away = floatArrayOf(0.48f, 0.50f, 0.54f),
        fog = floatArrayOf(0.38f, 0.40f, 0.42f, 0.024f),
        dark = 0.2f
    )

    val DUSK = SkyPreset(
        sunDir = dir(-0.7f, 0.15f, 0.5f),
        sunColor = floatArrayOf(0.55f, 0.42f, 0.48f),
        zenith = floatArrayOf(0.10f, 0.13f, 0.24f),
        horizon = floatArrayOf(0.48f, 0.34f, 0.30f),
        ground = floatArrayOf(0.06f, 0.05f, 0.06f),
        glow = floatArrayOf(0.55f, 0.32f, 0.22f),
        away = floatArrayOf(0.18f, 0.21f, 0.32f),
        fog = floatArrayOf(0.18f, 0.17f, 0.21f, 0.026f),
        dark = 0.72f
    )

    val SUNSET = SkyPreset(
        sunDir = dir(-0.82f, 0.15f, 0.4f),
        sunColor = floatArrayOf(1.35f, 0.75f, 0.38f),
        zenith = floatArrayOf(0.16f, 0.24f, 0.52f),
        horizon = floatArrayOf(0.95f, 0.50f, 0.24f),
        ground = floatArrayOf(0.13f, 0.09f, 0.06f),
        glow = floatArrayOf(1.1f, 0.55f, 0.22f),
        away = floatArrayOf(0.42f, 0.36f, 0.52f),
        fog = floatArrayOf(0.44f, 0.30f, 0.24f, 0.018f),
        dark = 0.45f
    )

    val NIGHT = SkyPreset(
        sunDir = dir(-0.35f, 0.62f, -0.5f),
        sunColor = floatArrayOf(0.28f, 0.34f, 0.50f),
        zenith = floatArrayOf(0.03f, 0.04f, 0.09f),
        horizon = floatArrayOf(0.07f, 0.09f, 0.16f),
        ground = floatArrayOf(0.02f, 0.02f, 0.03f),
        glow = floatArrayOf(0.12f, 0.15f, 0.22f),
        away = floatArrayOf(0.05f, 0.07f, 0.13f),
        fog = floatArrayOf(0.05f, 0.06f, 0.10f, 0.026f),
        dark = 0.92f
    )

    val NIGHTMARE = SkyPreset(
        sunDir = dir(0.78f, 0.30f, 0.55f),
        sunColor = floatArrayOf(0.65f, 0.16f, 0.12f),
        zenith = floatArrayOf(0.05f, 0.025f, 0.055f),
        horizon = floatArrayOf(0.22f, 0.045f, 0.035f),
        ground = floatArrayOf(0.035f, 0.015f, 0.018f),
        glow = floatArrayOf(0.72f, 0.12f, 0.06f),
        away = floatArrayOf(0.11f, 0.025f, 0.028f),
        fog = floatArrayOf(0.10f, 0.035f, 0.035f, 0.032f),
        dark = 1.0f
    )

    fun dreamForChapter(chapter: Int): SkyPreset = when (chapter) {
        1 -> MORNING
        2, 3 -> DAY
        4 -> OVERCAST
        5 -> DUSK
        6 -> MORNING
        7 -> DAY
        8 -> SUNSET
        9 -> NIGHT
        10 -> DUSK
        else -> DAY
    }
}

class DualityEngine {
    var base: Int = 0
    val wave = WaveState()
    val anchors = mutableListOf<AnchorBubble>()
    var stability: Float = 100f
    var nightTimer: Float = 0f
    var flickerTimer: Float = 0f
    var flickerNext: Float = 0f
    var baseNight: Boolean = false
    var onFlip: ((toWorld: Int, quiet: Boolean) -> Unit)? = null

    val drainPerSec = 2.2f
    val regenPerSec = 1.5f

    val targetWorld: Int
        get() = if (wave.active) wave.to else base

    fun reset() {
        base = 0
        wave.active = false
        wave.outerRadius = 0f
        anchors.clear()
        stability = 100f
        nightTimer = 0f
        flickerTimer = 0f
        flickerNext = 0f
        baseNight = false
    }

    private fun hash3(ix: Int, iy: Int, iz: Int): Float {
        var n = ix * 374761393 + iy * 668265263 + iz * 2147483647
        n = (n xor (n shr 13)) * 1274126177
        return ((n xor (n shr 16)) ushr 0).toFloat() / 4294967295.0f
    }

    fun vnoise3(x: Float, y: Float, z: Float): Float {
        val ix = floor(x).toInt()
        val iy = floor(y).toInt()
        val iz = floor(z).toInt()
        val fx = x - ix
        val fy = y - iy
        val fz = z - iz
        val ux = fx * fx * (3f - 2f * fx)
        val uy = fy * fy * (3f - 2f * fy)
        val uz = fz * fz * (3f - 2f * fz)
        fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t
        val n000 = hash3(ix, iy, iz)
        val n100 = hash3(ix + 1, iy, iz)
        val n010 = hash3(ix, iy + 1, iz)
        val n110 = hash3(ix + 1, iy + 1, iz)
        val n001 = hash3(ix, iy, iz + 1)
        val n101 = hash3(ix + 1, iy, iz + 1)
        val n011 = hash3(ix, iy + 1, iz + 1)
        val n111 = hash3(ix + 1, iy + 1, iz + 1)
        val nx00 = lerp(n000, n100, ux)
        val nx10 = lerp(n010, n110, ux)
        val nx01 = lerp(n001, n101, ux)
        val nx11 = lerp(n011, n111, ux)
        return lerp(lerp(nx00, nx10, uy), lerp(nx01, nx11, uy), uz)
    }

    fun worldAt(x: Float, y: Float, z: Float): Int {
        var w = base
        if (wave.active) {
            var d = hypot(hypot(x - wave.cx, y - wave.cy), z - wave.cz)
            if (abs(d - wave.radius) < 1.6f) {
                d += (vnoise3(x * 0.35f, y * 0.35f, z * 0.35f) - 0.5f) * 3f
            }
            var inside = d < wave.radius
            if (wave.outerRadius > 0f) {
                var d2 = hypot(hypot(x - wave.outerCx, y - wave.outerCy), z - wave.outerCz)
                if (abs(d2 - wave.outerRadius) < 1.6f) {
                    d2 += (vnoise3(x * 0.35f, y * 0.35f, z * 0.35f) - 0.5f) * 3f
                }
                inside = inside || d2 > wave.outerRadius
            }
            w = if (inside) wave.to else wave.from
        }
        for (b in anchors) {
            if (!b.cond()) continue
            var d = hypot(hypot(x - b.x, y - b.y), z - b.z)
            if (abs(d - b.r) < 0.7f) {
                d += (vnoise3(x * 0.6f + 7f, y * 0.6f + 7f, z * 0.6f + 7f) - 0.5f) * 1.2f
            }
            if (d < b.r) w = 0
        }
        return w
    }

    fun flip(to: Int, center: Vec3, speed: Float = 34f, force: Boolean = false, quiet: Boolean = false): Boolean {
        if (wave.active && wave.to == to && !force) return false
        if (wave.active && wave.to != to && wave.outerRadius == 0f && wave.radius < 95f) {
            wave.outerCx = wave.cx
            wave.outerCy = wave.cy
            wave.outerCz = wave.cz
            wave.outerRadius = wave.radius
            wave.from = wave.to
            wave.to = to
            wave.cx = center.x
            wave.cy = center.y
            wave.cz = center.z
            wave.radius = 0f
            wave.speed = speed
            onFlip?.invoke(to, quiet)
            return true
        }
        if (wave.active) {
            base = wave.to
            wave.active = false
        }
        if (base == to && !force) return false
        wave.outerRadius = 0f
        wave.active = true
        wave.from = base
        wave.to = to
        wave.cx = center.x
        wave.cy = center.y
        wave.cz = center.z
        wave.radius = 0f
        wave.speed = speed
        onFlip?.invoke(to, quiet)
        return true
    }

    fun toNight(center: Vec3, durationSec: Float, speed: Float = 38f, force: Boolean = false, quiet: Boolean = false) {
        flip(1, center, speed = speed, force = force, quiet = quiet)
        if (durationSec > 0f) {
            nightTimer = max(nightTimer, durationSec)
        }
    }

    fun toDream(center: Vec3, speed: Float = 38f, force: Boolean = false, quiet: Boolean = false) {
        flip(0, center, speed = speed, force = force, quiet = quiet)
        nightTimer = 0f
    }

    fun update(dt: Float, playerPos: Vec3, paused: Boolean) {
        if (wave.active) {
            wave.radius += wave.speed * dt
            val covered = wave.outerRadius > 0f &&
                wave.radius > wave.outerRadius + hypot(
                    hypot(wave.cx - wave.outerCx, wave.cy - wave.outerCy),
                    wave.cz - wave.outerCz
                ) + 2f
            if (wave.radius > 95f || covered) {
                base = wave.to
                wave.active = false
                wave.outerRadius = 0f
            }
        }
        if (paused) return
        if (nightTimer > 0f) {
            nightTimer -= dt
            if (nightTimer <= 0f && !baseNight) {
                toDream(playerPos)
            }
        }
        if (flickerTimer > 0f) {
            flickerTimer -= dt
            flickerNext -= dt
            if (flickerNext <= 0f) {
                flickerNext = 0.6f + Random.nextFloat() * 2.4f
                flip(if (targetWorld == 1) 0 else 1, playerPos, speed = 60f, quiet = true)
            }
            if (flickerTimer <= 0f) {
                if (baseNight) flip(1, playerPos) else toDream(playerPos)
            }
        }
    }

    fun isInsideAnchor(pos: Vec3): Boolean {
        for (b in anchors) {
            if (b.cond() && hypot(hypot(pos.x - b.x, pos.y - b.y), pos.z - b.z) < b.r) return true
        }
        return false
    }
}
