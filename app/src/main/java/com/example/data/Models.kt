package com.example.data

import kotlinx.serialization.Serializable

@Serializable
enum class MemoryVector {
    TRUTH, DENIAL, PROJECTION
}

enum class WorldFilter {
    DREAM, NIGHTMARE, ANY
}

enum class InteractIcon {
    HAND, EYE, KEY, DOOR, FIRE, SOUND, READ, PHOTO, FLASH, BAG, COMBINE, SIT, SUN
}

data class Vec3(val x: Float, val y: Float, val z: Float) {
    operator fun plus(o: Vec3) = Vec3(x + o.x, y + o.y, z + o.z)
    operator fun minus(o: Vec3) = Vec3(x - o.x, y - o.y, z - o.z)
}

data class ItemNightVariant(
    val invModel: String,
    val desc: String
)

data class ItemDef(
    val id: String,
    val name: String,
    val shortName: String? = null,
    val model: String,
    val invModel: String = model,
    val desc: String,
    val hint: String,
    val useAction: String? = null, // "photo" | "read" | "flash"
    val combine: Boolean = false,
    val nightVariant: ItemNightVariant? = null
)

data class LetterFragment(
    val text: String,
    val isNight: Boolean = false
)

data class ClueDef(
    val id: String,
    val title: String,
    val mandatory: Boolean,
    val desc: String
)

data class TestimonyDef(
    val id: String,
    val speaker: String,
    val summary: String,
    val vector: MemoryVector
)

data class DialogQuestion(
    val q: String,
    val a: String
)

data class DialogTreeDef(
    val context: String,
    val greeting: String,
    val questions: List<DialogQuestion>
)

data class NpcDef(
    val id: String,
    val name: String,
    val role: String,
    val type: String, // "real" | "phantom_denial" | "phantom_projection" | "companion"
    val model: String,
    val x: Float,
    val z: Float,
    val y: Float? = null,
    val yaw: Float = 0f,
    val world: WorldFilter = WorldFilter.ANY,
    val lines: List<Pair<String, String>>,
    val dialogTree: DialogTreeDef? = null,
    val testimony: TestimonyDef? = null
)

data class ConclusionDef(
    val vector: MemoryVector,
    val title: String,
    val text: String,
    val reqClue: String,
    val reqTestimony: String
)

data class ChapterDef(
    val id: Int,
    val kicker: String,
    val title: String,
    val subtitle: String,
    val sceneName: String,
    val spawnX: Float,
    val spawnY: Float,
    val spawnZ: Float,
    val spawnYaw: Float,
    val defaultObjective: String,
    val mandatoryGateHint: String,
    val clues: List<ClueDef>,
    val npcs: List<NpcDef>,
    val conclusions: List<ConclusionDef>
)

data class Interactable(
    val id: String,
    var pos: Vec3,
    val radius: Float = 2.4f,
    val world: WorldFilter = WorldFilter.ANY,
    val labelProvider: () -> String,
    val icon: InteractIcon = InteractIcon.HAND,
    val holdSeconds: Float = 0f,
    val condition: () -> Boolean = { true },
    val onInteract: suspend () -> Unit
)

data class ScreenGlint(
    val id: String,
    val nx: Float, // normalized 0..1 screen x
    val ny: Float, // normalized 0..1 screen y
    val icon: InteractIcon,
    val active: Boolean
)

@Serializable
data class GameSettings(
    val sensitivity: Float = 1.0f,
    val invertY: Boolean = false,
    val musicVolume: Float = 0.7f,
    val sfxVolume: Float = 0.85f,
    val thirdPerson: Boolean = true,
    val showFps: Boolean = false,
    val renderScale: Float = 1.0f
)

@Serializable
data class CustomLinkData(
    val clueId: String,
    val testimonyId: String
)

@Serializable
data class SavePayload(
    val version: Int = 2,
    val timestamp: Long = 0L,
    val sceneName: String = "",
    val chapter: Int = 1,
    val px: Float = 0f,
    val py: Float = 11f,
    val pz: Float = 0f,
    val yaw: Float = 0f,
    val pitch: Float = 0f,
    val stability: Float = 100f,
    val baseNight: Boolean = false,
    val flashOn: Boolean = false,
    val inventory: List<String> = emptyList(),
    val flags: Map<String, Boolean> = emptyMap(),
    val edits: Map<String, Boolean> = emptyMap(),
    val clues: List<String> = emptyList(),
    val testimonies: List<String> = emptyList(),
    val conclusions: Map<Int, MemoryVector> = emptyMap(),
    val customLinks: Map<Int, CustomLinkData> = emptyMap(),
    val objective: String = ""
)

data class SaveSlotInfo(
    val slotId: String, // "auto", "1", "2", "3"
    val label: String,
    val payload: SavePayload?
)

enum class AppMode {
    MENU, PLAYING, PAUSED, CINEMA, ENDING
}

data class EndingState(
    val vector: MemoryVector?, // null = MIXED
    val kicker: String,
    val title: String,
    val description: String,
    val subtitle: String,
    val modelId: String,
    val buttonLabel: String,
    val isTruthWithEpilogue: Boolean = false
)

sealed class ActiveModal {
    data object Inventory : ActiveModal()
    data object MemoryBoard : ActiveModal()
    data class SaveLoad(val isSaving: Boolean) : ActiveModal()
    data object Settings : ActiveModal()
    data class Inspect(
        val modelId: String,
        val kicker: String,
        val title: String,
        val desc: String,
        val buttonLabel: String = "Закрыть"
    ) : ActiveModal()
    data class Reader(
        val title: String,
        val pages: List<String>,
        val isNightPaper: Boolean = false
    ) : ActiveModal()
    data class NpcDialogue(
        val npc: NpcDef,
        val currentContext: String,
        val currentSpeech: String,
        val askedIndices: Set<Int>,
        val testimonyRecorded: Boolean
    ) : ActiveModal()
    data class RunePuzzle(
        val kicker: String,
        val title: String,
        val text: String,
        val solutions: List<List<String>>
    ) : ActiveModal()
    data class LetterPuzzle(
        val fragments: List<LetterFragment>,
        val tail: String
    ) : ActiveModal()
    data class CodePuzzle(
        val title: String,
        val text: String,
        val targetCode: String
    ) : ActiveModal()
    data class MapPuzzle(
        val isReadOnlyView: Boolean = false
    ) : ActiveModal()
}

data class MemoryProfile(
    val truth: Int = 0,
    val denial: Int = 0,
    val projection: Int = 0
) {
    val total: Int get() = truth + denial + projection
    val dominant: MemoryVector
        get() = when {
            denial > truth && denial >= projection -> MemoryVector.DENIAL
            projection > truth && projection > denial -> MemoryVector.PROJECTION
            else -> MemoryVector.TRUTH
        }
}

data class GameUiState(
    val mode: AppMode = AppMode.MENU,
    val chapter: Int = 1,
    val chapterKicker: String = "",
    val chapterTitle: String = "",
    val showChapterCard: Boolean = false,
    val fadeAlpha: Float = 0f,
    val fadeColorHex: Long = 0xFF000000,
    val isNight: Boolean = false,
    val nightTimerRemaining: Float = 0f,
    val stability: Float = 100f,
    val heartRateBpm: Int = 68,
    val headache: Float = 0f,
    val objective: String = "",
    val subtitleText: String? = null,
    val subtitleSpeaker: String? = null,
    val toasts: List<String> = emptyList(),
    val nearbyPrompt: String? = null,
    val nearbyIcon: InteractIcon = InteractIcon.HAND,
    val nearbyHoldDuration: Float = 0f,
    val holdProgress: Float = 0f,
    val canPeerEye: Boolean = false,
    val peering: Boolean = false,
    val hasFlashlight: Boolean = false,
    val flashOn: Boolean = false,
    val hasMemoryPhoto: Boolean = false,
    val isSitting: Boolean = false,
    val inventory: List<String> = emptyList(),
    val clues: Set<String> = emptySet(),
    val testimonies: Set<String> = emptySet(),
    val conclusions: Map<Int, MemoryVector> = emptyMap(),
    val customLinks: Map<Int, CustomLinkData> = emptyMap(),
    val unreadBoardCount: Int = 0,
    val canFormConclusionNow: Boolean = false,
    val flags: Map<String, Boolean> = emptyMap(),
    val edits: Map<String, Boolean> = emptyMap(),
    val settings: GameSettings = GameSettings(),
    val fps: Int = 60,
    val glints: List<ScreenGlint> = emptyList(),
    val activeModal: ActiveModal? = null,
    val cinemaLines: List<String> = emptyList(),
    val cinemaLight: Boolean = false,
    val cinemaCanSkip: Boolean = false,
    val endingState: EndingState? = null,
    val saveSlots: List<SaveSlotInfo> = emptyList(),
    val hasAutoSave: Boolean = false,
    val isLoadingChapter: Boolean = false
)
