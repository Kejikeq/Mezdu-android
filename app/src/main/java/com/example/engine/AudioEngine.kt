package com.example.engine

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

/**
 * Procedural WebAudio-style PCM synthesizer using Android AudioTrack.
 * Generates ambient Dream music-box / pad, Nightmare sub-bass drone, heartbeat, and crisp SFX.
 */
class AudioEngine {
    private val sampleRate = 22050
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Volatile var musicVolume: Float = 0.7f
    @Volatile var sfxVolume: Float = 0.85f
    @Volatile var nightMix: Float = 0f // 0 = dream, 1 = nightmare
    @Volatile var mode: String = "menu" // "menu" | "game" | "ending" | "paused"
    @Volatile var paused: Boolean = false

    private var musicTrack: AudioTrack? = null
    private var musicJob: Job? = null

    fun start() {
        if (musicJob?.isActive == true) return
        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(2048)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minBuf * 2)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        musicTrack = track
        runCatching { track.play() }

        musicJob = scope.launch {
            val chunkSamples = 1024
            val pcm = ShortArray(chunkSamples)
            var t = 0.0
            val dt = 1.0 / sampleRate
            // Dream melancholic chords (Am - F - C - G)
            val dreamNotes = doubleArrayOf(220.0, 261.63, 329.63, 392.0, 440.0, 349.23, 293.66, 329.63)
            var noteIdx = 0
            var nextNoteTime = 0.0
            var noteEnv = 0.0
            var curNoteFreq = 220.0
            var noisePhase = 0.0

            while (isActive) {
                val vol = if (paused) 0f else musicVolume * (if (mode == "menu") 0.35f else 0.42f)
                val nMix = nightMix.toDouble().coerceIn(0.0, 1.0)
                val dMix = 1.0 - nMix

                for (i in 0 until chunkSamples) {
                    if (vol <= 0.002f) {
                        pcm[i] = 0
                        t += dt
                        continue
                    }

                    // Dream warm pad + soft music-box bell
                    val pad1 = sin(2.0 * PI * 110.0 * t) * 0.25 + sin(2.0 * PI * 164.81 * t) * 0.16
                    val pad2 = sin(2.0 * PI * 220.0 * t + sin(t * 0.4) * 0.3) * 0.12
                    if (t >= nextNoteTime) {
                        nextNoteTime = t + (if (mode == "ending") 1.15 else 1.55)
                        curNoteFreq = dreamNotes[noteIdx % dreamNotes.size]
                        noteIdx++
                        noteEnv = 1.0
                    }
                    noteEnv *= 0.99975
                    val bell = sin(2.0 * PI * curNoteFreq * t) * noteEnv * 0.24

                    // Nightmare low drone + eerie detuned shimmer
                    val drone = sin(2.0 * PI * 55.0 * t) * 0.38 +
                        sin(2.0 * PI * 57.5 * t) * 0.26 +
                        sin(2.0 * PI * 82.4 * t + sin(t * 1.9) * 0.8) * 0.14
                    noisePhase = (noisePhase * 0.96 + (Random.nextDouble() - 0.5) * 0.08)
                    val wind = noisePhase * (0.35 + 0.65 * nMix)

                    val mixed = (dMix * (pad1 + pad2 + bell) + nMix * drone + wind * 0.35) * vol
                    val clamped = mixed.coerceIn(-0.85, 0.85)
                    pcm[i] = (clamped * 32767.0).toInt().toShort()
                    t += dt
                }
                val written = runCatching { track.write(pcm, 0, chunkSamples) }.getOrDefault(-1)
                if (written < 0) break
            }
        }
    }

    fun pause() {
        paused = true
        runCatching { musicTrack?.pause() }
    }

    fun resume() {
        paused = false
        runCatching { musicTrack?.play() }
    }

    fun stop() {
        musicJob?.cancel()
        musicJob = null
        runCatching {
            musicTrack?.stop()
            musicTrack?.release()
        }
        musicTrack = null
    }

    fun sfx(type: String, count: Int = 1, durationSec: Float = 0.8f) {
        val vol = sfxVolume
        if (vol <= 0.01f) return
        scope.launch {
            when (type) {
                "click" -> playToneBuffer(freq0 = 640.0, freq1 = 420.0, dur = 0.06, amp = 0.32 * vol)
                "tick" -> playToneBuffer(freq0 = 1100.0, freq1 = 800.0, dur = 0.04, amp = 0.25 * vol)
                "paper" -> playNoiseBurst(dur = 0.14, hp = 0.6, amp = 0.28 * vol)
                "door" -> playToneBuffer(freq0 = 140.0, freq1 = 85.0, dur = 0.28, amp = 0.36 * vol, noiseMix = 0.3)
                "break", "stone" -> playToneBuffer(freq0 = 180.0, freq1 = 65.0, dur = 0.25, amp = 0.45 * vol, noiseMix = 0.45)
                "wood" -> playToneBuffer(freq0 = 260.0, freq1 = 110.0, dur = 0.16, amp = 0.40 * vol, noiseMix = 0.25)
                "footstep" -> playNoiseBurst(dur = 0.07, hp = 0.25, amp = 0.22 * vol)
                "water_in", "splash" -> playNoiseBurst(dur = 0.35, hp = 0.35, amp = 0.35 * vol)
                "heart" -> playHeartbeat(vol)
                "glitch" -> playGlitch(vol)
                "success" -> playChord(doubleArrayOf(329.63, 440.0, 554.37), dur = 0.55, amp = 0.30 * vol)
                "fail" -> playToneBuffer(freq0 = 190.0, freq1 = 135.0, dur = 0.32, amp = 0.32 * vol)
                "pickup" -> playChord(doubleArrayOf(440.0, 587.33, 659.25), dur = 0.35, amp = 0.28 * vol)
                "beep" -> {
                    repeat(count.coerceIn(1, 5)) {
                        playToneBuffer(freq0 = 1040.0, freq1 = 1040.0, dur = 0.11, amp = 0.28 * vol)
                        kotlinx.coroutines.delay(260)
                    }
                }
                "rumble" -> playToneBuffer(freq0 = 68.0, freq1 = 44.0, dur = durationSec.toDouble().coerceIn(0.4, 2.2), amp = 0.42 * vol, noiseMix = 0.55)
                "crash" -> playToneBuffer(freq0 = 120.0, freq1 = 36.0, dur = 0.85, amp = 0.55 * vol, noiseMix = 0.75)
                "rain" -> playNoiseBurst(dur = durationSec.toDouble().coerceIn(0.6, 2.5), hp = 0.55, amp = 0.24 * vol)
                else -> playToneBuffer(freq0 = 520.0, freq1 = 480.0, dur = 0.08, amp = 0.22 * vol)
            }
        }
    }

    private fun playToneBuffer(freq0: Double, freq1: Double, dur: Double, amp: Double, noiseMix: Double = 0.0) {
        val n = (sampleRate * dur).toInt().coerceIn(256, sampleRate * 3)
        val buf = ShortArray(n)
        var phase = 0.0
        for (i in 0 until n) {
            val u = i.toDouble() / n
            val f = freq0 + (freq1 - freq0) * u
            phase += 2.0 * PI * f / sampleRate
            val env = sin(PI * minOf(1.0, u * 8.0)) * (1.0 - u).pow(1.4)
            val sample = sin(phase) * (1.0 - noiseMix) + (Random.nextDouble() * 2.0 - 1.0) * noiseMix
            buf[i] = (sample * env * amp * 32767.0).toInt().coerceIn(-32767, 32767).toShort()
        }
        playStaticSamples(buf)
    }

    private fun playNoiseBurst(dur: Double, hp: Double, amp: Double) {
        val n = (sampleRate * dur).toInt().coerceIn(256, sampleRate * 3)
        val buf = ShortArray(n)
        var prev = 0.0
        for (i in 0 until n) {
            val u = i.toDouble() / n
            val env = sin(PI * minOf(1.0, u * 6.0)) * exp(-u * 2.6)
            val white = Random.nextDouble() * 2.0 - 1.0
            val filtered = prev * (1.0 - hp) + white * hp
            prev = filtered
            buf[i] = (filtered * env * amp * 32767.0).toInt().coerceIn(-32767, 32767).toShort()
        }
        playStaticSamples(buf)
    }

    private fun playHeartbeat(vol: Float) {
        val dur = 0.52
        val n = (sampleRate * dur).toInt()
        val buf = ShortArray(n)
        for (i in 0 until n) {
            val t = i.toDouble() / sampleRate
            val b1 = exp(-((t - 0.06) / 0.032).pow(2.0)) * sin(2.0 * PI * 54.0 * t)
            val b2 = exp(-((t - 0.24) / 0.036).pow(2.0)) * 0.72 * sin(2.0 * PI * 48.0 * t)
            buf[i] = ((b1 + b2) * 0.65 * vol * 32767.0).toInt().coerceIn(-32767, 32767).toShort()
        }
        playStaticSamples(buf)
    }

    private fun playGlitch(vol: Float) {
        val n = (sampleRate * 0.28).toInt()
        val buf = ShortArray(n)
        for (i in 0 until n) {
            val u = i.toDouble() / n
            val f = if ((i / 180) % 2 == 0) 920.0 else 195.0
            val env = (1.0 - u)
            val s = sin(2.0 * PI * f * i / sampleRate) * 0.5 + (Random.nextDouble() * 2.0 - 1.0) * 0.45
            buf[i] = (s * env * 0.45 * vol * 32767.0).toInt().coerceIn(-32767, 32767).toShort()
        }
        playStaticSamples(buf)
    }

    private fun playChord(freqs: DoubleArray, dur: Double, amp: Double) {
        val n = (sampleRate * dur).toInt()
        val buf = ShortArray(n)
        for (i in 0 until n) {
            val u = i.toDouble() / n
            val env = minOf(1.0, u * 15.0) * (1.0 - u).pow(1.6)
            var sum = 0.0
            for (k in freqs.indices) {
                val delay = k * 0.04
                val t = (i.toDouble() / sampleRate) - delay
                if (t > 0) sum += sin(2.0 * PI * freqs[k] * t)
            }
            buf[i] = ((sum / freqs.size) * env * amp * 32767.0).toInt().coerceIn(-32767, 32767).toShort()
        }
        playStaticSamples(buf)
    }

    private fun playStaticSamples(samples: ShortArray) {
        runCatching {
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(samples.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            track.write(samples, 0, samples.size)
            track.play()
            Thread.sleep((samples.size * 1000L / sampleRate) + 60L)
            track.stop()
            track.release()
        }
    }
}
