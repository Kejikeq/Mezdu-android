package com.example.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import kotlin.math.abs

object MapGenerator {
    fun buildDreamMapBitmap(size: Int = 384): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)

        // Warm parchment base
        c.drawColor(Color.rgb(225, 209, 174))

        // Subtle topographic rings
        val contour = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(45, 110, 92, 62)
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        for (i in 1..6) {
            c.drawCircle(size * 0.55f, size * 0.45f, i * size * 0.09f, contour)
        }

        // Stream band
        val stream = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(112, 152, 174)
            style = Paint.Style.STROKE
            strokeWidth = size * 0.055f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val streamPath = Path().apply {
            moveTo(size * 0.18f, size * 0.14f)
            quadTo(size * 0.25f, size * 0.46f, size * 0.42f, size * 0.62f)
            quadTo(size * 0.62f, size * 0.78f, size * 0.85f, size * 0.88f)
        }
        c.drawPath(streamPath, stream)

        // Trails
        val trail = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(142, 110, 74)
            style = Paint.Style.STROKE
            strokeWidth = size * 0.025f
            strokeCap = Paint.Cap.ROUND
        }
        val trailPath = Path().apply {
            moveTo(size * 0.72f, size * 0.78f)
            lineTo(size * 0.58f, size * 0.62f)
            lineTo(size * 0.50f, size * 0.50f)
            lineTo(size * 0.34f, size * 0.45f)
            lineTo(size * 0.22f, size * 0.26f)
        }
        c.drawPath(trailPath, trail)

        // Landmark markers (House, Campfire, Thicket)
        val landmark = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(88, 62, 42) }
        c.drawRect(size * 0.68f, size * 0.74f, size * 0.76f, size * 0.82f, landmark) // House
        c.drawCircle(size * 0.50f, size * 0.50f, size * 0.03f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(214, 118, 42) }) // Campfire
        c.drawCircle(size * 0.34f, size * 0.45f, size * 0.035f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(66, 98, 62) }) // Thicket

        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(68, 52, 34)
            textSize = size * 0.042f
        }
        c.drawText("ДОМ", size * 0.64f, size * 0.88f, labelPaint)
        c.drawText("КОСТЁР", size * 0.53f, size * 0.48f, labelPaint)
        c.drawText("ЧАЩА", size * 0.25f, size * 0.53f, labelPaint)
        c.drawText("РУЧЕЙ", size * 0.14f, size * 0.38f, labelPaint)

        // Compass rose
        val rose = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(92, 68, 44)
            strokeWidth = 2.5f
            textSize = size * 0.045f
        }
        c.drawText("С", size * 0.87f, size * 0.12f, rose)
        c.drawLine(size * 0.89f, size * 0.14f, size * 0.89f, size * 0.24f, rose)

        return bmp
    }

    fun buildNightTracingBitmap(size: Int = 384): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)

        // Semi-translucent dark parchment tracing paper
        c.drawColor(Color.argb(170, 26, 20, 24))

        // Red subterranean tunnel dashed lines
        val tunnelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(224, 80, 63)
            style = Paint.Style.STROKE
            strokeWidth = size * 0.022f
            strokeCap = Paint.Cap.ROUND
        }
        val path = Path().apply {
            moveTo(size * 0.50f, size * 0.50f)
            lineTo(size * 0.44f, size * 0.38f)
            lineTo(size * 0.26f, size * 0.30f)
            lineTo(size * 0.22f, size * 0.22f)
        }
        c.drawPath(path, tunnelPaint)

        // Red Cross marking crash site in upstream creek!
        val crossPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(245, 72, 58)
            style = Paint.Style.STROKE
            strokeWidth = size * 0.032f
            strokeCap = Paint.Cap.ROUND
        }
        val cx = size * 0.22f
        val cy = size * 0.22f
        val r = size * 0.055f
        c.drawLine(cx - r, cy - r, cx + r, cy + r, crossPaint)
        c.drawLine(cx + r, cy - r, cx - r, cy + r, crossPaint)
        c.drawCircle(cx, cy, r * 1.45f, crossPaint.apply { strokeWidth = 3f })

        // Center campfire alignment marker
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(242, 200, 121)
            style = Paint.Style.STROKE
            strokeWidth = 3f
        }
        c.drawCircle(size * 0.50f, size * 0.50f, size * 0.04f, ring)

        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(244, 180, 170)
            textSize = size * 0.038f
        }
        c.drawText("7319", cx + r * 1.5f, cy + 8f, label)

        return bmp
    }

    fun isAligned(rotationDeg: Int, flipped: Boolean): Boolean {
        val norm = ((rotationDeg % 360) + 360) % 360
        return abs(norm) == 0 && !flipped
    }
}
