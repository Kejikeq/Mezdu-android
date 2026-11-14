package com.example.gfx

import android.opengl.GLES30
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import com.example.data.ChapterSceneData
import com.example.data.Interactable
import com.example.data.ScreenGlint
import com.example.data.Vec3
import com.example.engine.DualityEngine
import com.example.engine.SkyPresets
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tan

class VoxelWorldRenderer(
    private val duality: DualityEngine,
    private val onFpsSample: (Int) -> Unit,
    private val onGlintsUpdated: (List<ScreenGlint>) -> Unit
) : GLSurfaceView.Renderer {

    @Volatile var currentScene: ChapterSceneData? = null
    @Volatile var sceneDirty: Boolean = true
    @Volatile var camPos: Vec3 = Vec3(0f, 10f, 0f)
    @Volatile var camYaw: Float = 0f
    @Volatile var camPitch: Float = 0f
    @Volatile var playerPos: Vec3 = Vec3(0f, 7f, 0f)
    @Volatile var playerYaw: Float = 0f
    @Volatile var thirdPerson: Boolean = true
    @Volatile var chapter: Int = 1
    @Volatile var headache: Float = 0f
    @Volatile var flashOn: Boolean = false
    @Volatile var visibleInteractables: List<Interactable> = emptyList()

    private var program = 0
    private var skyProgram = 0
    private var viewportW = 1
    private var viewportH = 1

    private val projMatrix = FloatArray(16)
    private val viewMatrix = FloatArray(16)
    private val vpMatrix = FloatArray(16)

    private val accumulator = VoxelMeshBuilder.MeshAccumulator()
    private var vertexBuffer: FloatBuffer? = null
    private var vertexCount = 0
    private var startTimeNs = System.nanoTime()
    private var fpsFrames = 0
    private var fpsLastNs = System.nanoTime()
    private var glintLastNs = System.nanoTime()

    private var skyQuadBuffer: FloatBuffer? = null

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glEnable(GLES30.GL_CULL_FACE)
        GLES30.glCullFace(GLES30.GL_BACK)

        program = buildProgram(VOXEL_VERT_SHADER, VOXEL_FRAG_SHADER)
        skyProgram = buildProgram(SKY_VERT_SHADER, SKY_FRAG_SHADER)

        val quad = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, -1f, 1f, 1f, -1f, 1f)
        val bb = java.nio.ByteBuffer.allocateDirect(quad.size * 4).order(java.nio.ByteOrder.nativeOrder())
        skyQuadBuffer = bb.asFloatBuffer().apply { put(quad); position(0) }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        viewportW = width.coerceAtLeast(1)
        viewportH = height.coerceAtLeast(1)
        GLES30.glViewport(0, 0, viewportW, viewportH)
        val aspect = viewportW.toFloat() / viewportH.toFloat()
        Matrix.perspectiveM(projMatrix, 0, 58f, aspect, 0.15f, 180f)
    }

    override fun onDrawFrame(gl: GL10?) {
        val nowNs = System.nanoTime()
        val timeSec = ((nowNs - startTimeNs) * 1e-9).toFloat()

        fpsFrames++
        if (nowNs - fpsLastNs >= 500_000_000L) {
            val fps = ((fpsFrames * 1_000_000_000L) / (nowNs - fpsLastNs)).toInt()
            onFpsSample(fps)
            fpsFrames = 0
            fpsLastNs = nowNs
        }

        val skyD = SkyPresets.dreamForChapter(chapter)
        val skyN = SkyPresets.NIGHTMARE

        // Rebuild dynamic mesh every frame (fast, ~300-800 boxes -> <15k verts)
        rebuildMesh(timeSec)

        // Camera matrices
        val lookDist = 10f
        val cp = camPos
        val cosP = cos(camPitch)
        val lookX = cp.x + sin(camYaw) * cosP * lookDist
        val lookY = cp.y + sin(camPitch) * lookDist
        val lookZ = cp.z + cos(camYaw) * cosP * lookDist
        Matrix.setLookAtM(viewMatrix, 0, cp.x, cp.y, cp.z, lookX, lookY, lookZ, 0f, 1f, 0f)
        Matrix.multiplyMM(vpMatrix, 0, projMatrix, 0, viewMatrix, 0)

        GLES30.glClearColor(skyD.fog[0], skyD.fog[1], skyD.fog[2], 1f)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)

        drawSkyDome(skyD, skyN)
        drawVoxelScene(timeSec, skyD, skyN)

        // Update projected screen-space interaction glints ~15Hz
        if (nowNs - glintLastNs >= 65_000_000L) {
            glintLastNs = nowNs
            updateGlints()
        }
    }

    private fun rebuildMesh(timeSec: Float) {
        val scene = currentScene ?: return
        accumulator.clear()
        for (p in scene.props) {
            accumulator.addProp(p, timeSec)
        }
        // Third-person Elias avatar
        if (thirdPerson) {
            val px = playerPos.x
            val py = playerPos.y
            val pz = playerPos.z
            accumulator.addBox(px, py, pz, 0.44f, 0.78f, 0.30f, playerYaw, 0xFF2E3B52.toInt(), 0xFF211C28.toInt(), 3, false)
            accumulator.addBox(px, py + 0.78f, pz, 0.56f, 0.62f, 0.34f, playerYaw, 0xFF3E6A96.toInt(), 0xFF382430.toInt(), 3, false)
            accumulator.addBox(px, py + 1.42f, pz, 0.36f, 0.36f, 0.36f, playerYaw, 0xFFE6C5A8.toInt(), 0xFF8C7278.toInt(), 3, false)
        }
        vertexCount = accumulator.vertexCount
        vertexBuffer = accumulator.toFloatBuffer()
        sceneDirty = false
    }

    private fun drawSkyDome(skyD: com.example.engine.SkyPreset, skyN: com.example.engine.SkyPreset) {
        val qb = skyQuadBuffer ?: return
        GLES30.glDisable(GLES30.GL_DEPTH_TEST)
        GLES30.glUseProgram(skyProgram)

        val locPos = GLES30.glGetAttribLocation(skyProgram, "aPos")
        GLES30.glEnableVertexAttribArray(locPos)
        GLES30.glVertexAttribPointer(locPos, 2, GLES30.GL_FLOAT, false, 8, qb)

        val worldBlend = if (duality.worldAt(camPos.x, camPos.y, camPos.z) == 1) 1f else 0f
        val nightMix = if (duality.wave.active) {
            if (duality.wave.to == 1) (duality.wave.radius / 26f).coerceIn(0f, 1f)
            else 1f - (duality.wave.radius / 26f).coerceIn(0f, 1f)
        } else worldBlend

        fun mix3(a: FloatArray, b: FloatArray, t: Float, u: Int) {
            GLES30.glUniform3f(
                u,
                a[0] + (b[0] - a[0]) * t,
                a[1] + (b[1] - a[1]) * t,
                a[2] + (b[2] - a[2]) * t
            )
        }

        mix3(skyD.zenith, skyN.zenith, nightMix, GLES30.glGetUniformLocation(skyProgram, "uZenith"))
        mix3(skyD.horizon, skyN.horizon, nightMix, GLES30.glGetUniformLocation(skyProgram, "uHorizon"))
        mix3(skyD.glow, skyN.glow, nightMix, GLES30.glGetUniformLocation(skyProgram, "uGlow"))
        GLES30.glUniform1f(GLES30.glGetUniformLocation(skyProgram, "uPitch"), camPitch)

        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 6)
        GLES30.glDisableVertexAttribArray(locPos)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
    }

    private fun drawVoxelScene(
        timeSec: Float,
        skyD: com.example.engine.SkyPreset,
        skyN: com.example.engine.SkyPreset
    ) {
        val vb = vertexBuffer ?: return
        if (vertexCount == 0) return

        GLES30.glUseProgram(program)
        val stride = VoxelMeshBuilder.FLOATS_PER_VERTEX * 4

        val aPos = GLES30.glGetAttribLocation(program, "aPos")
        val aNormal = GLES30.glGetAttribLocation(program, "aNormal")
        val aDreamCol = GLES30.glGetAttribLocation(program, "aDreamCol")
        val aNightCol = GLES30.glGetAttribLocation(program, "aNightCol")
        val aMask = GLES30.glGetAttribLocation(program, "aMask")
        val aEmissive = GLES30.glGetAttribLocation(program, "aEmissive")

        vb.position(0)
        GLES30.glEnableVertexAttribArray(aPos)
        GLES30.glVertexAttribPointer(aPos, 3, GLES30.GL_FLOAT, false, stride, vb)

        vb.position(3)
        GLES30.glEnableVertexAttribArray(aNormal)
        GLES30.glVertexAttribPointer(aNormal, 3, GLES30.GL_FLOAT, false, stride, vb)

        vb.position(6)
        GLES30.glEnableVertexAttribArray(aDreamCol)
        GLES30.glVertexAttribPointer(aDreamCol, 3, GLES30.GL_FLOAT, false, stride, vb)

        vb.position(9)
        GLES30.glEnableVertexAttribArray(aNightCol)
        GLES30.glVertexAttribPointer(aNightCol, 3, GLES30.GL_FLOAT, false, stride, vb)

        vb.position(12)
        GLES30.glEnableVertexAttribArray(aMask)
        GLES30.glVertexAttribPointer(aMask, 1, GLES30.GL_FLOAT, false, stride, vb)

        vb.position(13)
        GLES30.glEnableVertexAttribArray(aEmissive)
        GLES30.glVertexAttribPointer(aEmissive, 1, GLES30.GL_FLOAT, false, stride, vb)

        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(program, "uVP"), 1, false, vpMatrix, 0)
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uCamPos"), camPos.x, camPos.y, camPos.z)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uTime"), timeSec)

        // Duality wave uniforms
        val w = duality.wave
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uBaseWorld"), duality.base)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uWaveActive"), if (w.active) 1 else 0)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uWaveFrom"), w.from)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uWaveTo"), w.to)
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uWaveCenter"), w.cx, w.cy, w.cz)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uWaveRadius"), w.radius)
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uOuterCenter"), w.outerCx, w.outerCy, w.outerCz)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uOuterRadius"), w.outerRadius)

        // Lighting & Fog
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uSunDir"), skyD.sunDir[0], skyD.sunDir[1], skyD.sunDir[2])
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uSunD"), skyD.sunColor[0], skyD.sunColor[1], skyD.sunColor[2])
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uSunN"), skyN.sunColor[0], skyN.sunColor[1], skyN.sunColor[2])
        GLES30.glUniform4f(GLES30.glGetUniformLocation(program, "uFogD"), skyD.fog[0], skyD.fog[1], skyD.fog[2], skyD.fog[3] * (1f + headache * 1.5f))
        GLES30.glUniform4f(GLES30.glGetUniformLocation(program, "uFogN"), skyN.fog[0], skyN.fog[1], skyN.fog[2], skyN.fog[3] * (1f + headache * 1.5f))

        // Flashlight
        val cosP = cos(camPitch)
        val fwdX = sin(camYaw) * cosP
        val fwdY = sin(camPitch)
        val fwdZ = cos(camYaw) * cosP
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uFlashOn"), if (flashOn) 1 else 0)
        GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uFlashDir"), fwdX, fwdY, fwdZ)

        // Primary dynamic point light nearest player
        val scene = currentScene
        val nearestLight = scene?.lights?.minByOrNull { l ->
            val dx = l.x - playerPos.x; val dz = l.z - playerPos.z
            dx * dx + dz * dz
        }
        if (nearestLight != null) {
            val flk = if (nearestLight.flicker) (0.85f + 0.15f * sin(timeSec * 14f)) else 1f
            GLES30.glUniform4f(GLES30.glGetUniformLocation(program, "uPointPos"), nearestLight.x, nearestLight.y, nearestLight.z, nearestLight.radius)
            GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uPointCol"), nearestLight.r * nearestLight.intensity * flk, nearestLight.g * nearestLight.intensity * flk, nearestLight.b * nearestLight.intensity * flk)
        } else {
            GLES30.glUniform4f(GLES30.glGetUniformLocation(program, "uPointPos"), 0f, 0f, 0f, 0f)
            GLES30.glUniform3f(GLES30.glGetUniformLocation(program, "uPointCol"), 0f, 0f, 0f)
        }

        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, vertexCount)

        GLES30.glDisableVertexAttribArray(aPos)
        GLES30.glDisableVertexAttribArray(aNormal)
        GLES30.glDisableVertexAttribArray(aDreamCol)
        GLES30.glDisableVertexAttribArray(aNightCol)
        GLES30.glDisableVertexAttribArray(aMask)
        GLES30.glDisableVertexAttribArray(aEmissive)
    }

    private fun updateGlints() {
        val list = visibleInteractables
        if (list.isEmpty()) {
            onGlintsUpdated(emptyList())
            return
        }
        val out = mutableListOf<ScreenGlint>()
        val worldPt = FloatArray(4)
        val clipPt = FloatArray(4)
        for (it in list) {
            val dx = it.pos.x - playerPos.x
            val dy = it.pos.y - playerPos.y
            val dz = it.pos.z - playerPos.z
            val dSq = dx * dx + dy * dy + dz * dz
            if (dSq > 16f * 16f) continue
            worldPt[0] = it.pos.x
            worldPt[1] = it.pos.y + 0.45f
            worldPt[2] = it.pos.z
            worldPt[3] = 1f
            Matrix.multiplyMV(clipPt, 0, vpMatrix, 0, worldPt, 0)
            if (clipPt[3] <= 0.1f) continue
            val ndcX = clipPt[0] / clipPt[3]
            val ndcY = clipPt[1] / clipPt[3]
            if (ndcX < -0.92f || ndcX > 0.92f || ndcY < -0.85f || ndcY > 0.85f) continue
            val nx = (ndcX * 0.5f) + 0.5f
            val ny = 1f - ((ndcY * 0.5f) + 0.5f)
            out.add(ScreenGlint(it.id, nx, ny, it.icon, dSq <= it.radius * it.radius))
        }
        onGlintsUpdated(out)
    }

    private fun compileShader(type: Int, src: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, src)
        GLES30.glCompileShader(shader)
        return shader
    }

    private fun buildProgram(vertSrc: String, fragSrc: String): Int {
        val v = compileShader(GLES30.GL_VERTEX_SHADER, vertSrc)
        val f = compileShader(GLES30.GL_FRAGMENT_SHADER, fragSrc)
        val p = GLES30.glCreateProgram()
        GLES30.glAttachShader(p, v)
        GLES30.glAttachShader(p, f)
        GLES30.glLinkProgram(p)
        return p
    }

    companion object {
        private const val SKY_VERT_SHADER = """#version 300 es
            in vec2 aPos;
            out vec2 vUv;
            void main() {
                vUv = aPos * 0.5 + 0.5;
                gl_Position = vec4(aPos, 0.999, 1.0);
            }
        """

        private const val SKY_FRAG_SHADER = """#version 300 es
            precision mediump float;
            in vec2 vUv;
            uniform vec3 uZenith;
            uniform vec3 uHorizon;
            uniform vec3 uGlow;
            uniform float uPitch;
            out vec4 fragColor;
            void main() {
                float h = clamp(vUv.y + uPitch * 0.45, 0.0, 1.0);
                vec3 col = mix(uHorizon, uZenith, pow(h, 0.65));
                float band = exp(-pow((h - 0.15) * 4.5, 2.0));
                col += uGlow * band * 0.35;
                fragColor = vec4(col, 1.0);
            }
        """

        private const val VOXEL_VERT_SHADER = """#version 300 es
            in vec3 aPos;
            in vec3 aNormal;
            in vec3 aDreamCol;
            in vec3 aNightCol;
            in float aMask;
            in float aEmissive;

            uniform mat4 uVP;

            out vec3 vWorldPos;
            out vec3 vNormal;
            out vec3 vDreamCol;
            out vec3 vNightCol;
            out float vMask;
            out float vEmissive;

            void main() {
                vWorldPos = aPos;
                vNormal = aNormal;
                vDreamCol = aDreamCol;
                vNightCol = aNightCol;
                vMask = aMask;
                vEmissive = aEmissive;
                gl_Position = uVP * vec4(aPos, 1.0);
            }
        """

        private const val VOXEL_FRAG_SHADER = """#version 300 es
            precision highp float;
            in vec3 vWorldPos;
            in vec3 vNormal;
            in vec3 vDreamCol;
            in vec3 vNightCol;
            in float vMask;
            in float vEmissive;

            uniform vec3 uCamPos;
            uniform float uTime;
            uniform int uBaseWorld;
            uniform int uWaveActive;
            uniform int uWaveFrom;
            uniform int uWaveTo;
            uniform vec3 uWaveCenter;
            uniform float uWaveRadius;
            uniform vec3 uOuterCenter;
            uniform float uOuterRadius;

            uniform vec3 uSunDir;
            uniform vec3 uSunD;
            uniform vec3 uSunN;
            uniform vec4 uFogD;
            uniform vec4 uFogN;
            uniform int uFlashOn;
            uniform vec3 uFlashDir;
            uniform vec4 uPointPos;
            uniform vec3 uPointCol;

            out vec4 fragColor;

            float hash3(vec3 p) {
                p = fract(p * 0.3183099 + 0.1);
                p *= 17.0;
                return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
            }

            float vnoise(vec3 x) {
                vec3 i = floor(x);
                vec3 f = fract(x);
                f = f * f * (3.0 - 2.0 * f);
                return mix(
                    mix(mix(hash3(i + vec3(0,0,0)), hash3(i + vec3(1,0,0)), f.x),
                        mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
                    mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
                        mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y),
                    f.z
                );
            }

            void main() {
                float w = float(uBaseWorld);
                float edgeGlow = 0.0;
                if (uWaveActive == 1) {
                    float d = length(vWorldPos - uWaveCenter);
                    if (abs(d - uWaveRadius) < 1.8) {
                        d += (vnoise(vWorldPos * 0.4) - 0.5) * 2.6;
                    }
                    bool inside = d < uWaveRadius;
                    if (uOuterRadius > 0.0) {
                        float d2 = length(vWorldPos - uOuterCenter);
                        if (abs(d2 - uOuterRadius) < 1.8) {
                            d2 += (vnoise(vWorldPos * 0.4) - 0.5) * 2.6;
                        }
                        inside = inside || d2 > uOuterRadius;
                    }
                    w = inside ? float(uWaveTo) : float(uWaveFrom);
                    float ringDist = abs(d - uWaveRadius);
                    if (ringDist < 1.1) {
                        edgeGlow = 1.0 - (ringDist / 1.1);
                    }
                }

                // World-mask visibility filtering
                int maskInt = int(vMask + 0.5);
                if (maskInt == 1 && w > 0.5) discard;
                if (maskInt == 2 && w < 0.5) discard;

                vec3 albedo = mix(vDreamCol, vNightCol, w);
                vec3 N = normalize(vNormal);
                float ndotl = max(dot(N, normalize(uSunDir)), 0.0);
                vec3 sunCol = mix(uSunD, uSunN, w);
                vec3 amb = mix(vec3(0.42, 0.39, 0.36), vec3(0.18, 0.11, 0.14), w);

                vec3 lit = albedo * (amb + sunCol * ndotl * 0.72);

                if (vEmissive > 0.5) {
                    float pulse = 0.85 + 0.15 * sin(uTime * 3.0);
                    lit = max(lit, albedo * 1.25 * pulse);
                }

                // Point Light contribution
                if (uPointPos.w > 0.1) {
                    vec3 toL = uPointPos.xyz - vWorldPos;
                    float dist = length(toL);
                    if (dist < uPointPos.w) {
                        float att = pow(1.0 - dist / uPointPos.w, 1.6);
                        float pnd = max(dot(N, normalize(toL)), 0.2);
                        lit += albedo * uPointCol * att * pnd * 0.65;
                    }
                }

                // Player Flashlight spotlight
                if (uFlashOn == 1) {
                    vec3 toFrag = vWorldPos - uCamPos;
                    float dist = length(toFrag);
                    if (dist < 18.0 && dist > 0.2) {
                        vec3 dir = toFrag / dist;
                        float spot = smoothstep(0.76, 0.94, dot(dir, normalize(uFlashDir)));
                        float att = 1.0 - dist / 18.0;
                        lit += albedo * vec3(1.0, 0.92, 0.75) * spot * att * 1.15;
                    }
                }

                // Duality boundary shimmer
                if (edgeGlow > 0.01) {
                    vec3 bCol = (uWaveTo == 1) ? vec3(0.92, 0.32, 0.25) : vec3(0.95, 0.78, 0.47);
                    lit += bCol * edgeGlow * 0.85;
                }

                // Distance Fog
                float camDist = length(vWorldPos - uCamPos);
                vec4 fog = mix(uFogD, uFogN, w);
                float fogAmt = 1.0 - exp(-camDist * fog.w);
                vec3 finalCol = mix(lit, fog.rgb, clamp(fogAmt, 0.0, 0.95));

                fragColor = vec4(finalCol, 1.0);
            }
        """
    }
}
