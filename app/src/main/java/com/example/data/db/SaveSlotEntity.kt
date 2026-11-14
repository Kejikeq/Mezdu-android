package com.example.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "save_slots")
data class SaveSlotEntity(
    @PrimaryKey val slotId: String, // "auto", "1", "2", "3"
    val timestamp: Long,
    val chapter: Int,
    val sceneName: String,
    val payloadJson: String
)
