package com.example.data

import com.example.data.WorldCoords.P_BENCH
import com.example.data.WorldCoords.P_CAMPFIRE
import com.example.data.WorldCoords.P_CAVE
import com.example.data.WorldCoords.P_CLIFF
import com.example.data.WorldCoords.P_CROSSING
import com.example.data.WorldCoords.P_MEADOW
import com.example.data.WorldCoords.P_POOL
import com.example.data.WorldCoords.P_START
import com.example.data.WorldCoords.P_THICKET
import com.example.data.WorldCoords.P_UPSTREAM
import com.example.data.WorldCoords.crX
import com.example.data.WorldCoords.crZ
import com.example.data.WorldCoords.hoX
import com.example.data.WorldCoords.hoZ
import com.example.data.WorldCoords.m
import com.example.data.WorldCoords.mdX
import com.example.data.WorldCoords.mdZ
import com.example.data.WorldCoords.noX
import com.example.data.WorldCoords.noZ
import com.example.data.WorldCoords.tkX
import com.example.data.WorldCoords.tkZ
import com.example.data.WorldCoords.upaX
import com.example.data.WorldCoords.upaZ
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

enum class VoxelShape {
    BOX, TREE_OAK, TREE_PINE, LAMP, HOUSE_SHELL, TABLE, SOFA, BED, BOOKSHELF, DRAWERS,
    FIREPLACE, BENCH, CAR, BRIDGE_DECK, STONE_FACE, RUNESTONE, FIGURE, DEER, RABBIT,
    CHEST, PHONE_BOOTH, WATER_PLANE, ITEM_ORB, DOOR_LEAF
}

data class SceneProp(
    val id: String,
    val shape: VoxelShape,
    var x: Float,
    var y: Float,
    var z: Float,
    var sx: Float = 1f,
    var sy: Float = 1f,
    var sz: Float = 1f,
    var yaw: Float = 0f,
    val dreamColor: Int,
    val nightColor: Int,
    val mask: Int = 3, // 1 = Dream only, 2 = Night only, 3 = Both
    var visible: Boolean = true,
    val highlight: Boolean = false,
    val emissive: Boolean = false
)

data class BoxCollider(
    val id: String,
    val x0: Float,
    val x1: Float,
    val y0: Float,
    val y1: Float,
    val z0: Float,
    val z1: Float,
    var mask: Int = 3
)

data class WorldLight(
    val x: Float,
    val y: Float,
    val z: Float,
    val radius: Float,
    val r: Float,
    val g: Float,
    val b: Float,
    val intensity: Float,
    val mask: Int = 3,
    val flicker: Boolean = false
)

data class ChapterSceneData(
    val chapter: Int,
    val groundY: Float,
    val boundsX0: Float,
    val boundsX1: Float,
    val boundsZ0: Float,
    val boundsZ1: Float,
    val props: MutableList<SceneProp>,
    val colliders: MutableList<BoxCollider>,
    val lights: MutableList<WorldLight>,
    val heightResolver: (x: Float, z: Float, curY: Float) -> Float
)

object ChapterScenes {
    fun buildScene(chapter: Int, edits: Map<String, Boolean>, flags: Map<String, Boolean>): ChapterSceneData {
        val props = mutableListOf<SceneProp>()
        val colliders = mutableListOf<BoxCollider>()
        val lights = mutableListOf<WorldLight>()

        fun addBox(
            id: String, x: Float, y: Float, z: Float, sx: Float, sy: Float, sz: Float,
            dreamCol: Int, nightCol: Int, mask: Int = 3, solid: Boolean = false, emissive: Boolean = false
        ) {
            props.add(SceneProp(id, VoxelShape.BOX, x, y, z, sx, sy, sz, 0f, dreamCol, nightCol, mask, true, false, emissive))
            if (solid) {
                colliders.add(BoxCollider("col_$id", x - sx * 0.5f, x + sx * 0.5f, y, y + sy, z - sz * 0.5f, z + sz * 0.5f, mask))
            }
        }

        fun addProp(
            id: String, shape: VoxelShape, x: Float, y: Float, z: Float,
            sx: Float = 1f, sy: Float = 1f, sz: Float = 1f, yaw: Float = 0f,
            dreamCol: Int, nightCol: Int, mask: Int = 3, visible: Boolean = true,
            highlight: Boolean = false, emissive: Boolean = false
        ): SceneProp {
            val p = SceneProp(id, shape, x, y, z, sx, sy, sz, yaw, dreamCol, nightCol, mask, visible, highlight, emissive)
            props.add(p)
            return p
        }

        fun addLamp(id: String, x: Float, y: Float, z: Float, warm: Boolean = true) {
            addProp(id, VoxelShape.LAMP, x, y, z, 0.35f, 4.0f, 0.35f, 0f, 0xFF2B2D32.toInt(), 0xFF1A151B.toInt(), 3, true, false, false)
            addProp("${id}_bulb", VoxelShape.BOX, x, y + 3.9f, z, 0.32f, 0.32f, 0.32f, 0f, 0xFFFFD27D.toInt(), 0xFFFF5E42.toInt(), 3, true, false, true)
            lights.add(WorldLight(x, y + 3.7f, z, 11f, if (warm) 1f else 0.7f, if (warm) 0.78f else 0.85f, if (warm) 0.45f else 1f, 2.2f, 3, false))
        }

        fun addTreeRing(cx: Float, cz: Float, baseY: Float, radiusMin: Float, radiusMax: Float, count: Int, pine: Boolean = false) {
            for (i in 0 until count) {
                val a = (i.toFloat() / count) * (PI.toFloat() * 2f) + (i % 3) * 0.17f
                val r = radiusMin + ((i * 37) % 100) / 100f * (radiusMax - radiusMin)
                val tx = cx + cos(a) * r
                val tz = cz + sin(a) * r
                val h = 4.2f + (i % 4) * 0.85f
                addProp(
                    "tree_${chapter}_$i",
                    if (pine) VoxelShape.TREE_PINE else VoxelShape.TREE_OAK,
                    tx, baseY, tz,
                    1.6f, h, 1.6f, a,
                    if (pine) 0xFF3E6342.toInt() else 0xFFC86D3B.toInt(),
                    0xFF2B1C22.toInt(),
                    3
                )
            }
        }

        val floorY: Float
        val bounds: FloatArray
        val heightResolver: (Float, Float, Float) -> Float

        when (chapter) {
            1 -> {
                floorY = 7.0f
                val f2 = 11.0f
                val baseY = 3.625f
                bounds = floatArrayOf(m(192f), m(596f), m(2044f), m(2318f))

                // Ground + Maple street + Square courtyard
                addBox("ch1_ground", m(394f), floorY - 0.5f, m(2180f), 62f, 0.5f, 44f, 0xFF567346.toInt(), 0xFF1D1820.toInt())
                addBox("ch1_street", m(394f), floorY - 0.46f, m(2162f), 58f, 0.48f, 4.5f, 0xFF5A5D66.toInt(), 0xFF26212A.toInt())
                addBox("ch1_plaza", m(400f), floorY - 0.44f, m(2126f), 14f, 0.46f, 12f, 0xFF9C9386.toInt(), 0xFF342B35.toInt())

                // Elias's Two-Story House (x: 336..484 -> 42.0..60.5, z: 2194..2290 -> 274.25..286.25)
                val hx0 = m(336f); val hx1 = m(484f); val hz0 = m(2194f); val hz1 = m(2290f)
                // 1st floor slab & 2nd floor slab (leaving stairwell opening x: 400..422, z: 2236..2266)
                addBox("house_floor1", (hx0 + hx1) * 0.5f, floorY - 0.1f, (hz0 + hz1) * 0.5f, hx1 - hx0, 0.12f, hz1 - hz0, 0xFF8C623E.toInt(), 0xFF382726.toInt())
                addBox("house_floor2_w", m(368f), f2 - 0.18f, m(2242f), m(64f), 0.2f, m(96f), 0xFF9A6F48.toInt(), 0xFF322325.toInt())
                addBox("house_floor2_e", m(454f), f2 - 0.18f, m(2242f), m(60f), 0.2f, m(96f), 0xFF9A6F48.toInt(), 0xFF322325.toInt())
                addBox("house_floor2_n", m(408f), f2 - 0.18f, m(2212f), m(32f), 0.2f, m(36f), 0xFF9A6F48.toInt(), 0xFF322325.toInt())

                // Staircase 1F <-> 2F along x=408, z=2240..2268
                for (step in 0 until 10) {
                    val sy = floorY + step * 0.4f
                    val sz = m(2268f - step * 2.8f)
                    addBox("stair_up_$step", m(410f), sy, sz, 1.8f, 0.35f, 0.42f, 0xFFA5774B.toInt(), 0xFF3B2826.toInt())
                }
                // Basement floor + stairs
                addBox("house_basement_floor", m(408f), baseY - 0.2f, m(2242f), 17f, 0.25f, 11f, 0xFF5B5D63.toInt(), 0xFF221A20.toInt())
                for (step in 0 until 8) {
                    val sy = baseY + step * 0.42f
                    val sz = m(2284f - step * 3.0f)
                    addBox("stair_dn_$step", m(398f), sy, sz, 1.6f, 0.35f, 0.45f, 0xFF706B66.toInt(), 0xFF2D2225.toInt())
                }

                // Exterior House Walls (with front doorway gap at x=404..412, z=2194)
                addBox("wall_h_n_w", m(370f), floorY, hz0, m(68f), 7.2f, 0.35f, 0xFFD9CDB8.toInt(), 0xFF3D2E36.toInt(), solid = true)
                addBox("wall_h_n_e", m(448f), floorY, hz0, m(72f), 7.2f, 0.35f, 0xFFD9CDB8.toInt(), 0xFF3D2E36.toInt(), solid = true)
                addBox("wall_h_n_top", m(408f), floorY + 2.4f, hz0, m(12f), 4.8f, 0.35f, 0xFFD9CDB8.toInt(), 0xFF3D2E36.toInt())
                addBox("wall_h_s", (hx0 + hx1) * 0.5f, floorY, hz1, hx1 - hx0, 7.2f, 0.35f, 0xFFD9CDB8.toInt(), 0xFF3D2E36.toInt(), solid = true)
                addBox("wall_h_w", hx0, floorY, (hz0 + hz1) * 0.5f, 0.35f, 7.2f, hz1 - hz0, 0xFFD9CDB8.toInt(), 0xFF3D2E36.toInt(), solid = true)
                addBox("wall_h_e", hx1, floorY, (hz0 + hz1) * 0.5f, 0.35f, 7.2f, hz1 - hz0, 0xFFD9CDB8.toInt(), 0xFF3D2E36.toInt(), solid = true)

                // Front Door (closes until ch1Door edit is true)
                val doorUnlocked = edits["ch1Door"] == true
                addProp(
                    "ch1_front_door", VoxelShape.DOOR_LEAF,
                    m(408f), floorY, hz0, 1.0f, 2.2f, 0.16f,
                    if (doorUnlocked) -1.4f else 0f,
                    0xFF6B3E26.toInt(), 0xFF321818.toInt(), 3, true
                )
                if (!doorUnlocked) {
                    colliders.add(BoxCollider("col_ch1_front_door", m(403f), m(413f), floorY, floorY + 2.4f, hz0 - 0.3f, hz0 + 0.3f, 3))
                }

                // 2F Master Bedroom Furniture
                addProp("ch1_bed", VoxelShape.BED, m(477.5f), f2, m(2214f), 2.1f, 0.7f, 1.5f, -1.57f, 0xFF4C6B8A.toInt(), 0xFF301A24.toInt())
                addProp("ch1_nightstand", VoxelShape.DRAWERS, m(481.6f), f2, m(2202f), 0.9f, 0.85f, 0.9f, -1.57f, 0xFF7D5333.toInt(), 0xFF36211F.toInt())
                addProp("ch1_sedative", VoxelShape.ITEM_ORB, m(481.6f), f2 + 0.95f, m(2202f), 0.3f, 0.3f, 0.3f, 0f, 0xFF6FC4FF.toInt(), 0xFFFF5E5E.toInt(), highlight = true, emissive = true)
                addProp("ch1_dresser", VoxelShape.DRAWERS, m(427.2f), f2, m(2216f), 1.0f, 0.95f, 1.2f, 1.57f, 0xFF7D5333.toInt(), 0xFF36211F.toInt())
                addProp("ch1_receipt", VoxelShape.ITEM_ORB, m(427.2f), f2 + 1.05f, m(2216f), 0.3f, 0.3f, 0.3f, 0f, 0xFFF2C879.toInt(), 0xFFFF7A59.toInt(), highlight = true, emissive = true)
                addProp("ch1_calendar", VoxelShape.BOX, m(436f), f2 + 1.3f, m(2195.2f), 0.7f, 0.9f, 0.08f, 0f, 0xFFECE3D0.toInt(), 0xFFA02C2C.toInt(), highlight = true)
                addProp("ch1_wardrobe", VoxelShape.BOOKSHELF, m(427.6f), f2, m(2238f), 1.3f, 2.1f, 0.65f, 1.57f, 0xFF6E472B.toInt(), 0xFF2B1C1B.toInt())

                // 1F Study, Living Room, Kitchen, Hallway Mirror & Clock
                addProp("ch1_study_desk", VoxelShape.TABLE, m(364f), floorY, m(2205f), 1.5f, 0.75f, 0.9f, 0f, 0xFF825838.toInt(), 0xFF311F1F.toInt())
                addProp("ch1_pass_orb", VoxelShape.ITEM_ORB, m(364.8f), floorY + 0.85f, m(2205f), 0.28f, 0.28f, 0.28f, 0f, 0xFFF2C879.toInt(), 0xFFE0503F.toInt(), highlight = true, emissive = true)
                addProp("ch1_mirror", VoxelShape.BOX, m(393.4f), floorY + 0.9f, m(2201f), 0.14f, 1.6f, 0.9f, 0f, 0xFFAAD4EE.toInt(), 0xFF551A25.toInt(), highlight = true, emissive = true)
                addProp("ch1_clock", VoxelShape.BOOKSHELF, m(418f), floorY, m(2197f), 0.65f, 2.2f, 0.55f, 0f, 0xFF5B3721.toInt(), 0xFF2A1818.toInt())
                addProp("ch1_fireplace", VoxelShape.FIREPLACE, m(481f), floorY, m(2224f), 0.9f, 1.8f, 1.6f, -1.57f, 0xFF7B4837.toInt(), 0xFF2D1E22.toInt(), emissive = true)
                addProp("ch1_sofa", VoxelShape.SOFA, m(446f), floorY, m(2224f), 1.9f, 0.85f, 0.9f, 1.57f, 0xFF915C3A.toInt(), 0xFF382125.toInt())
                addProp("ch1_dining_table", VoxelShape.TABLE, m(446f), floorY, m(2268f), 1.6f, 0.75f, 1.1f, 0f, 0xFF8B603C.toInt(), 0xFF2F2020.toInt())
                addProp("ch1_fridge", VoxelShape.BOOKSHELF, m(480.8f), floorY, m(2254f), 0.9f, 2.0f, 0.9f, -1.57f, 0xFFD9DFDF.toInt(), 0xFF4E5961.toInt())
                addProp("ch1_enlarger", VoxelShape.TABLE, m(372f), baseY, m(2208.5f), 1.3f, 0.9f, 0.8f, 0f, 0xFF6B3E2E.toInt(), 0xFF45191C.toInt())

                // Yard, Street, Neighborhood Buildings
                addProp("ch1_phonebooth", VoxelShape.PHONE_BOOTH, m(422f), floorY, m(2178f), 0.95f, 2.3f, 0.95f, 0f, 0xFFAA3B32.toInt(), 0xFF3B191D.toInt())
                addProp("ch1_bench_sq", VoxelShape.BENCH, m(406f), floorY, m(2144f), 1.6f, 0.8f, 0.65f, 0f, 0xFF885B36.toInt(), 0xFF362422.toInt())
                addProp("ch1_scarf", VoxelShape.ITEM_ORB, m(406f), floorY + 0.65f, m(2144f), 0.3f, 0.3f, 0.3f, 0f, 0xFF4CAF7B.toInt(), 0xFF6FC98D.toInt(), highlight = true, emissive = true)
                addProp("ch1_car_1", VoxelShape.CAR, m(352f), floorY, m(2171f), 4.2f, 1.45f, 1.85f, 0f, 0xFF3A5C8A.toInt(), 0xFF1F2433.toInt())
                addProp("ch1_car_2", VoxelShape.CAR, m(452f), floorY, m(2158f), 4.4f, 1.5f, 1.9f, PI.toFloat(), 0xFF3E638E.toInt(), 0xFF281920.toInt())

                // Neighborhood Cottages & University Archway
                addProp("ch1_miller_house", VoxelShape.HOUSE_SHELL, m(230f), floorY, m(2226f), 7.5f, 3.8f, 7.0f, 0f, 0xFFC59B78.toInt(), 0xFF36282B.toInt())
                addProp("ch1_wagner_house", VoxelShape.HOUSE_SHELL, m(554f), floorY, m(2226f), 7.5f, 4.0f, 7.0f, 0f, 0xFF9D5844.toInt(), 0xFF362124.toInt())
                addProp("ch1_apothecary_house", VoxelShape.HOUSE_SHELL, m(240f), floorY, m(2075f), 7.0f, 3.8f, 5.5f, 0f, 0xFF88A49B.toInt(), 0xFF233036.toInt())
                addProp("ch1_uni_hall", VoxelShape.HOUSE_SHELL, m(480f), floorY, m(2073f), 8.0f, 4.2f, 5.5f, 0f, 0xFFB8A98E.toInt(), 0xFF342C2B.toInt())
                addBox("ch1_uni_arch_l", m(395f), floorY, m(2096f), 0.9f, 3.6f, 0.9f, 0xFFB8A88C.toInt(), 0xFF3A2C2E.toInt())
                addBox("ch1_uni_arch_r", m(405f), floorY, m(2096f), 0.9f, 3.6f, 0.9f, 0xFFB8A88C.toInt(), 0xFF3A2C2E.toInt())
                addBox("ch1_uni_arch_top", m(400f), floorY + 3.2f, m(2096f), 2.4f, 0.8f, 1.0f, 0xFFB8A88C.toInt(), 0xFF3A2C2E.toInt(), emissive = true)

                addLamp("ch1_l1", m(396f), floorY, m(2178f))
                addLamp("ch1_l2", m(328f), floorY, m(2178f))
                addLamp("ch1_l3", m(474f), floorY, m(2178f))
                addLamp("ch1_l4", m(360f), floorY, m(2151f))
                addLamp("ch1_l5", m(438f), floorY, m(2151f))
                addTreeRing(m(400f), m(2180f), floorY, 26f, 38f, 18)

                lights.add(WorldLight(m(454f), f2 + 2.5f, m(2234f), 10f, 1f, 0.82f, 0.55f, 2.0f, 1))
                lights.add(WorldLight(m(364f), floorY + 2.8f, m(2216f), 9f, 1f, 0.8f, 0.5f, 2.0f, 1))
                lights.add(WorldLight(m(372f), baseY + 2.4f, m(2224f), 8f, 1f, 0.15f, 0.1f, 2.5f, 3, true))

                heightResolver = { x, z, curY ->
                    val inHouse = x in hx0..hx1 && z in hz0..hz1
                    when {
                        !inHouse -> floorY
                        // Basement stairway zone
                        x in m(392f)..m(405f) && z in m(2252f)..m(2288f) && curY < floorY + 0.5f -> {
                            val t = ((m(2284f) - z) / (m(2284f) - m(2258f))).coerceIn(0f, 1f)
                            baseY + t * (floorY - baseY)
                        }
                        curY < floorY - 1.2f -> baseY
                        // 2F Main stairway
                        x in m(402f)..m(420f) && z in m(2236f)..m(2272f) -> {
                            val t = ((m(2268f) - z) / (m(2268f) - m(2240f))).coerceIn(0f, 1f)
                            floorY + t * (f2 - floorY)
                        }
                        curY > floorY + 2.1f -> f2
                        else -> floorY
                    }
                }
            }

            2 -> {
                floorY = 7.0f
                bounds = floatArrayOf(m(360f), m(440f), m(1866f), m(1954f))
                addBox("ch2_ground", m(400f), floorY - 0.5f, m(1910f), 20f, 0.5f, 20f, 0xFF6B7066.toInt(), 0xFF1F161D.toInt())
                addProp("ch2_lab", VoxelShape.HOUSE_SHELL, m(400f), floorY, m(1920f), 7.8f, 3.6f, 6.0f, 0f, 0xFF7B675E.toInt(), 0xFF33181E.toInt())
                addProp("ch2_cabinet", VoxelShape.DRAWERS, m(395f), floorY, m(1903f), 1.0f, 1.1f, 0.8f, 0f, 0xFF6A5C52.toInt(), 0xFF2B1C1E.toInt())
                addProp("ch2_table", VoxelShape.TABLE, m(400f), floorY + 0.3f, m(1922f), 1.6f, 0.8f, 0.9f, 0f, 0xFF5D3A2A.toInt(), 0xFF2A1417.toInt())
                addProp("ch2_key", VoxelShape.ITEM_ORB, m(395f), floorY + 1.25f, m(1903f), 0.28f, 0.28f, 0.28f, 0f, 0xFFF2C879.toInt(), 0xFFFF6E4E.toInt(), highlight = true, emissive = true)
                addProp("ch2_photo", VoxelShape.ITEM_ORB, m(400f), floorY + 1.2f, m(1922f), 0.32f, 0.32f, 0.32f, 0f, 0xFFFF6E6E.toInt(), 0xFFFF3838.toInt(), highlight = true, emissive = true)
                addLamp("ch2_lamp", m(400f), floorY, m(1884f))
                lights.add(WorldLight(m(400f), floorY + 2.4f, m(1920f), 10f, 1f, 0.14f, 0.08f, 2.8f, 3, true))
                addTreeRing(m(400f), m(1910f), floorY, 10f, 16f, 12)
                heightResolver = { _, _, _ -> floorY }
            }

            3 -> {
                floorY = 7.0f
                bounds = floatArrayOf(m(640f), m(720f), m(2104f), m(2212f))
                addBox("ch3_ground", m(680f), floorY - 0.5f, m(2158f), 20f, 0.5f, 22f, 0xFF686A60.toInt(), 0xFF1D171F.toInt())
                // Railway platform & rails
                addBox("ch3_rails", m(680f), floorY - 0.42f, m(2116f), 16f, 0.45f, 2.0f, 0xFF474952.toInt(), 0xFF1D1821.toInt())
                addProp("ch3_bench", VoxelShape.BENCH, m(684f), floorY, m(2132f), 1.6f, 0.8f, 0.65f, -1.57f, 0xFF7D5838.toInt(), 0xFF322120.toInt())
                addProp("ch3_garage", VoxelShape.HOUSE_SHELL, m(680f), floorY, m(2186f), 7.8f, 3.6f, 5.8f, 0f, 0xFF736D66.toInt(), 0xFF282026.toInt())
                addProp("ch3_workbench", VoxelShape.TABLE, m(680f), floorY + 0.3f, m(2188f), 1.8f, 0.85f, 0.8f, 0f, 0xFF6B472D.toInt(), 0xFF291A18.toInt())
                addProp("ch3_key", VoxelShape.ITEM_ORB, m(673f), floorY + 0.8f, m(2135f), 0.3f, 0.3f, 0.3f, 0f, 0xFFF2C879.toInt(), 0xFFFF6E4E.toInt(), highlight = true, emissive = true)
                addLamp("ch3_lamp", m(674f), floorY, m(2132f))
                lights.add(WorldLight(m(680f), floorY + 2.4f, m(2184f), 9f, 0.95f, 0.75f, 0.45f, 2.2f, 3))
                addTreeRing(m(680f), m(2158f), floorY, 10f, 16f, 12)
                heightResolver = { _, _, _ -> floorY }
            }

            4 -> {
                floorY = 7.0f
                bounds = floatArrayOf(m(640f), m(720f), m(1870f), m(1972f))
                addBox("ch4_ground", m(680f), floorY - 0.5f, m(1920f), 20f, 0.5f, 22f, 0xFF4E5254.toInt(), 0xFF19151E.toInt())
                addBox("ch4_highway", m(680f), floorY - 0.45f, m(1888f), 18f, 0.46f, 4.0f, 0xFF34373D.toInt(), 0xFF1A1720.toInt())
                addProp("ch4_gas_canopy", VoxelShape.TABLE, m(680f), floorY, m(1904f), 5.0f, 3.0f, 3.0f, 0f, 0xFF8C463B.toInt(), 0xFF33181C.toInt())
                addProp("ch4_motel", VoxelShape.HOUSE_SHELL, m(680f), floorY, m(1945f), 7.8f, 3.5f, 5.5f, 0f, 0xFFA28C72.toInt(), 0xFF332125.toInt())
                addProp("ch4_table", VoxelShape.TABLE, m(684.5f), floorY + 0.3f, m(1944f), 1.4f, 0.75f, 0.85f, 0f, 0xFF7B5032.toInt(), 0xFF2B1B1B.toInt())
                addProp("ch4_key", VoxelShape.ITEM_ORB, m(680f), floorY + 0.9f, m(1904f), 0.3f, 0.3f, 0.3f, 0f, 0xFFF2C879.toInt(), 0xFFFF6E4E.toInt(), highlight = true, emissive = true)
                addProp("ch4_book", VoxelShape.ITEM_ORB, m(684.5f), floorY + 1.15f, m(1944f), 0.28f, 0.28f, 0.28f, 0f, 0xFFF2C879.toInt(), 0xFFFF6E4E.toInt(), highlight = true, emissive = true)
                addLamp("ch4_lamp", m(674f), floorY, m(1904f))
                lights.add(WorldLight(m(680f), floorY + 2.2f, m(1944f), 9f, 1f, 0.68f, 0.36f, 2.2f, 3))
                addTreeRing(m(680f), m(1920f), floorY, 10f, 16f, 12, pine = true)
                heightResolver = { _, _, _ -> floorY }
            }

            5 -> {
                floorY = 7.0f
                val sx = P_START.first; val sz = P_START.second
                val cx = P_CROSSING.first; val cz = P_CROSSING.second
                bounds = floatArrayOf(min(sx, cx) - 18f, max(sx, cx) + 18f, min(sz, cz) - 18f, max(sx, cz) + 18f)

                addBox("ch5_ground", (bounds[0] + bounds[1]) * 0.5f, floorY - 0.5f, (bounds[2] + bounds[3]) * 0.5f, 44f, 0.5f, 46f, 0xFFC5AC7B.toInt(), 0xFF282024.toInt())
                addProp("ch5_stream", VoxelShape.WATER_PLANE, cx, floorY - 0.1f, cz, 36f, 0.1f, 5.2f, 0f, 0xFF47869E.toInt(), 0xFF141822.toInt())

                // Bridge deck
                val bridgeSolved = edits["bridge1"] == true || flags["bridgeSolved"] == true
                addProp(
                    "ch5_bridge", VoxelShape.BRIDGE_DECK,
                    crX(68f), floorY - 0.05f, cz,
                    3.6f, 0.35f, if (bridgeSolved) 6.5f else 2.0f, 0f,
                    0xFF7B5738.toInt(), 0xFF342222.toInt()
                )

                // Shovel, Cave rockface, Chest
                val caveX = 1169f * VS; val caveZ = 2148f * VS
                addBox("ch5_rockface", caveX + 2.2f, floorY, caveZ, 5.5f, 4.2f, 4.8f, 0xFF6B6A6E.toInt(), 0xFF261E24.toInt())
                if (edits["startCave"] != true && flags["chestDug"] != true) {
                    addBox("ch5_cave_block", caveX, floorY, caveZ, 2.2f, 2.0f, 2.2f, 0xFF7F684F.toInt(), 0xFF312222.toInt())
                }
                addProp("ch5_chest", VoxelShape.CHEST, (1172f + 1216f) * 0.5f * VS, floorY, caveZ, 1.1f, 0.8f, 0.8f, 0.4f, 0xFF6E4B2F.toInt(), 0xFF3A2020.toInt(), highlight = true)
                addProp("ch5_shovel", VoxelShape.ITEM_ORB, caveX - 2.2f, floorY + 0.5f, caveZ + 2.4f, 0.35f, 0.35f, 0.35f, 0f, 0xFFF2C879.toInt(), 0xFFFF6E4E.toInt(), highlight = true, emissive = true)

                // Rune Plate & 4 Runestones
                val plateX = crX(70.6f); val plateZ = crZ(95.7f)
                addProp("ch5_plate", VoxelShape.TABLE, plateX, floorY - 0.2f, plateZ, 1.4f, 0.6f, 1.4f, 0f, 0xFF768274.toInt(), 0xFF352328.toInt(), highlight = true)
                val runeCols = listOf(0xFFE05544.toInt(), 0xFF4C8BE0.toInt(), 0xFFE8C44C.toInt(), 0xFF54B868.toInt())
                val rCoords = listOf(60.6f to 91.2f, 62.8f to 89.6f, 65.6f to 91.6f, 66.9f to 89.9f)
                rCoords.forEachIndexed { idx, (rx, rz) ->
                    addProp("ch5_rune_$idx", VoxelShape.RUNESTONE, crX(rx), floorY, crZ(rz), 0.7f, 1.2f, 0.7f, idx * 0.7f, 0xFF6F7278.toInt(), runeCols[idx], mask = 2, emissive = true)
                }

                // Compass & Rabbit
                addProp("ch5_compass", VoxelShape.ITEM_ORB, sx - 2.4f, floorY + 0.3f, sz - 1.2f, 0.25f, 0.25f, 0.25f, 0f, 0xFFF2C879.toInt(), 0xFFF2C879.toInt(), highlight = true, emissive = true)
                if (flags["rabbitPet"] != true) {
                    addProp("ch5_rabbit", VoxelShape.RABBIT, sx + 1.6f, floorY, sz - 1.8f, 0.45f, 0.5f, 0.65f, -2.4f, 0xFFEBE4DC.toInt(), 0xFF28181E.toInt())
                }

                addTreeRing((bounds[0] + bounds[1]) * 0.5f, (bounds[2] + bounds[3]) * 0.5f, floorY, 16f, 24f, 20)
                heightResolver = { _, _, _ -> floorY }
            }

            6 -> {
                floorY = 7.5f
                val mx = P_MEADOW.first; val mz = P_MEADOW.second
                val hx = hoX(78f); val hz = hoZ(60f)
                bounds = floatArrayOf(min(mx, hx) - 18f, max(mx, hx) + 18f, min(mz, hz) - 18f, max(mz, hz) + 18f)

                addBox("ch6_ground", (bounds[0] + bounds[1]) * 0.5f, floorY - 0.5f, (bounds[2] + bounds[3]) * 0.5f, 52f, 0.5f, 50f, 0xFF627E48.toInt(), 0xFF1F181F.toInt())

                // White Deer on meadow
                if (flags["deerTouched"] != true) {
                    addProp("ch6_deer", VoxelShape.DEER, mdX(48f), floorY, mdZ(72.5f), 0.9f, 1.8f, 1.6f, 1.57f, 0xFFF4EFE6.toInt(), 0xFF331B22.toInt(), highlight = true, emissive = true)
                }

                // Forester's House on the Hill
                addProp("ch6_house", VoxelShape.HOUSE_SHELL, hx, floorY, hoZ(59.6f), 8.2f, 3.8f, 6.2f, 0f, 0xFF8C6342.toInt(), 0xFF2A1B1E.toInt())
                addProp("ch6_hearth", VoxelShape.FIREPLACE, hx, floorY, hoZ(56.78f), 1.4f, 2.2f, 1.0f, 0f, 0xFF6D5852.toInt(), 0xFF2D1B1E.toInt(), emissive = flags["hearthRepaired"] == true)
                addProp("ch6_sofa", VoxelShape.SOFA, hx, floorY, hoZ(60.7f), 1.8f, 0.85f, 0.85f, PI.toFloat(), 0xFF8F5A3C.toInt(), 0xFF341E22.toInt())
                addProp("ch6_table", VoxelShape.TABLE, hoX(81f), floorY, hoZ(58.7f), 1.4f, 0.72f, 0.9f, 0f, 0xFF7D5333.toInt(), 0xFF2E1E1E.toInt())
                addProp("ch6_drawers", VoxelShape.DRAWERS, hoX(74.3f), floorY, hoZ(59.5f), 0.9f, 1.0f, 1.2f, 1.57f, 0xFF754A2C.toInt(), 0xFF2B1A19.toInt())
                addProp("ch6_locket", VoxelShape.ITEM_ORB, hoX(77.9f), floorY + 1.8f, hoZ(57.25f), 0.3f, 0.3f, 0.3f, 0f, 0xFFF2C879.toInt(), 0xFFFF7A59.toInt(), highlight = true, emissive = true)
                addProp("ch6_bench", VoxelShape.BENCH, P_BENCH.first, floorY, P_BENCH.second, 1.6f, 0.8f, 0.65f, 1.57f, 0xFF7D5838.toInt(), 0xFF302020.toInt())
                addProp("ch6_workbench", VoxelShape.TABLE, hoX(72.9f), floorY, hoZ(57.8f), 1.3f, 0.8f, 0.7f, 1.57f, 0xFF6D4C32.toInt(), 0xFF291A18.toInt())
                addProp("ch6_key", VoxelShape.ITEM_ORB, m(624f), floorY + 1.0f, m(508f), 0.28f, 0.28f, 0.28f, 0f, 0xFFF2C879.toInt(), 0xFFFFD27D.toInt(), mask = 2, highlight = true, emissive = true)

                lights.add(WorldLight(hx, floorY + 1.5f, hoZ(57.3f), 8.5f, 1f, 0.58f, 0.28f, 2.4f, 1, true))
                lights.add(WorldLight(hx, floorY + 2.2f, hoZ(60f), 8.5f, 1f, 0.14f, 0.08f, 2.0f, 2, true))
                addTreeRing((bounds[0] + bounds[1]) * 0.5f, (bounds[2] + bounds[3]) * 0.5f, floorY, 18f, 28f, 22)
                heightResolver = { _, _, _ -> floorY }
            }

            7 -> {
                floorY = 7.5f
                val cfX = P_CAMPFIRE.first; val cfZ = P_CAMPFIRE.second
                val thX = P_THICKET.first; val thZ = P_THICKET.second
                val stX = hoX(74f); val stZ = hoZ(52f)
                bounds = floatArrayOf(min(thX, stX) - 16f, max(cfX, stX) + 16f, min(cfZ, thZ) - 16f, max(cfZ, stZ) + 16f)

                addBox("ch7_ground", (bounds[0] + bounds[1]) * 0.5f, floorY - 0.5f, (bounds[2] + bounds[3]) * 0.5f, 56f, 0.5f, 52f, 0xFF566E42.toInt(), 0xFF1E171D.toInt())
                // Stone Faces along route
                for (i in 0 until 6) {
                    val f = 0.15f + i * 0.13f
                    val fx = stX + (cfX - stX) * f + (if (i % 2 == 0) 3.2f else -3.2f)
                    val fz = stZ + (cfZ - stZ) * f
                    addProp("ch7_face_$i", VoxelShape.STONE_FACE, fx, floorY, fz, 1.0f, 2.1f, 1.0f, i * 1.1f, 0xFF7B7B7E.toInt(), 0xFF421C22.toInt(), mask = 2, emissive = true)
                }
                // Campfire & Backpack
                addProp("ch7_campfire", VoxelShape.FIREPLACE, cfX, floorY, cfZ, 1.1f, 0.6f, 1.1f, 0f, 0xFFFF8833.toInt(), 0xFF332628.toInt(), emissive = true)
                addProp("ch7_backpack", VoxelShape.CHEST, cfX + 1.7f, floorY, cfZ + 1.1f, 0.65f, 0.55f, 0.5f, -0.7f, 0xFF46698A.toInt(), 0xFF351C22.toInt(), highlight = true)
                addProp("ch7_log", VoxelShape.BENCH, cfX - 1.2f, floorY, cfZ + 0.6f, 1.6f, 0.45f, 0.55f, 0.4f, 0xFF6B472C.toInt(), 0xFF2E1E1D.toInt())
                lights.add(WorldLight(cfX, floorY + 1.0f, cfZ, 10f, 1f, 0.52f, 0.22f, 2.6f, 1, true))

                // Thicket figures & teddy bear
                addProp("ch7_teddy", VoxelShape.RABBIT, thX + 0.7f, floorY, thZ + 1.2f, 0.5f, 0.55f, 0.5f, 0.6f, 0xFFA87749.toInt(), 0xFF3D2224.toInt())
                addProp("ch7_reach_fig", VoxelShape.FIGURE, tkX(37.4f), floorY, tkZ(41.4f), 0.7f, 1.85f, 0.55f, 0.3f, 0xFF5D6673.toInt(), 0xFF281720.toInt(), highlight = true)
                addTreeRing((bounds[0] + bounds[1]) * 0.5f, (bounds[2] + bounds[3]) * 0.5f, floorY, 16f, 26f, 24, pine = true)
                heightResolver = { _, _, _ -> floorY }
            }

            8 -> {
                floorY = 7.5f
                val ux = P_UPSTREAM.first; val uz = P_UPSTREAM.second
                val clx = P_CLIFF.first; val clz = P_CLIFF.second
                bounds = floatArrayOf(min(ux, clx) - 18f, max(ux, clx) + 18f, min(uz, clz) - 18f, max(uz, clz) + 18f)

                addBox("ch8_ground", (bounds[0] + bounds[1]) * 0.5f, floorY - 0.5f, (bounds[2] + bounds[3]) * 0.5f, 44f, 0.5f, 44f, 0xFF5A6D4C.toInt(), 0xFF1D1820.toInt())
                addProp("ch8_stream", VoxelShape.WATER_PLANE, upaX(23.5f), floorY - 0.08f, upaZ(46.8f), 12f, 0.1f, 10f, 0f, 0xFF3F7E9C.toInt(), 0xFF10131C.toInt())
                addProp("ch8_wheelcap", VoxelShape.ITEM_ORB, upaX(22.6f), floorY + 0.25f, upaZ(46.3f), 0.45f, 0.45f, 0.45f, 0f, 0xFF9AA3AB.toInt(), 0xFF383E46.toInt())
                addProp("ch8_plate", VoxelShape.ITEM_ORB, upaX(22.5f), floorY + 0.3f, upaZ(46.9f), 0.35f, 0.35f, 0.35f, 0f, 0xFFF2C879.toInt(), 0xFFFF5E4E.toInt(), highlight = true, emissive = true)
                addProp("ch8_shard", VoxelShape.ITEM_ORB, upaX(25.8f), floorY + 0.3f, upaZ(47.7f), 0.35f, 0.35f, 0.35f, 0f, 0xFFE0503F.toInt(), 0xFFFF4030.toInt(), highlight = true, emissive = true)
                addBox("ch8_cliff_rock", clx, floorY, clz - 2.5f, 8f, 3.5f, 3.0f, 0xFF69676D.toInt(), 0xFF281F26.toInt())
                addTreeRing((bounds[0] + bounds[1]) * 0.5f, (bounds[2] + bounds[3]) * 0.5f, floorY, 15f, 22f, 18, pine = true)
                heightResolver = { _, _, _ -> floorY }
            }

            9 -> {
                floorY = 8.0f
                bounds = floatArrayOf(noX(66f), noX(84f), noZ(15f), noZ(46f))
                // Gorge cliffs + Stone Bridge + Tunnel Walls
                addBox("ch9_south_ledge", noX(75f), floorY - 0.5f, noZ(40f), 14f, 0.5f, 12f, 0xFF6A666D.toInt(), 0xFF282028.toInt())
                addProp("ch9_bridge", VoxelShape.BRIDGE_DECK, noX(75f), floorY - 0.1f, noZ(30f), 3.4f, 0.4f, 11f, 0f, 0xFF7D7872.toInt(), 0xFF30242A.toInt())
                // Tunnel Enclosure
                addBox("ch9_tunnel_floor", noX(75.5f), floorY - 0.5f, noZ(20f), 4.5f, 0.5f, 10f, 0xFF5D5B62.toInt(), 0xFF221A20.toInt())
                addBox("ch9_tunnel_w", noX(73.2f), floorY, noZ(20f), 0.5f, 3.4f, 10f, 0xFF5A565D.toInt(), 0xFF241B22.toInt(), solid = true)
                addBox("ch9_tunnel_e", noX(77.8f), floorY, noZ(20f), 0.5f, 3.4f, 10f, 0xFF5A565D.toInt(), 0xFF241B22.toInt(), solid = true)
                if (edits["grate"] != true) {
                    addBox("ch9_grate", noX(75.5f), floorY, m(188 + 536), 3.8f, 3.0f, 0.35f, 0xFF6B3E33.toInt(), 0xFF3E1C1A.toInt(), solid = true)
                }
                if (edits["tunnelWall"] != true) {
                    addBox("ch9_wall", noX(75.5f), floorY, m(136 + 536), 3.8f, 3.2f, 0.6f, 0xFF6C686E.toInt(), 0xFF35242A.toInt(), solid = true)
                }
                addProp("ch9_lock", VoxelShape.ITEM_ORB, noX(76.45f), floorY + 1.0f, m(188 + 536) + 0.55f, 0.35f, 0.35f, 0.35f, 0f, 0xFFF2C879.toInt(), 0xFFFF6E4E.toInt(), highlight = true, emissive = true)
                addLamp("ch9_l1", noX(73.2f), floorY, noZ(40f))
                addLamp("ch9_l2", noX(72.3f), floorY, noZ(20.2f))
                heightResolver = { _, _, _ -> floorY }
            }

            else -> { // Chapter 10
                floorY = 8.0f
                val plx = P_POOL.first; val plz = P_POOL.second
                bounds = floatArrayOf(noX(58f), noX(95f), noZ(2f), noZ(19f))
                addBox("ch10_grotto_floor", noX(76f), floorY - 0.5f, noZ(9f), 32f, 0.5f, 16f, 0xFF565965.toInt(), 0xFF221A23.toInt())
                addProp("ch10_pool", VoxelShape.WATER_PLANE, plx, floorY - 0.06f, plz, 5.2f, 0.1f, 5.2f, 0f, 0xFF6BA6C4.toInt(), 0xFF1F273B.toInt(), emissive = true)
                addProp("ch10_car_wreck", VoxelShape.CAR, plx, floorY + 0.35f, plz, 3.6f, 1.3f, 1.7f, 0.5f, 0xFF2A3B4C.toInt(), 0xFF2E1418.toInt(), mask = 2)
                addProp("ch10_car_key", VoxelShape.ITEM_ORB, plx, floorY + 0.35f, plz + 3.6f, 0.3f, 0.3f, 0.3f, 0f, 0xFFF2C879.toInt(), 0xFFFFD27D.toInt(), visible = flags["flashback"] == true && flags["car_key_taken"] != true, highlight = true, emissive = true)
                // West (Truth / Ward 7) and East (Illusion / Shadow) Portals
                addBox("ch10_west_portal", noX(61f), floorY, noZ(7.75f), 2.4f, 3.6f, 1.2f, 0xFF9AC8FF.toInt(), 0xFF6BA0EE.toInt(), emissive = true)
                addBox("ch10_east_portal", noX(91f), floorY, noZ(7.8f), 2.4f, 3.6f, 1.2f, 0xFFF2C879.toInt(), 0xFFB83C34.toInt(), emissive = true)
                lights.add(WorldLight(noX(92.6f), floorY + 1.5f, noZ(7.8f), 14f, 1f, 0.94f, 0.85f, 3.0f, 3))
                lights.add(WorldLight(noX(61f), floorY + 1.5f, noZ(7.75f), 12f, 0.55f, 0.78f, 1f, 2.8f, 3))
                heightResolver = { _, _, _ -> floorY }
            }
        }

        // Add chapter NPCs as visible 3D voxel figures
        val chDef = ChaptersCatalog2.get(chapter)
        for (npc in chDef.npcs) {
            val mask = when (npc.world) {
                WorldFilter.DREAM -> 1
                WorldFilter.NIGHTMARE -> 2
                WorldFilter.ANY -> 3
            }
            val ny = npc.y ?: floorY
            val colD = when (npc.type) {
                "real" -> 0xFF5D89B3.toInt()
                "phantom_denial" -> 0xFFD9A65B.toInt()
                else -> 0xFF3E3545.toInt()
            }
            val colN = if (npc.type == "phantom_projection") 0xFFE0503F.toInt() else 0xFF6B5368.toInt()
            addProp(
                npc.id, VoxelShape.FIGURE,
                npc.x, ny, npc.z,
                0.7f, 1.85f, 0.55f, npc.yaw,
                colD, colN, mask = mask, highlight = true
            )
        }

        return ChapterSceneData(
            chapter = chapter,
            groundY = floorY,
            boundsX0 = bounds[0],
            boundsX1 = bounds[1],
            boundsZ0 = bounds[2],
            boundsZ1 = bounds[3],
            props = props,
            colliders = colliders,
            lights = lights,
            heightResolver = heightResolver
        )
    }
}
