package com.example.data.db

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.example.data.GameSettings
import com.example.data.SavePayload
import com.example.data.SaveSlotInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "mezhdu_settings")

class GameRepository(private val context: Context) {
    private val dao = AppDatabase.getInstance(context).saveSlotDao()
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private object PrefKeys {
        val SENSITIVITY = floatPreferencesKey("sens")
        val INVERT_Y = booleanPreferencesKey("invert_y")
        val MUSIC_VOL = floatPreferencesKey("music_vol")
        val SFX_VOL = floatPreferencesKey("sfx_vol")
        val THIRD_PERSON = booleanPreferencesKey("third_person")
        val SHOW_FPS = booleanPreferencesKey("show_fps")
        val RENDER_SCALE = floatPreferencesKey("render_scale")
    }

    val settingsFlow: Flow<GameSettings> = context.settingsDataStore.data.map { prefs ->
        GameSettings(
            sensitivity = prefs[PrefKeys.SENSITIVITY] ?: 1.0f,
            invertY = prefs[PrefKeys.INVERT_Y] ?: false,
            musicVolume = prefs[PrefKeys.MUSIC_VOL] ?: 0.7f,
            sfxVolume = prefs[PrefKeys.SFX_VOL] ?: 0.85f,
            thirdPerson = prefs[PrefKeys.THIRD_PERSON] ?: true,
            showFps = prefs[PrefKeys.SHOW_FPS] ?: false,
            renderScale = prefs[PrefKeys.RENDER_SCALE] ?: 1.0f
        )
    }

    suspend fun updateSettings(settings: GameSettings) {
        context.settingsDataStore.edit { prefs ->
            prefs[PrefKeys.SENSITIVITY] = settings.sensitivity
            prefs[PrefKeys.INVERT_Y] = settings.invertY
            prefs[PrefKeys.MUSIC_VOL] = settings.musicVolume
            prefs[PrefKeys.SFX_VOL] = settings.sfxVolume
            prefs[PrefKeys.THIRD_PERSON] = settings.thirdPerson
            prefs[PrefKeys.SHOW_FPS] = settings.showFps
            prefs[PrefKeys.RENDER_SCALE] = settings.renderScale
        }
    }

    val saveSlotsFlow: Flow<List<SaveSlotInfo>> = dao.observeAllSlots().map { entities ->
        val byId = entities.associateBy { it.slotId }
        val order = listOf(
            "auto" to "Автосохранение",
            "1" to "Ячейка 1",
            "2" to "Ячейка 2",
            "3" to "Ячейка 3"
        )
        order.map { (id, label) ->
            val entity = byId[id]
            val payload = entity?.let {
                runCatching { json.decodeFromString<SavePayload>(it.payloadJson) }.getOrNull()
            }
            SaveSlotInfo(slotId = id, label = label, payload = payload)
        }
    }

    suspend fun saveToSlot(slotId: String, payload: SavePayload) {
        val now = System.currentTimeMillis()
        val stamped = payload.copy(timestamp = now)
        val encoded = json.encodeToString(stamped)
        dao.upsertSlot(
            SaveSlotEntity(
                slotId = slotId,
                timestamp = now,
                chapter = stamped.chapter,
                sceneName = stamped.sceneName,
                payloadJson = encoded
            )
        )
    }

    suspend fun loadSlot(slotId: String): SavePayload? {
        val entity = dao.getSlot(slotId) ?: return null
        return runCatching { json.decodeFromString<SavePayload>(entity.payloadJson) }.getOrNull()
    }

    suspend fun deleteSlot(slotId: String) {
        dao.deleteSlot(slotId)
    }
}
