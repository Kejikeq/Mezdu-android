package com.example.ui

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.ActiveModal
import com.example.data.AppMode
import com.example.data.ChapterSceneData
import com.example.data.ChapterScenes
import com.example.data.ChaptersCatalog2
import com.example.data.CustomLinkData
import com.example.data.EndingState
import com.example.data.GameSettings
import com.example.data.GameUiState
import com.example.data.InteractIcon
import com.example.data.Interactable
import com.example.data.ItemsCatalog
import com.example.data.MemoryProfile
import com.example.data.MemoryVector
import com.example.data.NpcDef
import com.example.data.SavePayload
import com.example.data.ScreenGlint
import com.example.data.Vec3
import com.example.data.WorldFilter
import com.example.data.db.GameRepository
import com.example.engine.AudioEngine
import com.example.engine.DualityEngine
import com.example.gfx.VoxelWorldRenderer
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sin

class GameViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = GameRepository(application)
    val duality = DualityEngine()
    val audio = AudioEngine()

    private val _uiState = MutableStateFlow(GameUiState())
    val uiState: StateFlow<GameUiState> = _uiState.asStateFlow()

    val renderer = VoxelWorldRenderer(
        duality = duality,
        onFpsSample = { fps -> _uiState.update { it.copy(fps = fps) } },
        onGlintsUpdated = { glints -> _uiState.update { it.copy(glints = glints) } }
    )

    // Internal mutable game state
    var currentChapter = 1
        private set
    var playerPos = Vec3(0f, 11f, 0f)
        private set
    var playerYaw = 0f
    var camYaw = 0f
    var camPitch = -0.14f
    var camDist = 3.2f

    var joyX = 0f
    var joyY = 0f

    val inventory = mutableListOf<String>()
    val clues = mutableSetOf<String>()
    val testimonies = mutableSetOf<String>()
    val conclusions = mutableMapOf<Int, MemoryVector>()
    val customLinks = mutableMapOf<Int, CustomLinkData>()
    val flags = mutableMapOf<String, Boolean>()
    val edits = mutableMapOf<String, Boolean>()

    private var unreadBoardCount = 0
    private var currentObjective = ""
    private var inputLocked = false
    private var flashOn = false
    private var peering = false
    private var headache = 0f
    private var stepAccum = 0f
    private var holdProgress = 0f
    private var holdingAction = false
    private var activeScene: ChapterSceneData? = null
    private var allInteractables: List<Interactable> = emptyList()
    private var activeInteractable: Interactable? = null
    private var loopJob: Job? = null
    private var subtitleJob: Job? = null
    private var skipRequested = false

    // Modal async bridges
    private var inspectDeferred: CompletableDeferred<Unit>? = null
    private var readerDeferred: CompletableDeferred<Unit>? = null
    private var npcDeferred: CompletableDeferred<Unit>? = null
    private var runeDeferred: CompletableDeferred<Boolean>? = null
    private var letterDeferred: CompletableDeferred<Boolean>? = null
    private var codeDeferred: CompletableDeferred<Boolean>? = null
    private var mapDeferred: CompletableDeferred<Boolean>? = null

    init {
        duality.onFlip = { to, quiet ->
            if (!quiet) {
                audio.sfx(if (to == 1) "water_in" else "click")
                vibrate(30L)
            }
        }
        viewModelScope.launch {
            repo.settingsFlow.collect { s ->
                audio.musicVolume = s.musicVolume
                audio.sfxVolume = s.sfxVolume
                renderer.thirdPerson = s.thirdPerson
                _uiState.update { it.copy(settings = s) }
            }
        }
        viewModelScope.launch {
            repo.saveSlotsFlow.collect { slots ->
                val hasAuto = slots.firstOrNull { it.slotId == "auto" }?.payload != null
                _uiState.update { it.copy(saveSlots = slots, hasAutoSave = hasAuto) }
            }
        }
        allInteractables = ChapterInteractables.buildAll(this)
        audio.start()
        startGameLoop()
    }

    override fun onCleared() {
        super.onCleared()
        loopJob?.cancel()
        audio.stop()
    }

    fun onAppPause() {
        audio.pause()
        if (_uiState.value.mode == AppMode.PLAYING && _uiState.value.activeModal == null) {
            togglePause()
        }
    }

    fun onAppResume() {
        audio.resume()
    }

    private fun startGameLoop() {
        loopJob?.cancel()
        loopJob = viewModelScope.launch {
            var lastNs = System.nanoTime()
            while (true) {
                delay(16L)
                val nowNs = System.nanoTime()
                val dt = ((nowNs - lastNs) * 1e-9f).coerceIn(0.001f, 0.05f)
                lastNs = nowNs

                val state = _uiState.value
                val paused = state.mode != AppMode.PLAYING || state.activeModal != null

                duality.update(dt, playerPos, paused)

                if (!paused && !inputLocked) {
                    updateMovement(dt)
                    updateStability(dt)
                    updateInteractables(dt)
                }

                // Update renderer uniforms/transforms
                val isNightNow = duality.worldAt(playerPos.x, playerPos.y + 0.9f, playerPos.z) == 1
                audio.nightMix = if (isNightNow) 1f else 0f
                audio.paused = state.mode == AppMode.PAUSED

                val thirdP = state.settings.thirdPerson
                val eyeY = playerPos.y + 1.55f
                if (thirdP) {
                    val backX = -sin(camYaw) * cos(camPitch) * camDist
                    val backY = -sin(camPitch) * camDist + 0.4f
                    val backZ = -cos(camYaw) * cos(camPitch) * camDist
                    renderer.camPos = Vec3(playerPos.x + backX, (playerPos.y + 1.6f + backY).coerceAtLeast(playerPos.y + 0.4f), playerPos.z + backZ)
                } else {
                    renderer.camPos = Vec3(playerPos.x, eyeY, playerPos.z)
                }
                renderer.camYaw = camYaw
                renderer.camPitch = camPitch
                renderer.playerPos = playerPos
                renderer.playerYaw = playerYaw
                renderer.chapter = currentChapter
                renderer.headache = headache
                renderer.flashOn = flashOn && isNightNow

                val bpm = (66 + ((100f - duality.stability) * 0.65f).toInt() + if (isNightNow) 16 else 0).coerceIn(60, 148)
                _uiState.update {
                    it.copy(
                        isNight = isNightNow,
                        nightTimerRemaining = duality.nightTimer.coerceAtLeast(0f),
                        stability = duality.stability,
                        heartRateBpm = bpm,
                        headache = headache,
                        peering = peering,
                        flashOn = flashOn
                    )
                }
            }
        }
    }

    private fun updateMovement(dt: Float) {
        val scene = activeScene ?: return
        val mag = hypot(joyX, joyY)
        if (mag > 0.04f) {
            val speed = 4.6f * (if (duality.stability < 25f) 0.75f else 1f)
            val fwdX = sin(camYaw)
            val fwdZ = cos(camYaw)
            val rightX = -cos(camYaw)
            val rightZ = sin(camYaw)

            val vx = (fwdX * (-joyY) + rightX * joyX) * speed * dt
            val vz = (fwdZ * (-joyY) + rightZ * joyX) * speed * dt

            val nextX = (playerPos.x + vx).coerceIn(scene.boundsX0, scene.boundsX1)
            val nextZ = (playerPos.z + vz).coerceIn(scene.boundsZ0, scene.boundsZ1)

            val w = duality.worldAt(nextX, playerPos.y + 0.9f, nextZ)
            var rx = playerPos.x
            var rz = playerPos.z
            if (!hitsCollider(nextX, playerPos.y, playerPos.z, w)) rx = nextX
            if (!hitsCollider(rx, playerPos.y, nextZ, w)) rz = nextZ

            val ny = scene.heightResolver(rx, rz, playerPos.y)
            playerPos = Vec3(rx, ny, rz)
            playerYaw = kotlin.math.atan2(vx, vz)

            stepAccum += mag * speed * dt
            if (stepAccum > 1.7f) {
                stepAccum = 0f
                audio.sfx("footstep")
            }
        }
    }

    private fun hitsCollider(x: Float, y: Float, z: Float, world: Int): Boolean {
        val scene = activeScene ?: return false
        val bit = if (world == 1) 2 else 1
        val r = 0.34f
        for (c in scene.colliders) {
            if ((c.mask and bit) == 0) continue
            if (x + r > c.x0 && x - r < c.x1 && y + 1.7f > c.y0 && y + 0.3f < c.y1 && z + r > c.z0 && z - r < c.z1) {
                return true
            }
        }
        return false
    }

    private fun updateStability(dt: Float) {
        val w = duality.worldAt(playerPos.x, playerPos.y + 0.9f, playerPos.z)
        val inAnchor = duality.isInsideAnchor(playerPos)
        val hasLocket = hasItem("locket")
        val hasStone = hasItem("carved_stone")

        if (w == 1 && !inAnchor) {
            var drain = duality.drainPerSec
            if (currentChapter == 7 && !hasStone) drain *= 1.5f
            if (flashOn) drain *= 0.65f
            duality.stability = (duality.stability - drain * dt).coerceIn(8f, 100f)
        } else {
            val regen = duality.regenPerSec * (if (hasLocket) 2f else 1f) * (if (inAnchor) 2.5f else 1f)
            duality.stability = (duality.stability + regen * dt).coerceIn(0f, 100f)
        }
        headache = ((55f - duality.stability) / 55f).coerceIn(0f, 1f)
    }

    private fun updateInteractables(dt: Float) {
        val curW = duality.worldAt(playerPos.x, playerPos.y + 0.9f, playerPos.z)
        val visible = mutableListOf<Interactable>()
        var best: Interactable? = null
        var bestDist = Float.MAX_VALUE

        for (it in allInteractables) {
            if (!it.condition()) continue
            val wOk = when (it.world) {
                WorldFilter.ANY -> true
                WorldFilter.DREAM -> curW == 0
                WorldFilter.NIGHTMARE -> curW == 1
            }
            if (!wOk) continue
            visible.add(it)
            val d = hypot(hypot(it.pos.x - playerPos.x, it.pos.y - (playerPos.y + 0.8f)), it.pos.z - playerPos.z)
            if (d <= it.radius && d < bestDist) {
                bestDist = d
                best = it
            }
        }

        renderer.visibleInteractables = visible
        activeInteractable = best

        if (best != null && holdingAction && best.holdSeconds > 0f) {
            holdProgress += dt / best.holdSeconds
            if (holdProgress >= 1f) {
                holdProgress = 0f
                holdingAction = false
                triggerActiveInteractable()
            }
        } else if (!holdingAction || best == null) {
            holdProgress = 0f
        }

        _uiState.update {
            it.copy(
                nearbyPrompt = best?.labelProvider?.invoke(),
                nearbyIcon = best?.icon ?: InteractIcon.HAND,
                nearbyHoldDuration = best?.holdSeconds ?: 0f,
                holdProgress = holdProgress
            )
        }
    }

    // --- Controls from Compose HUD ---
    fun setJoystick(x: Float, y: Float) {
        joyX = x.coerceIn(-1f, 1f)
        joyY = y.coerceIn(-1f, 1f)
    }

    fun onLookDrag(dx: Float, dy: Float) {
        val s = _uiState.value.settings
        val mul = 0.0042f * s.sensitivity
        camYaw += dx * mul
        val ySign = if (s.invertY) -1f else 1f
        camPitch = (camPitch - dy * mul * ySign).coerceIn(-0.95f, 0.85f)
    }

    fun onActionPressStart() {
        val it = activeInteractable ?: return
        if (it.holdSeconds > 0f) {
            holdingAction = true
        } else {
            triggerActiveInteractable()
        }
    }

    fun onActionPressEnd() {
        holdingAction = false
        holdProgress = 0f
    }

    private fun triggerActiveInteractable() {
        val it = activeInteractable ?: return
        viewModelScope.launch {
            it.onInteract()
        }
    }

    fun togglePeerEye() {
        if (!flags["eye"].orFalse() && currentChapter == 1 && !flags["hasWokenUp"].orFalse()) return
        peering = !peering
        if (peering) {
            duality.toNight(playerPos, 0f, speed = 40f, force = true)
        } else {
            if (!duality.baseNight) duality.toDream(playerPos, speed = 40f)
            else duality.toNight(playerPos, 0f, speed = 40f)
        }
    }

    fun stopPeer() {
        if (peering) {
            peering = false
            if (!duality.baseNight) duality.toDream(playerPos, speed = 40f)
        }
    }

    fun toggleFlashlight() {
        if (!hasItem("broken_flashlight")) return
        flashOn = !flashOn
        audio.sfx("click")
    }

    fun setFlashOn(on: Boolean) {
        flashOn = on
    }

    fun useMemoryPhotoAnchor() {
        if (!hasItem("memory_photo")) return
        viewModelScope.launch {
            audio.sfx("paper")
            adjustStability(28f)
            stopPeer()
            duality.toDream(playerPos, speed = 45f)
            inspectModel(
                "item_memory_photo",
                "якорь памяти",
                "Фотография из нагрудного кармана",
                ItemsCatalog.ITEMS["memory_photo"]!!.desc
            )
        }
    }

    // --- Game Flow: New Game, Continue, Save/Load, Chapters ---
    fun startNewGame() {
        viewModelScope.launch {
            resetRun()
            val ch1 = ChaptersCatalog2.get(1)
            currentChapter = 1
            playerPos = Vec3(ch1.spawnX, ch1.spawnY, ch1.spawnZ)
            camYaw = ch1.spawnYaw
            playerYaw = ch1.spawnYaw
            loadSceneForCurrentChapter()
            _uiState.update {
                it.copy(
                    mode = AppMode.CINEMA,
                    activeModal = null,
                    endingState = null,
                    chapter = 1,
                    chapterKicker = ch1.kicker,
                    chapterTitle = ch1.title,
                    showChapterCard = true,
                    cinemaCanSkip = true
                )
            }
            audio.mode = "game"
            skipRequested = false

            waitSkippable(2.6f)
            _uiState.update { it.copy(showChapterCard = false) }
            if (!skipRequested) {
                say("Моя спальня… Кажется, сегодня понедельник. Мы с Михаилом только собираемся в экспедицию к Северному перевалу.", 4.2f)
                waitSkippable(4.0f)
            }
            if (!skipRequested) {
                say("Но почему в воздухе стоит запах сырости и речной воды, а в висках стучит так, словно эта поездка уже случилась?..", 4.0f)
                waitSkippable(3.8f)
            }

            giveItem("memory_photo", silent = true)
            setFlag("eye", true)
            setFlag("hasWokenUp", true)
            setObjective(ch1.defaultObjective)
            _uiState.update { it.copy(mode = AppMode.PLAYING, cinemaCanSkip = false, showChapterCard = false) }
            saveAutoCheckpoint(ch1.sceneName)
        }
    }

    fun continueFromAutoSave() {
        viewModelScope.launch {
            val payload = repo.loadSlot("auto") ?: return@launch
            applySavePayload(payload)
        }
    }

    fun loadFromSlot(slotId: String) {
        viewModelScope.launch {
            val payload = repo.loadSlot(slotId) ?: return@launch
            applySavePayload(payload)
        }
    }

    fun saveToSlot(slotId: String) {
        viewModelScope.launch {
            val chDef = ChaptersCatalog2.get(currentChapter)
            repo.saveToSlot(slotId, buildSavePayload(chDef.sceneName))
            toast("Игра сохранена в «${if (slotId == "auto") "Авто" else "Ячейка $slotId"}»")
            audio.sfx("success")
        }
    }

    private fun saveAutoCheckpoint(sceneName: String) {
        viewModelScope.launch {
            repo.saveToSlot("auto", buildSavePayload(sceneName))
        }
    }

    private fun buildSavePayload(sceneName: String) = SavePayload(
        sceneName = sceneName,
        chapter = currentChapter,
        px = playerPos.x,
        py = playerPos.y,
        pz = playerPos.z,
        yaw = camYaw,
        pitch = camPitch,
        stability = duality.stability,
        baseNight = duality.baseNight,
        flashOn = flashOn,
        inventory = inventory.toList(),
        flags = flags.toMap(),
        edits = edits.toMap(),
        clues = clues.toList(),
        testimonies = testimonies.toList(),
        conclusions = conclusions.toMap(),
        customLinks = customLinks.toMap(),
        objective = currentObjective
    )

    private fun applySavePayload(p: SavePayload) {
        resetRun()
        currentChapter = p.chapter.coerceIn(1, 10)
        playerPos = Vec3(p.px, p.py, p.pz)
        camYaw = p.yaw
        playerYaw = p.yaw
        camPitch = p.pitch
        duality.stability = p.stability
        duality.baseNight = p.baseNight
        duality.base = if (p.baseNight) 1 else 0
        flashOn = p.flashOn
        inventory.addAll(p.inventory)
        flags.putAll(p.flags)
        edits.putAll(p.edits)
        clues.addAll(p.clues)
        testimonies.addAll(p.testimonies)
        conclusions.putAll(p.conclusions)
        customLinks.putAll(p.customLinks)
        currentObjective = p.objective.ifEmpty { ChaptersCatalog2.get(currentChapter).defaultObjective }
        loadSceneForCurrentChapter()
        audio.mode = "game"
        _uiState.update { it.copy(mode = AppMode.PLAYING, activeModal = null, endingState = null) }
        syncCollectionState()
    }

    private fun resetRun() {
        duality.reset()
        inventory.clear()
        clues.clear()
        testimonies.clear()
        conclusions.clear()
        customLinks.clear()
        flags.clear()
        edits.clear()
        unreadBoardCount = 0
        flashOn = false
        peering = false
        inputLocked = false
        headache = 0f
        currentObjective = ""
        syncCollectionState()
    }

    fun loadSceneForCurrentChapter() {
        val scene = ChapterScenes.buildScene(currentChapter, edits, flags)
        activeScene = scene
        renderer.currentScene = scene
        renderer.sceneDirty = true
    }

    fun refreshSceneProps() {
        loadSceneForCurrentChapter()
    }

    fun advanceToChapter(nextCh: Int) {
        if (nextCh < 1 || nextCh > 10) return
        viewModelScope.launch {
            inputLocked = true
            _uiState.update { it.copy(mode = AppMode.CINEMA, activeModal = null, isLoadingChapter = true) }

            val prof = memoryProfile()
            if (prof.total > 0) {
                val bridge = when (prof.dominant) {
                    MemoryVector.TRUTH -> "Шаг за шагом я приближаюсь к тому, что действительно случилось в ту неделю…"
                    MemoryVector.DENIAL -> "Ничего страшного не произошло. Нужно просто прожить эту неделю спокойно…"
                    MemoryVector.PROJECTION -> "Кто-то вёл меня по этому маршруту с самого начала. Я найду все улики…"
                }
                say(bridge, 3.0f)
                delay(1400L)
            }

            currentChapter = nextCh
            val cd = ChaptersCatalog2.get(nextCh)
            duality.baseNight = nextCh >= 9
            duality.base = if (nextCh >= 9) 1 else 0
            duality.wave.active = false
            duality.nightTimer = 0f
            duality.stability = max(75f, duality.stability)
            peering = false

            playerPos = Vec3(cd.spawnX, cd.spawnY, cd.spawnZ)
            camYaw = cd.spawnYaw
            playerYaw = cd.spawnYaw
            loadSceneForCurrentChapter()
            setObjective(cd.defaultObjective)

            _uiState.update {
                it.copy(
                    isLoadingChapter = false,
                    chapter = nextCh,
                    chapterKicker = cd.kicker,
                    chapterTitle = cd.title,
                    showChapterCard = true
                )
            }
            delay(2500L)
            _uiState.update { it.copy(showChapterCard = false, mode = AppMode.PLAYING) }
            inputLocked = false
            saveAutoCheckpoint(cd.sceneName)
        }
    }

    // --- Narrative / Board / Inventory Helpers ---
    fun isNight(): Boolean = duality.worldAt(playerPos.x, playerPos.y + 0.9f, playerPos.z) == 1
    fun hasItem(id: String) = inventory.contains(id)
    fun giveItem(id: String, silent: Boolean = false) {
        if (!inventory.contains(id)) inventory.add(id)
        if (!silent) {
            audio.sfx("pickup")
            toast("Получено: ${ItemsCatalog.getDisplayName(id)}")
        }
        syncCollectionState()
    }
    fun takeItem(id: String) {
        inventory.remove(id)
        syncCollectionState()
    }
    suspend fun pickupItem(id: String, kicker: String = "найдено"): Boolean {
        giveItem(id)
        val def = ItemsCatalog.ITEMS[id]
        if (def != null) {
            inspectModel(def.model, kicker, def.name, def.desc)
        }
        return true
    }

    fun setFlag(key: String, v: Boolean) {
        flags[key] = v
        syncCollectionState()
    }
    fun setEdit(key: String, v: Boolean) {
        edits[key] = v
        loadSceneForCurrentChapter()
        syncCollectionState()
    }
    fun addClue(id: String) {
        if (clues.add(id)) {
            unreadBoardCount++
            toast("Улика в дневнике")
            syncCollectionState()
        }
    }
    fun hasClue(id: String) = clues.contains(id)
    fun hasChapterClues(ch: Int) = ChaptersCatalog2.get(ch).clues.any { clues.contains(it.id) }
    fun addTestimony(id: String) {
        if (testimonies.add(id)) {
            unreadBoardCount++
            toast("Показание записано в дневник")
            syncCollectionState()
        }
    }
    fun hasConclusion(ch: Int) = conclusions.containsKey(ch)
    fun lockConclusion(ch: Int, vec: MemoryVector, link: CustomLinkData) {
        conclusions[ch] = vec
        customLinks[ch] = link
        audio.sfx("success")
        val react = when (vec) {
            MemoryVector.TRUTH -> "Память обретает резкость. Сквозь туман проступает честная картина."
            MemoryVector.DENIAL -> "Сознание выбирает покой. Тревожные детали отступают."
            MemoryVector.PROJECTION -> "Подозрение пускает корни. Теперь каждая улика кажется чужим замыслом."
        }
        say(react, 4.0f)
        if (isMandatoryWorldDone(ch) && ch < 10) {
            setObjective("Вывод главы зафиксирован. Пройдите к выходу или нажмите «Перейти к Главе ${ch + 1}» в «Выводах»")
        }
        syncCollectionState()
    }

    fun memoryProfile(): MemoryProfile {
        var t = 0; var d = 0; var p = 0
        conclusions.values.forEach {
            when (it) {
                MemoryVector.TRUTH -> t++
                MemoryVector.DENIAL -> d++
                MemoryVector.PROJECTION -> p++
            }
        }
        return MemoryProfile(t, d, p)
    }

    fun adapt(defaultText: String = "", truthText: String = defaultText, denialText: String = defaultText, projectionText: String = defaultText): String {
        val prof = memoryProfile()
        if (prof.total == 0 && defaultText.isNotEmpty()) return defaultText
        return when (prof.dominant) {
            MemoryVector.TRUTH -> truthText
            MemoryVector.DENIAL -> denialText
            MemoryVector.PROJECTION -> projectionText
        }
    }

    fun isMandatoryWorldDone(ch: Int = currentChapter): Boolean = when (ch) {
        1 -> edits["ch1Door"] == true && hasItem("student_pass")
        2 -> edits["ch2Door"] == true && hasItem("wet_photo")
        3 -> edits["ch3Door"] == true && flags["ch3GarageInspected"] == true
        4 -> edits["ch4Door"] == true && hasItem("guestbook_page")
        5 -> edits["bridge1"] == true || flags["bridgeSolved"] == true
        6 -> hasItem("letter_full") && hasItem("photo_2") && hasItem("locket")
        7 -> hasItem("map_combined") && hasItem("photo_3")
        8 -> hasItem("license_plate") && hasItem("metal_shard")
        9 -> edits["grate"] == true && edits["tunnelWall"] == true
        10 -> hasItem("car_key")
        else -> false
    }

    fun isChapterExitReady(ch: Int = currentChapter): Boolean {
        if (ch >= 10) return isMandatoryWorldDone(10)
        return isMandatoryWorldDone(ch) && hasConclusion(ch)
    }

    fun adjustStability(delta: Float) {
        duality.stability = (duality.stability + delta).coerceIn(8f, 100f)
    }

    fun rotatePlayerYaw(delta: Float) {
        camYaw += delta
        playerYaw += delta
    }

    fun setInputLock(locked: Boolean) {
        inputLocked = locked
    }

    fun setObjective(text: String) {
        currentObjective = text
        _uiState.update { it.copy(objective = text) }
    }

    fun say(text: String, durSec: Float = 3.8f) = voice(text, durSec, null)

    fun voice(text: String, durSec: Float = 3.8f, speaker: String? = null) {
        subtitleJob?.cancel()
        subtitleJob = viewModelScope.launch {
            _uiState.update { it.copy(subtitleText = text, subtitleSpeaker = speaker) }
            delay((durSec * 1000L).toLong())
            _uiState.update { it.copy(subtitleText = null, subtitleSpeaker = null) }
        }
    }

    fun toast(msg: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(toasts = (it.toasts + msg).takeLast(3)) }
            delay(3000L)
            _uiState.update { st -> st.copy(toasts = st.toasts.drop(1)) }
        }
    }

    suspend fun waitSec(sec: Float) {
        delay((sec * 1000L).toLong())
    }

    private suspend fun waitSkippable(sec: Float) {
        val steps = (sec / 0.05f).toInt().coerceAtLeast(1)
        for (i in 0 until steps) {
            if (skipRequested) return
            delay(50L)
        }
    }

    fun skipIntroCinema() {
        skipRequested = true
    }

    fun vibrate(ms: Long) {
        val ctx = getApplication<Application>()
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val v = ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                @Suppress("DEPRECATION")
                v.vibrate(ms)
            }
        }
    }

    fun deleteSaveSlot(slotId: String) {
        viewModelScope.launch {
            repo.deleteSlot(slotId)
            toast("Сохранение удалено")
        }
    }

    private fun syncCollectionState() {
        val chDef = ChaptersCatalog2.get(currentChapter)
        val hasAnyClue = chDef.clues.any { clues.contains(it.id) }
        val hasAnyTest = chDef.npcs.any { it.testimony != null && testimonies.contains(it.testimony.id) }
        val canForm = currentChapter <= 9 && !conclusions.containsKey(currentChapter) && hasAnyClue && hasAnyTest
        val eyeEnabled = flags["eye"] == true || flags["hasWokenUp"] == true || currentChapter > 1
        _uiState.update {
            it.copy(
                chapter = currentChapter,
                canPeerEye = eyeEnabled,
                hasFlashlight = inventory.contains("broken_flashlight"),
                hasMemoryPhoto = inventory.contains("memory_photo"),
                inventory = inventory.toList(),
                clues = clues.toSet(),
                testimonies = testimonies.toSet(),
                conclusions = conclusions.toMap(),
                customLinks = customLinks.toMap(),
                unreadBoardCount = unreadBoardCount,
                canFormConclusionNow = canForm,
                flags = flags.toMap(),
                edits = edits.toMap(),
                objective = currentObjective
            )
        }
    }

    // --- Modals & Menus ---
    fun togglePause() {
        _uiState.update {
            when {
                it.activeModal != null -> {
                    dismissActiveModal()
                    it
                }
                it.mode == AppMode.PLAYING -> it.copy(mode = AppMode.PAUSED)
                it.mode == AppMode.PAUSED -> it.copy(mode = AppMode.PLAYING)
                else -> it
            }
        }
    }

    fun openInventory() {
        _uiState.update { it.copy(activeModal = ActiveModal.Inventory) }
    }

    fun openMemoryBoard() {
        unreadBoardCount = 0
        syncCollectionState()
        _uiState.update { it.copy(activeModal = ActiveModal.MemoryBoard) }
    }

    fun openSaveLoad(isSaving: Boolean) {
        _uiState.update { it.copy(activeModal = ActiveModal.SaveLoad(isSaving)) }
    }

    fun openSettings() {
        _uiState.update { it.copy(activeModal = ActiveModal.Settings) }
    }

    fun updateSettings(newSettings: GameSettings) {
        viewModelScope.launch { repo.updateSettings(newSettings) }
    }

    fun returnToMainMenu() {
        _uiState.update { it.copy(mode = AppMode.MENU, activeModal = null, endingState = null) }
        audio.mode = "menu"
    }

    fun dismissActiveModal() {
        inspectDeferred?.complete(Unit); inspectDeferred = null
        readerDeferred?.complete(Unit); readerDeferred = null
        npcDeferred?.complete(Unit); npcDeferred = null
        runeDeferred?.complete(false); runeDeferred = null
        letterDeferred?.complete(false); letterDeferred = null
        codeDeferred?.complete(false); codeDeferred = null
        mapDeferred?.complete(false); mapDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    // --- Async UI Dialog / Puzzle Bridges ---
    suspend fun inspectModel(modelId: String, kicker: String, title: String, desc: String) {
        val def = CompletableDeferred<Unit>()
        inspectDeferred = def
        _uiState.update { it.copy(activeModal = ActiveModal.Inspect(modelId, kicker, title, desc)) }
        def.await()
    }

    fun completeInspect() {
        inspectDeferred?.complete(Unit)
        inspectDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    suspend fun readPages(title: String, pages: List<String>, isNightPaper: Boolean) {
        val def = CompletableDeferred<Unit>()
        readerDeferred = def
        _uiState.update { it.copy(activeModal = ActiveModal.Reader(title, pages, isNightPaper)) }
        def.await()
    }

    fun completeReader() {
        readerDeferred?.complete(Unit)
        readerDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    suspend fun openNpcDialog(npc: NpcDef) {
        val dt = npc.dialogTree ?: return
        val def = CompletableDeferred<Unit>()
        npcDeferred = def
        val alreadyRec = npc.testimony?.let { testimonies.contains(it.id) } ?: false
        _uiState.update {
            it.copy(
                activeModal = ActiveModal.NpcDialogue(
                    npc = npc,
                    currentContext = dt.context,
                    currentSpeech = dt.greeting,
                    askedIndices = emptySet(),
                    testimonyRecorded = alreadyRec
                )
            )
        }
        def.await()
    }

    fun askNpcQuestion(index: Int) {
        val modal = _uiState.value.activeModal as? ActiveModal.NpcDialogue ?: return
        val dt = modal.npc.dialogTree ?: return
        val qObj = dt.questions.getOrNull(index) ?: return
        audio.sfx("paper")
        _uiState.update {
            it.copy(
                activeModal = modal.copy(
                    currentContext = "Элиас спрашивает: ${qObj.q}",
                    currentSpeech = qObj.a,
                    askedIndices = modal.askedIndices + index
                )
            )
        }
    }

    fun recordNpcTestimony() {
        val modal = _uiState.value.activeModal as? ActiveModal.NpcDialogue ?: return
        val t = modal.npc.testimony ?: return
        addTestimony(t.id)
        audio.sfx("success")
        _uiState.update { it.copy(activeModal = modal.copy(testimonyRecorded = true)) }
    }

    fun closeNpcDialog() {
        npcDeferred?.complete(Unit)
        npcDeferred = null
        _uiState.update { it.copy(activeModal = null) }
        if (hasChapterClues(currentChapter) && !hasConclusion(currentChapter)) {
            setObjective("Откройте «Выводы» сверху, чтобы связать улику и показание")
        }
    }

    suspend fun openRunePuzzle(kicker: String, title: String, text: String, solutions: List<List<String>>): Boolean {
        val def = CompletableDeferred<Boolean>()
        runeDeferred = def
        _uiState.update { it.copy(activeModal = ActiveModal.RunePuzzle(kicker, title, text, solutions)) }
        return def.await()
    }

    fun completeRunePuzzle(success: Boolean) {
        runeDeferred?.complete(success)
        runeDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    suspend fun openLetterPuzzle(): Boolean {
        val def = CompletableDeferred<Boolean>()
        letterDeferred = def
        _uiState.update { it.copy(activeModal = ActiveModal.LetterPuzzle(ItemsCatalog.LETTER_FRAGMENTS, ItemsCatalog.LETTER_TAIL)) }
        return def.await()
    }

    fun completeLetterPuzzle(success: Boolean) {
        letterDeferred?.complete(success)
        letterDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    suspend fun openCodePuzzle(title: String, text: String, targetCode: String): Boolean {
        val def = CompletableDeferred<Boolean>()
        codeDeferred = def
        _uiState.update { it.copy(activeModal = ActiveModal.CodePuzzle(title, text, targetCode)) }
        return def.await()
    }

    fun completeCodePuzzle(success: Boolean) {
        codeDeferred?.complete(success)
        codeDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    suspend fun openMapPuzzle(readOnly: Boolean): Boolean {
        val def = CompletableDeferred<Boolean>()
        mapDeferred = def
        _uiState.update { it.copy(activeModal = ActiveModal.MapPuzzle(readOnly)) }
        return def.await()
    }

    fun completeMapPuzzle(success: Boolean) {
        mapDeferred?.complete(success)
        mapDeferred = null
        _uiState.update { it.copy(activeModal = null) }
    }

    fun useInventoryItem(id: String) {
        val def = ItemsCatalog.ITEMS[id] ?: return
        when (def.useAction) {
            "photo" -> {
                _uiState.update { it.copy(activeModal = null) }
                useMemoryPhotoAnchor()
            }
            "read" -> {
                viewModelScope.launch {
                    val pages = if (id == "letter_full") listOf(
                        "Я не могу больше скрывать. Ты должен знать правду о том, что случилось у ручья.",
                        "Я не могу тебя найти. Три дня. Полиция ничего не делает. Я знаю, что ты был у ручья.",
                        "Вернись. Пожалуйста."
                    ) else listOf(def.desc)
                    readPages(def.name, pages, false)
                }
            }
            "flash" -> {
                _uiState.update { it.copy(activeModal = null) }
                toggleFlashlight()
            }
            else -> {
                if (def.combine && hasItem("map_dream") && hasItem("map_night")) {
                    toast("Подойдите к бревну у костра, чтобы совместить карты")
                } else {
                    viewModelScope.launch { inspectModel(def.model, "осмотр предмета", def.name, def.desc) }
                }
            }
        }
    }

    // --- Chapter 10 Flashback & 4 Endings ---
    suspend fun runCh10SourceFlashback() {
        setFlag("flashback", true)
        setInputLock(true)
        val prof = memoryProfile()
        say("Я смотрю в воду — и вся прошедшая неделя от понедельника до воскресенья складывается в единую картину.", 3.8f)
        waitSec(3.2f)
        inspectModel(
            modelId = if (prof.dominant == MemoryVector.PROJECTION) "mike_head_black" else "mike_head",
            kicker = "отражение в воде Источника",
            title = "Михаил",
            desc = adapt(
                truthText = "Мой лучший друг. В ту ночь у него был жар, но когда машина рухнула в реку, он со сломанной рукой вытащил меня на берег.",
                denialText = "Он спокойно улыбается мне, будто мы всё ещё сидим в университетской лаборатории в тихий понедельник.",
                projectionText = "Его взгляд кажется чужим и холодным — точно таким, каким я рисовал его в своих подозрениях всю дорогу."
            )
        )

        _uiState.update { it.copy(mode = AppMode.CINEMA, cinemaLight = false) }
        audio.mode = "ending"
        showCinemaLine(
            adapt(
                truthText = "Четверг, полночь. Я за рулём универсала 7319. Михаил рядом просит сбавить скорость.",
                denialText = "Солнечный лес. Тёплый чай на столе. Никакого дождя и никакого обрыва.",
                projectionText = "Тени у телефонной будки. Исправленные карты. Чужие голоса в ночи."
            ), 3.4f
        )
        audio.sfx("rain", durationSec = 2.0f)
        showCinemaLine("Мокрый карниз над водопадом. Скрежет тормозов.", 2.4f)
        audio.sfx("crash"); vibrate(350L)
        showCinemaLine("Ледяная вода ручья — и мерный писк приборов в Палате № 7.", 2.8f)

        audio.mode = "game"
        _uiState.update { it.copy(mode = AppMode.PLAYING, cinemaLines = emptyList()) }
        refreshSceneProps()
        say("У кромки воды блестит ключ зажигания.", 3.5f)
        setObjective("Поднять ключ зажигания у воды")
        setInputLock(false)
    }

    private suspend fun showCinemaLine(text: String, sec: Float) {
        _uiState.update { it.copy(cinemaLines = listOf(text)) }
        waitSec(sec)
    }

    fun triggerEndingTruth() {
        viewModelScope.launch {
            setFlag("ended", true)
            setInputLock(true)
            audio.mode = "ending"
            _uiState.update { it.copy(mode = AppMode.CINEMA, cinemaLight = true) }
            repeat(3) {
                audio.sfx("heart")
                waitSec(0.8f)
            }
            showCinemaLine("Белый потолок Палаты № 7. Мерный ритм кардиомонитора.", 3.0f)
            audio.sfx("beep", count = 3)
            showCinemaLine("Чей-то тёплый голос рядом: «Элиас! Он открыл глаза!»", 3.0f)
            showCinemaLine("У окна стоит Михаил с рукой на перевязи и светло улыбается тебе.", 3.2f)
            _uiState.update {
                it.copy(
                    mode = AppMode.ENDING,
                    cinemaLight = false,
                    cinemaLines = emptyList(),
                    endingState = EndingState(
                        vector = MemoryVector.TRUTH,
                        kicker = "тумбочка в Палате № 7",
                        title = "Прощение и Возвращение",
                        description = "Ты восстановил подлинную картину всех семи дней, принял свою ответственность за ту ночь и вернулся к тем, кто боролся за твою жизнь.",
                        subtitle = "Концовка Истины · «Пробуждение в Палате № 7»",
                        modelId = "item_photo_final",
                        buttonLabel = "Сделать вдох",
                        isTruthWithEpilogue = true
                    )
                )
            }
        }
    }

    fun triggerEndingDenial() {
        viewModelScope.launch {
            setFlag("ended", true)
            setInputLock(true)
            audio.mode = "ending"
            _uiState.update { it.copy(mode = AppMode.CINEMA, cinemaLight = true) }
            showCinemaLine("Шум водопада и писк больничных приборов стихают.", 2.8f)
            showCinemaLine("Наступает тёплое, солнечное утро понедельника.", 2.8f)
            showCinemaLine("На календаре — вечное начало недели перед поездкой, которая никогда не случится.", 3.4f)
            _uiState.update {
                it.copy(
                    mode = AppMode.ENDING,
                    cinemaLight = false,
                    cinemaLines = emptyList(),
                    endingState = EndingState(
                        vector = MemoryVector.DENIAL,
                        kicker = "письменный стол · понедельник",
                        title = "Вечный Понедельник",
                        description = "Игра приняла твою версию памяти: ты выбрал покой вместо боли, и мир снов бережно замкнул для тебя безмятежное утро.",
                        subtitle = "Концовка Иллюзии · «Вечный Понедельник»",
                        modelId = "item_student_card",
                        buttonLabel = "Остаться во сне"
                    )
                )
            }
        }
    }

    fun triggerEndingProjection() {
        viewModelScope.launch {
            setFlag("ended", true)
            setInputLock(true)
            audio.mode = "ending"
            _uiState.update { it.copy(mode = AppMode.CINEMA, cinemaLight = false) }
            showCinemaLine("Ты отворачиваешься от протянутой руки и уходишь прочь по холодным ступеням.", 3.0f)
            showCinemaLine("Ты доказал себе, что виноват чужой умысел — и теперь никто не смеет тебя судить.", 3.2f)
            showCinemaLine("Но улицы города пусты, а за твоей спиной стоит безмолвная тень.", 3.2f)
            _uiState.update {
                it.copy(
                    mode = AppMode.ENDING,
                    cinemaLines = emptyList(),
                    endingState = EndingState(
                        vector = MemoryVector.PROJECTION,
                        kicker = "холодное зеркало",
                        title = "Лабиринт Теней",
                        description = "Твоя память выстроила безупречную защиту из подозрений, но за стеной недоверия ты остался совершенно один.",
                        subtitle = "Концовка Проекции · «Лабиринт Теней»",
                        modelId = "mike_head_black",
                        buttonLabel = "Идти дальше одному"
                    )
                )
            }
        }
    }

    fun triggerEndingMixed() {
        viewModelScope.launch {
            setFlag("ended", true)
            setInputLock(true)
            audio.mode = "ending"
            _uiState.update { it.copy(mode = AppMode.CINEMA, cinemaLight = true) }
            audio.sfx("beep", count = 2)
            showCinemaLine("Свет больничной лампы пробивается сквозь лесной туман.", 2.8f)
            showCinemaLine("Ты очнулся в Палате № 7, но правда и вымысел в твоей памяти переплелись навсегда.", 3.2f)
            _uiState.update {
                it.copy(
                    mode = AppMode.ENDING,
                    cinemaLight = false,
                    cinemaLines = emptyList(),
                    endingState = EndingState(
                        vector = null,
                        kicker = "на ладони после пробуждения",
                        title = "Хрупкое Равновесие",
                        description = "Часть недели ты вспомнил честно, а часть — укрыл за защитной иллюзией. Но главное — ты вернулся в мир живых.",
                        subtitle = "Концовка Границы · «Хрупкое Равновесие»",
                        modelId = "item_petal_pink",
                        buttonLabel = "Сохранить в памяти"
                    )
                )
            }
        }
    }
}
