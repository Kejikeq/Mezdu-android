package com.example.ui

import com.example.data.ChaptersCatalog2
import com.example.data.InteractIcon
import com.example.data.Interactable
import com.example.data.ItemsCatalog
import com.example.data.MemoryVector
import com.example.data.Vec3
import com.example.data.WorldCoords.P_BENCH
import com.example.data.WorldCoords.P_CAMPFIRE
import com.example.data.WorldCoords.P_CLIFF
import com.example.data.WorldCoords.P_POOL
import com.example.data.WorldCoords.P_START
import com.example.data.WorldCoords.P_THICKET
import com.example.data.WorldCoords.VS
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
import com.example.data.WorldFilter

object ChapterInteractables {

    fun buildAll(vm: GameViewModel): List<Interactable> {
        val list = mutableListOf<Interactable>()

        fun addExit(ch: Int, pos: Vec3, labelOpen: String, labelLocked: String) {
            list.add(
                Interactable(
                    id = "exit_ch$ch",
                    pos = pos,
                    radius = 3.0f,
                    world = WorldFilter.ANY,
                    labelProvider = { if (vm.isChapterExitReady(ch)) labelOpen else labelLocked },
                    icon = InteractIcon.DOOR,
                    condition = { vm.currentChapter == ch },
                    onInteract = {
                        if (!vm.isMandatoryWorldDone(ch)) {
                            val cd = ChaptersCatalog2.get(ch)
                            vm.say(cd.mandatoryGateHint, 4.2f)
                        } else if (!vm.hasConclusion(ch)) {
                            vm.say("Прежде чем покинуть это место, нужно связать улики и показания на Доске выводов в дневнике.", 4.0f)
                            vm.waitSec(0.35f)
                            vm.openMemoryBoard()
                        } else {
                            vm.advanceToChapter(ch + 1)
                        }
                    }
                )
            )
        }

        // --- NPCs for Chapters 1..9 ---
        for (ch in 1..9) {
            val cd = ChaptersCatalog2.get(ch)
            for (npc in cd.npcs) {
                val ny = npc.y ?: 7.0f
                list.add(
                    Interactable(
                        id = "talk_${npc.id}",
                        pos = Vec3(npc.x, ny + 1.0f, npc.z),
                        radius = 2.6f,
                        world = npc.world,
                        labelProvider = { "Поговорить: ${npc.name}" },
                        icon = InteractIcon.HAND,
                        condition = { vm.currentChapter == ch },
                        onInteract = {
                            if (npc.dialogTree != null) {
                                vm.openNpcDialog(npc)
                            } else {
                                vm.setInputLock(true)
                                for ((line, speaker) in npc.lines) {
                                    vm.voice(line, 4.0f, speaker)
                                    vm.waitSec(3.5f)
                                }
                                val prof = vm.memoryProfile()
                                if (prof.total > 0) {
                                    when {
                                        npc.type == "real" && prof.dominant == MemoryVector.DENIAL -> {
                                            vm.voice("«Ты улыбаешься так, будто ничего не случилось… Но от правды не спрятаться во сне, Элиас».", 3.6f, npc.name)
                                            vm.waitSec(3.2f)
                                        }
                                        npc.type == "real" && prof.dominant == MemoryVector.PROJECTION -> {
                                            vm.voice("«Зачем ты ищешь заговор там, где была наша общая беда? Михаил не враг тебе».", 3.6f, npc.name)
                                            vm.waitSec(3.2f)
                                        }
                                        npc.type == "phantom_denial" && prof.dominant == MemoryVector.DENIAL -> {
                                            vm.voice("«Вот видишь, ты и сам уже понимаешь, как здесь спокойно. Продолжай держаться за этот светлый день».", 3.6f, npc.name)
                                            vm.waitSec(3.2f)
                                        }
                                        npc.type == "phantom_projection" && prof.dominant == MemoryVector.PROJECTION -> {
                                            vm.voice("«Твои прежние догадки подтверждаются! Ты правильно делаешь, что не веришь его оправданиям».", 3.6f, npc.name)
                                            vm.waitSec(3.2f)
                                        }
                                    }
                                }
                                npc.testimony?.let { vm.addTestimony(it.id) }
                                vm.setInputLock(false)
                                if (vm.hasChapterClues(ch) && !vm.hasConclusion(ch)) {
                                    vm.setObjective("Откройте «Выводы» сверху, чтобы связать улику и показание")
                                }
                            }
                        }
                    )
                )
            }
        }

        // ================= CHAPTER 1 =================
        val f1 = 7.0f; val f2 = 11.0f; val baseY = 3.625f
        list.add(Interactable(
            id = "ch1_front_door", pos = Vec3(m(408f), f1 + 1.0f, m(2194f)), radius = 2.5f,
            labelProvider = {
                when {
                    vm.edits["ch1Door"] == true -> "Парадная дверь открыта (выходите во двор и сквер)"
                    !vm.flags["ch1AnsweringHeard"].orFalse() || !vm.hasItem("student_pass") ->
                        "Парадная дверь (прослушайте автоответчик и возьмите пропуск в кабинете)"
                    !vm.hasItem("apartment_key") -> "Парадная дверь заперта (найдите ключ за зеркалом в прихожей)"
                    else -> "Отпереть парадную дверь латунным ключом"
                }
            },
            icon = InteractIcon.DOOR,
            condition = { vm.currentChapter == 1 && vm.edits["ch1Door"] != true },
            onInteract = {
                if (!vm.flags["ch1AnsweringHeard"].orFalse() || !vm.hasItem("student_pass")) {
                    vm.audio.sfx("click")
                    vm.say("Нельзя уходить без документов. Нужно прослушать автоответчик и забрать пропуск со стола в кабинете на 1-м этаже.", 3.8f)
                    vm.setObjective("Осмотреть письменный стол в кабинете на 1-м этаже и забрать пропуск")
                } else if (!vm.hasItem("apartment_key")) {
                    vm.audio.sfx("click")
                    vm.say("Замок заперт. Запасной ключ лежит за зеркалом в прихожей (вглядитесь кнопкой Глаз)…", 4.0f)
                    vm.setObjective("Осмотреть зеркало в прихожей в «Кошмаре» и достать ключ")
                } else {
                    vm.setFlag("ch1BoltUnlocked", true)
                    vm.audio.sfx("break")
                    vm.setEdit("ch1Door", true)
                    vm.stopPeer()
                    vm.say("Латунный ключ провернулся! Парадная дверь распахнута — на улице пахнет осенними клёнами.", 4.2f)
                    vm.setObjective("Выйти на улицу к Университету, поговорить с людьми и сделать вывод в «Выводах»")
                }
            }
        ))

        list.add(Interactable(
            id = "ch1_study_desk", pos = Vec3(m(364f), f1 + 0.8f, m(2205f)), radius = 2.6f,
            labelProvider = {
                if (!vm.flags["ch1AnsweringHeard"].orFalse())
                    "Стол в кабинете: прослушать автоответчик и забрать пропуск"
                else "Стол Элиаса: прослушать автоответчик"
            },
            icon = InteractIcon.SOUND,
            condition = { vm.currentChapter == 1 },
            onInteract = {
                vm.audio.sfx("click")
                vm.setFlag("ch1AnsweringHeard", true)
                vm.addClue("c1_answering")
                vm.voice("«Элиас, это Михаил! Выезжаем сегодня в ночь, иначе шторм размоет верхний карниз! Хватит пить эти таблетки!»", 4.6f, "Автоответчик")
                vm.waitSec(4.2f)
                vm.audio.sfx("beep", count = 2)
                vm.voice("«Бип... бип... Пульс нестабилен. Введите десять кубиков раствора...»", 3.6f, "Голос сквозь помехи")
                vm.waitSec(3.4f)
                vm.say(vm.adapt(
                    defaultText = "Сквозь голос Михаила пробивается мерный писк больничного кардиомонитора.",
                    truthText = "Этот писк на фоне записи… Он звучит совсем как палата интенсивной терапии.",
                    denialText = "Просто радиопомехи на старой линии. Обычное осеннее утро.",
                    projectionText = "Почему Михаил так торопил меня в ночь, зная о шторме?"
                ), 4.0f)
                if (!vm.hasItem("student_pass")) {
                    vm.pickupItem("student_pass", "письменный стол в кабинете")
                }
                if (vm.edits["ch1Door"] != true) {
                    vm.setObjective("Найти ключ от входной двери за зеркалом в прихожей и выйти наружу")
                }
            }
        ))

        list.add(Interactable(
            id = "ch1_mirror", pos = Vec3(m(393.4f), f1 + 1.2f, m(2201f)), radius = 2.5f,
            labelProvider = {
                if (vm.isNight()) "Зеркало в прихожей: вглядеться сквозь ледяную пелену"
                else "Зеркало в прихожей: осмотреть отражение и раму"
            },
            icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 1 },
            onInteract = {
                if (!vm.isNight()) {
                    vm.audio.sfx("paper")
                    vm.say("В раме зеркала секретный пенал для ключа, но замок словно заклинен сном. Нажмите «Глаз», чтобы вглядеться глубже…", 4.4f)
                } else {
                    vm.audio.sfx("water_in")
                    vm.addClue("c1_mirror")
                    vm.say("На стекле проступает больничная койка и браслет пациента «7319-Э». За рамой блестит латунный ключ!", 4.4f)
                    if (!vm.hasItem("apartment_key")) {
                        vm.waitSec(1.1f)
                        if (vm.pickupItem("apartment_key", "тайник за зеркалом в прихожей")) {
                            vm.say("Ключ от входной двери у меня! Можно отпереть парадную дверь.", 3.8f)
                            if (vm.edits["ch1Door"] != true) vm.setObjective("Отпереть парадную дверь найденным ключом")
                        }
                    }
                }
            }
        ))

        list.add(Interactable(
            id = "ch1_calendar", pos = Vec3(m(436f), f2 + 1.3f, m(2195.2f)), radius = 2.5f,
            labelProvider = { if (vm.isNight()) "Календарь на стене (2-й этаж): водяные знаки" else "Календарь на стене (2-й этаж): 12 октября" },
            icon = InteractIcon.READ,
            condition = { vm.currentChapter == 1 },
            onInteract = {
                vm.audio.sfx("paper")
                vm.addClue("c1_calendar")
                if (!vm.isNight()) {
                    vm.readPages("Календарь в спальне", listOf(
                        "«ПОНЕДЕЛЬНИК, 12 ОКТЯБРЯ»",
                        "Пометка карандашом: Собрать линзы, забрать у Михаила карты перевала. Выезд назначен на пятницу."
                    ), false)
                    vm.say("Уголки страниц мокрые, словно их вытащили со дна реки.", 3.6f)
                } else {
                    vm.readPages("Штамп приемного покоя", listOf(
                        "«ОТДЕЛЕНИЕ РЕАНИМАЦИИ И ИНТЕНСИВНОЙ ТЕРАПИИ № 7»",
                        "Дата поступления: 18 октября. Травматический шок, аспирация речной водой.",
                        "Пациент: Элиас В. Состояние: кома III степени."
                    ), true)
                    vm.say("Дни перечеркнуты красным врачебным маркером… Неужели авария уже случилась?!", 4.0f)
                }
            }
        ))

        list.add(Interactable(
            id = "ch1_dresser", pos = Vec3(m(427.2f), f2 + 0.9f, m(2216f)), radius = 2.4f,
            labelProvider = { "Комод в спальне (2-й этаж): заказ-наряд автосервиса" },
            icon = InteractIcon.READ,
            condition = { vm.currentChapter == 1 && !vm.hasItem("brake_receipt") },
            onInteract = {
                if (vm.pickupItem("brake_receipt", "комод в спальне (2-й этаж)")) {
                    vm.addClue("c1_brake_receipt")
                    vm.readPages("Акт осмотра тормозов", listOf(
                        "«ЗАКАЗ-НАРЯД № 7319 · АВТОСЕРВИС СЕВЕРНЫЙ ВЫЕЗД»",
                        "Диагностика: Критический износ тормозного контура заднего моста.",
                        "Особая отметка: Клиент от ремонта отказался под расписку: „Мы спешим до грозы“..."
                    ), false)
                }
            }
        ))

        list.add(Interactable(
            id = "ch1_nightstand", pos = Vec3(m(481.6f), f2 + 0.9f, m(2202f)), radius = 2.3f,
            labelProvider = { "Тумбочка у кровати (2-й этаж): пузырёк с седативным" },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 1 && !vm.hasItem("sedative_bottle") },
            onInteract = {
                if (vm.pickupItem("sedative_bottle", "прикроватная тумбочка")) {
                    vm.addClue("c1_sedative")
                    vm.say("Пузырёк успокоительного… Я выпил двойную дозу перед выездом.", 3.8f)
                }
            }
        ))

        // Optional Ch 1 clues across house, basement, yard & square
        list.add(Interactable(
            id = "ch1_cup", pos = Vec3(m(446f), f1 + 0.8f, m(2268f)), radius = 2.2f,
            labelProvider = { "Обеденный стол: осмотреть чашку с чаем" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_coffee_cup") },
            onInteract = {
                vm.inspectModel("item_cassette", "кухонный стол", "Холодная фарфоровая чашка", "На дне чашки застыл горький осадок седативного раствора.")
                vm.addClue("c1_coffee_cup")
            }
        ))
        list.add(Interactable(
            id = "ch1_clock", pos = Vec3(m(418f), f1 + 1.0f, m(2197f)), radius = 2.3f,
            labelProvider = { "Напольные часы: застыли на 01:17" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_clock") },
            onInteract = {
                vm.audio.sfx("tick")
                vm.addClue("c1_clock")
                vm.say("Стрелки дедовых часов замерли на 01:17 ночи — в минуту, когда универсал сорвался с карниза.", 4.2f)
            }
        ))
        list.add(Interactable(
            id = "ch1_fridge", pos = Vec3(m(480.8f), f1 + 1.0f, m(2254f)), radius = 2.3f,
            labelProvider = { "Холодильник: записка Михаила под магнитом" }, icon = InteractIcon.READ,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_fridge_note") },
            onInteract = {
                vm.addClue("c1_fridge_note")
                vm.readPages("Записка на холодильнике", listOf(
                    "«Элиас! Прошу тебя: не бери синие флаконы из аптеки Штерна и выспись перед дорогой.»",
                    "«Если начнётся шторм — перенесём выезд на субботу. Жизнь дороже диссертации. — М.»"
                ), false)
            }
        ))
        list.add(Interactable(
            id = "ch1_basement", pos = Vec3(m(372f), baseY + 0.9f, m(2208.5f)), radius = 2.5f,
            labelProvider = { "Подвал: домашняя фотолаборатория" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_darkroom_basement") },
            onInteract = {
                vm.addClue("c1_darkroom_basement")
                vm.audio.sfx("water_in")
                vm.say("Под рубиновым светом сохнут негативы Чёртова каньона и машины, зависшей над пропастью…", 4.5f)
            }
        ))
        list.add(Interactable(
            id = "ch1_phone", pos = Vec3(m(422f), f1 + 1.1f, m(2178f)), radius = 2.3f,
            labelProvider = { "Телефонная будка: поднять свисающую трубку" }, icon = InteractIcon.SOUND,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_phone_record") },
            onInteract = {
                vm.addClue("c1_phone_record")
                vm.voice("«„Алло, МЧС?! Это Михаил... Мой напарник гонит машину в ночной шторм, а у нас текут тормоза!..“»", 4.8f, "Запись звонка")
            }
        ))
        list.add(Interactable(
            id = "ch1_scarf", pos = Vec3(m(406f), f1 + 0.7f, m(2144f)), radius = 2.3f,
            labelProvider = { "Скамья в сквере: поднять шарф Лии" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 1 && !vm.hasItem("leah_scarf") },
            onInteract = {
                if (vm.pickupItem("leah_scarf", "скамья в сквере")) {
                    vm.addClue("c1_scarf")
                    vm.voice("«Не уезжайте в эту бурю… у меня дурное предчувствие…»", 4.0f, "Голос Лии")
                }
            }
        ))
        list.add(Interactable(
            id = "ch1_bulletin", pos = Vec3(m(406f), f1 + 1.1f, m(2098f)), radius = 2.3f,
            labelProvider = { if (vm.isNight()) "Стенд: ориентировка МЧС" else "Стенд Университета: объявление" },
            icon = InteractIcon.READ,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_bulletin") },
            onInteract = {
                vm.addClue("c1_bulletin")
                vm.readPages("Сводка МЧС", listOf(
                    "«ОРИЕНТИРОВКА ПОИСКОВО-СПАСАТЕЛЬНОЙ СЛУЖБЫ»",
                    "Синий универсал № 7319 пробил ограждение и затонул в реке. Водитель доставлен в реанимацию в коме."
                ), vm.isNight())
            }
        ))
        list.add(Interactable(
            id = "ch1_apothecary_ledger", pos = Vec3(m(240f), f1 + 0.9f, m(2075f)), radius = 2.8f,
            labelProvider = { "Аптека Штерна: журнал учёта" }, icon = InteractIcon.READ,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_apothecary_ledger") },
            onInteract = {
                vm.addClue("c1_apothecary_ledger")
                vm.readPages("Журнал аптеки Штерна", listOf(
                    "«Препарат Сомнол-Форте (концентрат). Управление транспортом ЗАПРЕЩЕНО. Подпись: Элиас В.»"
                ), false)
            }
        ))
        list.add(Interactable(
            id = "ch1_wagner_map", pos = Vec3(m(554f), f1 + 0.9f, m(2226f)), radius = 2.8f,
            labelProvider = { "Особняк Вагнера: карта каньона" }, icon = InteractIcon.READ,
            condition = { vm.currentChapter == 1 && !vm.hasClue("c1_wagner_map") },
            onInteract = {
                vm.addClue("c1_wagner_map")
                vm.readPages("Резолюция профессора Вагнера", listOf(
                    "«В связи со штормовым предупреждением ВЫЕЗД ЗАПРЕЩЁН. Элиас В. самовольно забрал ключи универсала.»"
                ), false)
            }
        ))

        addExit(
            1, Vec3(m(400f), f1 + 1.0f, m(2096f)),
            "Арка Университета: войти в Архив карт (Глава 2 →)",
            "Арка Университета (предъявите пропуск и зафиксируйте вывод в «Выводах»)"
        )

        // ================= CHAPTER 2 =================
        list.add(Interactable(
            id = "ch2_cabinet", pos = Vec3(m(395f), f1 + 1.0f, m(1903f)), radius = 2.6f,
            labelProvider = { "Картотека архива: забрать ключ от проявочной" }, icon = InteractIcon.KEY,
            condition = { vm.currentChapter == 2 && !vm.hasItem("darkroom_key") },
            onInteract = {
                if (vm.pickupItem("darkroom_key", "картотека архива карт")) {
                    vm.addClue("c2_darkroom_key")
                    vm.say("В журнале стоит моя подпись: «Верхний карниз у водопада». Ключ от фотолаборатории у меня.", 4.2f)
                    vm.setObjective("Отопереть дверь фотолаборатории и проявить снимок в красном свете")
                }
            }
        ))
        list.add(Interactable(
            id = "ch2_door", pos = Vec3(m(401f), f1 + 1.0f, m(1896f)), radius = 2.6f,
            labelProvider = { if (vm.hasItem("darkroom_key")) "Отпереть фотолабораторию ключом" else "Запертая дверь фотолаборатории (нужен ключ)" },
            icon = InteractIcon.DOOR,
            condition = { vm.currentChapter == 2 && vm.edits["ch2Door"] != true },
            onInteract = {
                if (!vm.hasItem("darkroom_key")) {
                    vm.audio.sfx("click")
                    vm.say("Дверь заперта. Ключ в картотеке слева от входа.", 3.5f)
                } else {
                    vm.audio.sfx("door")
                    vm.setEdit("ch2Door", true)
                    vm.say("Дверь открылась. Внутри горит багровый фонарь.", 3.5f)
                    vm.setObjective("Проявить снимок на центральном столе фотолаборатории")
                }
            }
        ))
        list.add(Interactable(
            id = "ch2_tray", pos = Vec3(m(400f), f1 + 1.0f, m(1922f)), radius = 2.8f,
            labelProvider = { "Ванночка с проявителем: проявить снимок" }, icon = InteractIcon.PHOTO,
            condition = { vm.currentChapter == 2 && !vm.hasItem("wet_photo") },
            onInteract = {
                vm.audio.sfx("splash")
                if (vm.pickupItem("wet_photo", "красный свет проявочной")) {
                    vm.addClue("c2_wet_photo")
                    vm.say("Снимок проявлен: силуэт автомобиля над водопадом и цифры «7319». Зафиксируйте вывод Вторника.", 4.2f)
                    vm.setObjective("Сделать вывод Вторника в «Выводах» и пройти к северному выходу")
                }
            }
        ))
        addExit(
            2, Vec3(m(400f), f1 + 1.0f, m(1944f)),
            "Выход из корпуса: отправиться к перрону и мастерской (Глава 3 →)",
            "Северный выход корпуса (проявите снимок и зафиксируйте вывод Вторника)"
        )

        // ================= CHAPTER 3 =================
        list.add(Interactable(
            id = "ch3_keybox", pos = Vec3(m(673f), f1 + 0.8f, m(2135f)), radius = 2.6f,
            labelProvider = { "Железный ящик у перрона: достать ключ от гаража" }, icon = InteractIcon.KEY,
            condition = { vm.currentChapter == 3 && !vm.hasItem("garage_key") },
            onInteract = {
                if (vm.pickupItem("garage_key", "тайник у перрона")) {
                    vm.addClue("c3_garage_key")
                    vm.say("Тяжёлый ключ от мастерской Михаила с биркой «7319».", 3.8f)
                    vm.setObjective("Открыть дверь гаража-мастерской Михаила к югу от перрона")
                }
            }
        ))
        list.add(Interactable(
            id = "ch3_ticket", pos = Vec3(m(684f), f1 + 0.8f, m(2132f)), radius = 2.4f,
            labelProvider = { "Скамья перрона: взять ж/д билет (опц.)" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 3 && !vm.hasItem("train_ticket") },
            onInteract = {
                if (vm.pickupItem("train_ticket", "скамья на перроне")) {
                    vm.addClue("c3_train_ticket")
                }
            }
        ))
        list.add(Interactable(
            id = "ch3_door", pos = Vec3(m(681f), f1 + 1.0f, m(2184f)), radius = 2.6f,
            labelProvider = { if (vm.hasItem("garage_key")) "Отпереть ворота мастерской" else "Запертая мастерская (ключ у перрона)" },
            icon = InteractIcon.DOOR,
            condition = { vm.currentChapter == 3 && vm.edits["ch3Door"] != true },
            onInteract = {
                if (!vm.hasItem("garage_key")) {
                    vm.audio.sfx("click")
                    vm.say("Ворота мастерской заперты. Ключ спрятан у колонны старого перрона.", 3.8f)
                } else {
                    vm.audio.sfx("door")
                    vm.setEdit("ch3Door", true)
                    vm.say("Замок поддался. В гараже пусто — машины на месте нет.", 3.8f)
                    vm.setObjective("Осмотреть верстак внутри мастерской Михаила")
                }
            }
        ))
        list.add(Interactable(
            id = "ch3_workbench", pos = Vec3(m(680f), f1 + 1.0f, m(2188f)), radius = 2.8f,
            labelProvider = { "Верстак в гараже: осмотреть аптечку и записку" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 3 && !vm.flags["ch3GarageInspected"].orFalse() },
            onInteract = {
                vm.setFlag("ch3GarageInspected", true)
                vm.addClue("c3_oil_stain")
                vm.readPages("Записка от Михаила (среда)", listOf(
                    "«Элиас, меня бьёт озноб, температура под тридцать девять.»",
                    "«Я подтянул трос тормоза как смог. Ключи оставляю тебе — веди сам, только, прошу, не гони ночью по мокрому серпантину.»"
                ), vm.isNight())
                vm.say("Начиная со среды за рулём нашего универсала сидел я.", 4.0f)
                vm.setObjective("Сделать вывод Среды в «Выводах» и выйти к шоссе")
            }
        ))
        addExit(
            3, Vec3(m(680f), f1 + 1.0f, m(2204f)),
            "Выезд из кооператива: выехать на ночное шоссе к мотелю (Глава 4 →)",
            "Выезд на шоссе (осмотрите верстак и зафиксируйте вывод Среды)"
        )

        // ================= CHAPTER 4 =================
        list.add(Interactable(
            id = "ch4_fusebox", pos = Vec3(m(680f), f1 + 1.0f, m(1904f)), radius = 2.6f,
            labelProvider = { "Щиток бензоколонки: забрать ключ от Номера 4" }, icon = InteractIcon.KEY,
            condition = { vm.currentChapter == 4 && !vm.hasItem("motel_key") },
            onInteract = {
                vm.audio.sfx("click")
                if (vm.pickupItem("motel_key", "колонка АЗС")) {
                    vm.addClue("c4_motel_key")
                    vm.say("Латунный брелок «Мотель Поворот · Номер 4». На чеке — полный бак в четверг перед полуночью.", 4.2f)
                    vm.setObjective("Открыть дверь Номера 4 мотеля к югу от заправки")
                }
            }
        ))
        list.add(Interactable(
            id = "ch4_door", pos = Vec3(m(681f), f1 + 1.0f, m(1936f)), radius = 2.6f,
            labelProvider = { if (vm.hasItem("motel_key")) "Отпереть дверь Номера 4" else "Дверь Номера 4 (ключ у АЗС)" },
            icon = InteractIcon.DOOR,
            condition = { vm.currentChapter == 4 && vm.edits["ch4Door"] != true },
            onInteract = {
                if (!vm.hasItem("motel_key")) {
                    vm.audio.sfx("click")
                    vm.say("Четвёртый номер заперт. Ключ висит у щитка бензоколонки.", 3.6f)
                } else {
                    vm.audio.sfx("door")
                    vm.setEdit("ch4Door", true)
                    vm.say("Постель внутри не разобрана — будто мы уехали среди ночи.", 3.8f)
                    vm.setObjective("Изучить книгу постояльцев на столе внутри Номера 4")
                }
            }
        ))
        list.add(Interactable(
            id = "ch4_guestbook", pos = Vec3(m(684.5f), f1 + 1.0f, m(1944f)), radius = 2.8f,
            labelProvider = { "Стол в Номере 4: изучить книгу постояльцев" }, icon = InteractIcon.READ,
            condition = { vm.currentChapter == 4 && !vm.hasItem("guestbook_page") },
            onInteract = {
                if (vm.pickupItem("guestbook_page", "стол в Номере 4")) {
                    vm.addClue("c4_guestbook")
                    vm.say("Запись четверга, 23:40: «Синий универсал 7319. Уехали в ущелье в самый ливень».", 4.2f)
                    vm.setObjective("Зафиксировать вывод Четверга в «Выводах» и спуститься в долину")
                }
            }
        ))
        addExit(
            4, Vec3(m(680f), f1 + 1.0f, m(1964f)),
            "Шлагбаум долины: спуститься к песчаному берегу ручья (Глава 5 →)",
            "Спуск в долину (изучите книгу в Номере 4 и зафиксируйте вывод Четверга)"
        )

        // ================= CHAPTER 5 =================
        val caveX = 1169f * VS; val caveZ = 2148f * VS
        list.add(Interactable(
            id = "ch5_compass", pos = Vec3(P_START.first - 2.4f, f1 + 0.5f, P_START.second - 1.2f), radius = 2.4f,
            labelProvider = { "Кромка воды: поднять разбитый компас (опц.)" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 5 && !vm.hasItem("cracked_compass") },
            onInteract = {
                if (vm.pickupItem("cracked_compass", "прибрежная галька")) vm.addClue("c5_cracked_compass")
            }
        ))
        list.add(Interactable(
            id = "ch5_rabbit", pos = Vec3(P_START.first + 1.6f, f1 + 0.5f, P_START.second - 1.8f), radius = 2.2f,
            world = WorldFilter.DREAM, labelProvider = { "Погладить белого кролика" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 5 && !vm.flags["rabbitPet"].orFalse() },
            onInteract = {
                vm.setFlag("rabbitPet", true)
                vm.audio.sfx("glitch"); vm.vibrate(40L)
                vm.duality.toNight(vm.playerPos, 0.5f, speed = 100f, quiet = true)
                vm.waitSec(0.55f)
                vm.duality.toDream(vm.playerPos, speed = 100f, quiet = true)
                vm.say("На долю секунды он стал тенью…", 3.5f)
                vm.refreshSceneProps()
            }
        ))
        list.add(Interactable(
            id = "ch5_shovel", pos = Vec3(caveX - 2.2f, f1 + 0.6f, caveZ + 2.4f), radius = 2.5f, holdSeconds = 0.6f,
            labelProvider = { "Взять сапёрную лопату у раскопок" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 5 && !vm.flags["hasShovel"].orFalse() && !vm.flags["chestDug"].orFalse() },
            onInteract = {
                vm.setFlag("hasShovel", true)
                vm.audio.sfx("click"); vm.vibrate(35L)
                vm.say("Взял сапёрную лопату. Теперь можно расчистить завал штольни.", 4.0f)
                vm.setObjective("Расчистить завал штольни лопатой и откопать сундук")
                vm.refreshSceneProps()
            }
        ))
        list.add(Interactable(
            id = "ch5_cave", pos = Vec3(caveX, f1 + 0.8f, caveZ), radius = 2.6f,
            labelProvider = {
                if (vm.flags["hasShovel"].orFalse()) "Расчистить завал лопатой"
                else "Осмотреть завал штольни (нужна лопата)"
            },
            icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 5 && !vm.flags["chestDug"].orFalse() },
            onInteract = {
                if (!vm.flags["hasShovel"].orFalse()) {
                    vm.inspectModel("chest_buried", "завал штольни", "Засыпанный сундук дорожников", "За обвалившимся грунтом виден стальной сундук с ключом от моста. Нужна лопата у входа.")
                    vm.setObjective("Взять сапёрную лопату рядом со входом в штольню")
                } else {
                    vm.setInputLock(true)
                    vm.audio.sfx("footstep"); vm.vibrate(45L); vm.waitSec(0.45f)
                    vm.audio.sfx("rumble", durationSec = 1.0f)
                    vm.setEdit("startCave", true)
                    vm.setFlag("chestDug", true)
                    vm.say("Завал расчищен! Стальной сундук топографов открыт.", 3.8f)
                    vm.setObjective("Открыть сундук дорожников внутри штольни")
                    vm.setInputLock(false)
                    vm.refreshSceneProps()
                }
            }
        ))
        list.add(Interactable(
            id = "ch5_chest", pos = Vec3((1172f + 1216f) * 0.5f * VS, f1 + 0.6f, caveZ), radius = 2.6f,
            labelProvider = { if (vm.flags["chestDug"].orFalse()) "Открыть сундук дорожников" else "Засыпанный сундук" },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 5 && !vm.flags["chestOpened"].orFalse() },
            onInteract = {
                if (!vm.flags["chestDug"].orFalse()) {
                    vm.say("Сначала нужно расчистить проход лопатой.", 3.5f)
                } else {
                    vm.audio.sfx("click")
                    vm.setFlag("chestOpened", true)
                    vm.pickupItem("chest_key", "сундук дорожников")
                    if (!vm.hasItem("rune_map")) {
                        vm.waitSec(0.35f)
                        vm.pickupItem("rune_map", "сундук дорожников")
                    }
                    vm.addClue("c5_rune_map")
                    vm.say("Ключ и чертёж переправы у меня! (Порядок: Солнце, Луна, Волна, Лист)", 4.2f)
                    vm.setObjective("Подойти к каменной плите у моста и восстановить переправу")
                }
            }
        ))
        val runeDefs = listOf(
            Triple("leaf", 60.6f to 91.2f, "Лист" to "зелёным"),
            Triple("sun", 62.8f to 89.6f, "Солнце" to "красным"),
            Triple("wave", 65.6f to 91.6f, "Волна" to "жёлтым"),
            Triple("moon", 66.9f to 89.9f, "Луна" to "синим")
        )
        runeDefs.forEach { (g, posPair, labelPair) ->
            list.add(Interactable(
                id = "ch5_rune_$g", pos = Vec3(crX(posPair.first), f1 + 0.5f, crZ(posPair.second)), radius = 2.6f,
                world = WorldFilter.NIGHTMARE, labelProvider = { "Осмотреть руну «${labelPair.first}»" }, icon = InteractIcon.EYE,
                condition = { vm.currentChapter == 5 },
                onInteract = {
                    vm.inspectModel("runestone_$g", "сухое русло", "Руна «${labelPair.first}»", "Камень на дне русла. Знак светится ${labelPair.second}.")
                }
            ))
        }
        list.add(Interactable(
            id = "ch5_plate", pos = Vec3(crX(70.6f), f1 + 0.5f, crZ(95.7f)), radius = 3.0f,
            labelProvider = {
                when {
                    vm.flags["terminalUnlocked"].orFalse() -> "Ввести знаки на каменной плите у моста"
                    vm.hasItem("chest_key") -> "Отопереть плиту ключом и ввести знаки"
                    else -> "Заблокированная каменная плита (ключ в штольне)"
                }
            },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 5 && vm.edits["bridge1"] != true },
            onInteract = {
                if (!vm.hasItem("chest_key")) {
                    vm.say("Плита заперта. Ключ и чертёж лежат в сундуке в штольне у берега.", 4.2f)
                } else {
                    vm.setFlag("terminalUnlocked", true)
                    val solved = vm.openRunePuzzle(
                        kicker = "каменная плита у моста",
                        title = "Четыре знака переправы",
                        text = "Инженерный чертёж переправы указывает порядок четырёх знаков (Солнце, Луна, Волна, Лист):",
                        solutions = listOf(listOf("sun", "moon", "wave", "leaf"))
                    )
                    if (solved) {
                        vm.audio.sfx("success"); vm.audio.sfx("rumble", durationSec = 1.4f)
                        vm.setEdit("bridge1", true)
                        vm.setFlag("bridgeSolved", true)
                        vm.addClue("c5_bridge_mechanism")
                        vm.refreshSceneProps()
                        vm.say("Мост восстановлен! Сделайте вывод Пятницы и перейдите на северный берег.", 4.4f)
                        vm.setObjective("Зафиксировать вывод Пятницы в «Выводах» и перейти мост")
                    }
                }
            }
        ))
        addExit(
            5, Vec3(crX(67f), f1 + 0.8f, crZ(85f)),
            "Тропа за мостом: подняться к поляне с Оленем (Глава 6 →)",
            "Северный берег (восстановите мост и зафиксируйте вывод Пятницы)"
        )

        // ================= CHAPTER 6 =================
        val f6 = 7.5f
        val deer0 = mdX(48f) to mdZ(72.5f)
        val doorX6 = m(624f); val doorZ6 = m(508f)
        list.add(Interactable(
            id = "ch6_deer", pos = Vec3(deer0.first + 0.9f, f6 + 1.0f, deer0.second), radius = 2.8f,
            world = WorldFilter.DREAM, labelProvider = { "Коснуться Белого Оленя" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 6 && !vm.flags["deerTouched"].orFalse() },
            onInteract = {
                vm.setInputLock(true)
                vm.duality.toNight(vm.playerPos, 8f, speed = 50f, force = true)
                vm.adjustStability(-15f)
                vm.audio.sfx("heart")
                vm.say("Не двигайся. Не дыши. Он… это всё ещё он?", 3.8f)
                vm.waitSec(3.2f)
                vm.say("Он уходит в сторону дома на холме, оставляя светящийся лепесток.", 3.6f)
                vm.setFlag("deerTouched", true)
                vm.setInputLock(false)
                vm.refreshSceneProps()
                vm.setObjective("Поднять лепесток и идти к дому на холме")
            }
        ))
        list.add(Interactable(
            id = "ch6_petal", pos = Vec3(deer0.first + 0.6f, f6 + 0.5f, deer0.second + 0.3f), radius = 2.2f,
            labelProvider = { "Поднять лепесток оленя" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 6 && vm.flags["deerTouched"].orFalse() && !vm.hasItem("fallen_petal") },
            onInteract = {
                if (vm.pickupItem("fallen_petal", "след оленя")) {
                    vm.say("…Он почернел и высох прямо в ладони.", 3.6f)
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_key", pos = Vec3(doorX6 + 0.12f, f6 + 1.0f, doorZ6 + 0.3f), radius = 2.2f,
            world = WorldFilter.NIGHTMARE, labelProvider = { "Достать ключ под венком" }, icon = InteractIcon.KEY,
            condition = { vm.currentChapter == 6 && !vm.hasItem("rusty_key") },
            onInteract = {
                if (vm.pickupItem("rusty_key", "венок на двери")) {
                    vm.say("Золотой ключ от дома лесника! Вернусь в дневной сон и отопру дверь.", 4.0f)
                    vm.setObjective("Вернуться в дневной мир и открыть дверь дома")
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_door", pos = Vec3(doorX6, f6 + 1.0f, doorZ6 + 0.7f), radius = 2.5f,
            labelProvider = {
                if (!vm.isNight()) (if (vm.hasItem("rusty_key")) "Открыть дверь дома ключом" else "Открыть дверь дома")
                else "Дверь (вернитесь в дневной мир, чтобы открыть)"
            },
            icon = InteractIcon.DOOR,
            condition = { vm.currentChapter == 6 && vm.edits["door"] != true },
            onInteract = {
                if (!vm.isNight()) {
                    if (!vm.hasItem("rusty_key")) {
                        vm.audio.sfx("click")
                        vm.say("Заперто.", 1.5f)
                        vm.waitSec(0.9f)
                        vm.duality.toNight(vm.playerPos, 14f, speed = 42f)
                        vm.say("Под засохшим венком на двери что-то блестит в темноте…", 4.0f)
                        vm.setObjective("Достать ключ под венком в «Кошмаре»")
                    } else {
                        vm.audio.sfx("door")
                        vm.setEdit("door", true)
                        vm.say("Ключ провернулся. Дверь в дом открыта.", 3.5f)
                        vm.setObjective("Осмотреть комод, камин и стол: собрать 3 памятные вещи")
                    }
                } else {
                    vm.say("Вернитесь в дневной мир (кнопка Глаз), чтобы отпереть замок.", 3.4f)
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_drawers", pos = Vec3(hoX(74.9f), f6 + 0.8f, hoZ(59.5f)), radius = 2.4f,
            labelProvider = { if (vm.flags["letterD"].orFalse() && !vm.hasItem("photo_2")) "Комод (в темноте): взять фото и второй обрывок" else "Комод: открыть верхний ящик" },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 6 && (!vm.flags["letterD"].orFalse() || !vm.flags["letterN"].orFalse() || !vm.hasItem("photo_2")) },
            onInteract = {
                if (!vm.isNight() && !vm.flags["letterD"].orFalse()) {
                    vm.inspectModel("item_photo_2", "верхний ящик", "Старая фотография", "Я и Михаил. Мы смеёмся у ручья.")
                    vm.readPages("Обрывок письма (день)", listOf("…не могу больше скрывать.", "Ты должен знать правду о том, что случилось у ручья…"), false)
                    vm.setFlag("letterD", true)
                    vm.giveItem("letter_dream", silent = true)
                    vm.duality.toNight(vm.playerPos, 22f, speed = 34f, force = true)
                    vm.say("Буквы поплыли… Осмотрите ящик ещё раз в темноте!", 3.8f)
                    vm.setObjective("В темноте открыть верхний ящик комода и взять фото и второй обрывок")
                } else {
                    if (!vm.isNight()) {
                        vm.duality.toNight(vm.playerPos, 20f, speed = 40f, force = true)
                        vm.waitSec(0.35f)
                    }
                    if (!vm.hasItem("photo_2")) {
                        vm.pickupItem("photo_2", "верхний ящик")
                        vm.addClue("c6_gold_locket")
                    }
                    if (!vm.flags["letterN"].orFalse()) {
                        vm.readPages("Обрывок письма (ночь)", listOf("…я не могу тебя найти. Три дня.", "Полиция ничего не делает. Я знаю, что ты был у ручья…"), true)
                        vm.setFlag("letterN", true)
                        vm.giveItem("letter_night", silent = true)
                        vm.setObjective("Подойти к обеденному столу и сложить части письма")
                    }
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_table_letter", pos = Vec3(hoX(81f), f6 + 0.8f, hoZ(58.7f)), radius = 2.4f,
            labelProvider = { "Стол: сложить части письма" }, icon = InteractIcon.READ,
            condition = { vm.currentChapter == 6 && vm.flags["letterD"].orFalse() && vm.flags["letterN"].orFalse() && !vm.hasItem("letter_full") },
            onInteract = {
                val ok = vm.openLetterPuzzle()
                if (ok) {
                    vm.takeItem("letter_dream")
                    vm.takeItem("letter_night")
                    vm.giveItem("letter_full")
                    vm.addClue("c6_house_letter")
                    vm.readPages("Восстановленное письмо", listOf(
                        "Я не могу больше скрывать. Ты должен знать правду о том, что случилось у ручья.",
                        "Я не могу тебя найти. Три дня. Полиция ничего не делает. Я знаю, что ты был у ручья.",
                        "Вернись. Пожалуйста."
                    ), false)
                    vm.setObjective(
                        if (!vm.hasItem("locket")) "Забрать золотой медальон с каминной полки"
                        else "Все 3 памятные вещи собраны! Сделайте вывод Субботы в «Выводах»"
                    )
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_locket", pos = Vec3(hoX(77.9f), f6 + 1.2f, hoZ(57.25f)), radius = 2.4f,
            labelProvider = { "Камин: взять золотой медальон" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 6 && !vm.hasItem("locket") },
            onInteract = {
                if (vm.pickupItem("locket", "каминная полка")) {
                    vm.addClue("c6_gold_locket")
                    vm.setObjective(
                        if (vm.hasItem("letter_full") && vm.hasItem("photo_2"))
                            "Воспоминания дома собраны (3 из 3). Сделайте вывод Субботы в «Выводах»"
                        else "Сложите письмо на столе и заберите фотографию из комода"
                    )
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_hearth", pos = Vec3(hoX(78f), f6 + 0.8f, hoZ(56.78f)), radius = 2.3f,
            labelProvider = { if (!vm.flags["hearthRepaired"].orFalse()) "Камин: разжечь сухими дровами (опц.)" else "Погреться у камина" },
            icon = InteractIcon.FIRE,
            condition = { vm.currentChapter == 6 },
            onInteract = {
                if (!vm.flags["hearthRepaired"].orFalse()) {
                    vm.setFlag("hearthRepaired", true)
                    vm.audio.sfx("success")
                    vm.adjustStability(35f)
                    vm.duality.toDream(vm.playerPos)
                    vm.say("Берёзовые дрова вспыхнули! Живой огонь согревает весь дом.", 3.8f)
                    vm.refreshSceneProps()
                } else {
                    vm.duality.toDream(vm.playerPos)
                    vm.adjustStability(20f)
                    vm.say("Огонь в камине потрескивает. Пальцы наконец согрелись.", 3.4f)
                }
            }
        ))
        list.add(Interactable(
            id = "ch6_bench", pos = Vec3(P_BENCH.first, f6 + 0.5f, P_BENCH.second), radius = 2.2f,
            labelProvider = { "Присесть на скамейку и перевести дух" }, icon = InteractIcon.SIT,
            condition = { vm.currentChapter == 6 },
            onInteract = {
                vm.duality.toDream(vm.playerPos)
                vm.adjustStability(25f)
                vm.say("Здесь… спокойнее. Можно перевести дух.", 3.5f)
            }
        ))
        list.add(Interactable(
            id = "ch6_cassette", pos = Vec3(hoX(72.9f), f6 + 0.8f, hoZ(57.8f)), radius = 2.3f,
            labelProvider = { "Тайник у стены: найти аудиокассету Лии (опц.)" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 6 && !vm.hasItem("cassette_leah") },
            onInteract = {
                if (vm.pickupItem("cassette_leah", "тайник под половицами")) {
                    vm.addClue("c6_leah_cassette")
                    vm.adjustStability(50f)
                    vm.voice("«Мы ждём тебя, Элиас, вернись скорее!»", 4.2f, "Аудиокассета")
                }
            }
        ))
        addExit(
            6, Vec3(hoX(74f), f6 + 0.8f, hoZ(53f)),
            "Калитка за домом: выйти на тропу каменных лиц (Глава 7 →)",
            "Калитка за домом (соберите 3 памятные вещи и сделайте вывод Субботы)"
        )

        // ================= CHAPTER 7 =================
        val cfX = P_CAMPFIRE.first; val cfZ = P_CAMPFIRE.second
        list.add(Interactable(
            id = "ch7_carved_stone", pos = Vec3((hoX(74f) + cfX) * 0.5f + 2f, f6 + 0.5f, (hoZ(52f) + cfZ) * 0.5f), radius = 2.6f,
            labelProvider = { "Поднять резной камень-оберег (опц.)" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 7 && !vm.hasItem("carved_stone") },
            onInteract = {
                if (vm.pickupItem("carved_stone", "тропа каменных лиц")) vm.addClue("c7_carved_stone")
            }
        ))
        list.add(Interactable(
            id = "ch7_backpack_d", pos = Vec3(cfX + 1.7f, f6 + 0.5f, cfZ + 1.1f), radius = 2.4f,
            world = WorldFilter.DREAM, labelProvider = { "Рюкзак: достать дневную карту" }, icon = InteractIcon.BAG,
            condition = { vm.currentChapter == 7 && !vm.hasItem("map_dream") && !vm.hasItem("map_combined") },
            onInteract = {
                vm.say("Наш походный рюкзак… Достану дневную карту троп.", 3.5f)
                vm.pickupItem("map_dream", "рюкзак у костра")
                if (!vm.hasItem("map_night")) {
                    vm.duality.toNight(vm.playerPos, 16f, speed = 40f)
                    vm.setObjective("Забрать фонарик и тёмную карту из разорванного рюкзака в «Кошмаре»")
                }
            }
        ))
        list.add(Interactable(
            id = "ch7_backpack_n", pos = Vec3(cfX + 1.7f, f6 + 0.5f, cfZ + 1.1f), radius = 2.4f,
            world = WorldFilter.NIGHTMARE, labelProvider = { "Разорванный рюкзак: фонарик и тёмная карта" }, icon = InteractIcon.BAG,
            condition = { vm.currentChapter == 7 && (!vm.hasItem("broken_flashlight") || (!vm.hasItem("map_night") && !vm.hasItem("map_combined"))) },
            onInteract = {
                if (!vm.hasItem("broken_flashlight") && vm.pickupItem("broken_flashlight", "разорванный рюкзак")) {
                    vm.say("Фонарик горит! Кнопка справа внизу включает луч.", 3.6f)
                }
                if (!vm.hasItem("map_night") && !vm.hasItem("map_combined")) {
                    vm.pickupItem("map_night", "разорванный рюкзак")
                }
                if (vm.hasItem("map_dream") && vm.hasItem("map_night")) {
                    vm.setObjective("Подойти к бревну у костра и совместить обе карты")
                }
            }
        ))
        list.add(Interactable(
            id = "ch7_log", pos = Vec3(cfX - 1.2f, f6 + 0.5f, cfZ + 0.6f), radius = 2.5f,
            labelProvider = { "Бревно у костра: совместить карты" }, icon = InteractIcon.COMBINE,
            condition = { vm.currentChapter == 7 && vm.hasItem("map_dream") && vm.hasItem("map_night") },
            onInteract = {
                val ok = vm.openMapPuzzle(readOnly = false)
                if (ok) {
                    vm.takeItem("map_dream"); vm.takeItem("map_night")
                    vm.giveItem("map_combined")
                    vm.addClue("c7_combined_map")
                    vm.audio.sfx("success")
                    vm.say("Красный крест указывает на изгиб ручья! Осмотрите чащу к западу от костра.", 4.4f)
                    if (!vm.hasItem("photo_3")) vm.setObjective("Осмотреть лесную чащу к западу и найти студенческий билет")
                }
            }
        ))
        list.add(Interactable(
            id = "ch7_teddy", pos = Vec3(P_THICKET.first + 0.7f, f6 + 0.4f, P_THICKET.second + 1.2f), radius = 2.2f,
            labelProvider = { if (vm.isNight()) "Достать записку из мишки (опц.)" else "Осмотреть плюшевого мишку" },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 7 && !vm.hasItem("bear_note") },
            onInteract = {
                if (!vm.isNight()) {
                    vm.inspectModel("teddy", "чаща", "Плюшевый мишка", "Детская игрушка посреди чащи. В темноте внутри что-то спрятано.")
                } else if (vm.pickupItem("bear_note", "чаща")) {
                    vm.addClue("c7_carved_stone")
                    vm.readPages("Записка", listOf("Мама, я боюсь темноты."), false)
                }
            }
        ))
        list.add(Interactable(
            id = "ch7_figure_card", pos = Vec3(tkX(37.4f), f6 + 1.2f, tkZ(41.4f)), radius = 2.9f,
            labelProvider = { if (vm.isNight()) "Взять студенческий билет, который он протягивает" else "Фигура в чаще (вглядитесь Глазом, чтобы взять)" },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 7 && !vm.hasItem("photo_3") },
            onInteract = {
                if (!vm.isNight()) {
                    vm.duality.toNight(vm.playerPos, 18f, speed = 42f, force = true)
                    vm.waitSec(0.5f)
                }
                vm.say("Он протягивает размокшую карточку…", 3.2f)
                vm.waitSec(0.8f)
                if (vm.pickupItem("photo_3", "фигура в чаще")) {
                    vm.addClue("c7_student_card")
                    vm.say("Студенческий билет: «МИХАИЛ». Я вспомнил его имя!", 4.4f)
                    vm.setObjective("Зафиксировать вывод Главы 7 и пройти к верховью ручья")
                }
            }
        ))
        addExit(
            7, Vec3(tkX(31f), f6 + 0.8f, tkZ(43f)),
            "Тропа вдоль воды: выйти к верховью ручья (Глава 8 →)",
            "Путь к ручью (совместите карты, заберите билет и зафиксируйте вывод)"
        )

        // ================= CHAPTER 8 =================
        list.add(Interactable(
            id = "ch8_wheelcap", pos = Vec3(upaX(22.6f), f6 + 0.5f, upaZ(46.3f)), radius = 2.5f,
            world = WorldFilter.DREAM, labelProvider = { "Осмотреть колпак колеса (опц.)" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 8 && !vm.hasClue("c8_wheel_cap") },
            onInteract = {
                vm.inspectModel("item_locket", "дно ручья", "Сорванный колпак колеса", "Протектор стёрт — на мокром камне машину понесло юзом.")
                vm.addClue("c8_wheel_cap")
            }
        ))
        list.add(Interactable(
            id = "ch8_reflection", pos = Vec3(upaX(25.2f), f6 + 0.5f, upaZ(44.6f)), radius = 2.5f,
            world = WorldFilter.DREAM, labelProvider = { "Посмотреть в воду ручья" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 8 && !vm.flags["reflection"].orFalse() },
            onInteract = {
                vm.setInputLock(true)
                vm.say("В воде — отражение. Я. Только я.", 2.6f)
                vm.waitSec(2.4f)
                vm.duality.toNight(vm.playerPos, 15f, speed = 70f, force = true)
                vm.audio.sfx("heart")
                vm.say("…За моей спиной кто-то стоит.", 2.4f)
                vm.waitSec(2.2f)
                vm.audio.sfx("glitch"); vm.vibrate(140L)
                vm.rotatePlayerYaw(kotlin.math.PI.toFloat())
                vm.setFlag("reflection", true)
                vm.addClue("c8_metal_shard")
                vm.setInputLock(false)
            }
        ))
        list.add(Interactable(
            id = "ch8_plate", pos = Vec3(upaX(22.5f), f6 + 0.5f, upaZ(46.9f)), radius = 2.8f,
            labelProvider = { if (!vm.isNight()) "Вглядеться в воду и достать номер «7319»" else "Выхватить фонариком номер «7319» со дна" },
            icon = InteractIcon.FLASH,
            condition = { vm.currentChapter == 8 && !vm.hasItem("license_plate") },
            onInteract = {
                if (!vm.isNight()) {
                    vm.duality.toNight(vm.playerPos, 20f, speed = 45f, force = true)
                    vm.waitSec(0.45f)
                }
                if (!vm.hasItem("broken_flashlight")) vm.giveItem("broken_flashlight", silent = true)
                vm.setFlashOn(true)
                vm.say("Луч фонарика выхватывает цифры под водой…", 2.4f)
                vm.waitSec(1.0f)
                if (vm.pickupItem("license_plate", "дно ручья")) {
                    vm.addClue("c8_license_plate")
                    vm.say("Номерной знак «7319». Вторая цифра — тройка.", 4.2f)
                }
            }
        ))
        list.add(Interactable(
            id = "ch8_shard", pos = Vec3(upaX(25.8f), f6 + 0.5f, upaZ(47.7f)), radius = 2.5f,
            labelProvider = { "Поднять стальной обломок капота" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 8 && !vm.hasItem("metal_shard") },
            onInteract = {
                if (!vm.isNight()) {
                    vm.duality.toNight(vm.playerPos, 18f, speed = 45f, force = true)
                    vm.waitSec(0.35f)
                }
                if (vm.pickupItem("metal_shard", "береговые валуны")) {
                    vm.addClue("c8_metal_shard")
                    vm.say("Искорёженная сталь со следами удара о валуны.", 3.6f)
                }
            }
        ))
        addExit(
            8, Vec3(P_CLIFF.first - 0.5f, f6 + 0.8f, P_CLIFF.second - 0.5f),
            "Скальный карниз: подняться к мосту над пропастью (Глава 9 →)",
            "Скальный обрыв (достаньте номер «7319» и обломок и зафиксируйте вывод)"
        )

        // ================= CHAPTER 9 =================
        val f9 = 8.0f
        list.add(Interactable(
            id = "ch9_feather", pos = Vec3(noX(73.6f), f9 + 0.6f, noZ(39.6f)), radius = 2.3f,
            labelProvider = { "У фонаря: поднять чёрное перо ворона (опц.)" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 9 && !vm.hasItem("feather_black") },
            onInteract = {
                if (vm.pickupItem("feather_black", "фонарь у моста")) vm.addClue("c9_black_feather")
            }
        ))
        list.add(Interactable(
            id = "ch9_girder", pos = Vec3(m(588f + 600f) + 0.4f, f9 + 0.6f, m(252f + 536f) + 0.8f), radius = 2.6f,
            labelProvider = { "Вонзить стальной осколок в трещину балки" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 9 && !vm.flags["grip"].orFalse() },
            onInteract = {
                vm.setFlag("grip", true)
                vm.audio.sfx("stone")
                vm.say("Осколок вошёл в трещину. Можно перейти мост к решётке тоннеля.", 3.8f)
            }
        ))
        list.add(Interactable(
            id = "ch9_codelock", pos = Vec3(noX(76.3f), f9 + 0.8f, m(188 + 536) + 1.1f), radius = 3.0f,
            labelProvider = { "Кодовый замок на решётке («7319»)" }, icon = InteractIcon.KEY,
            condition = { vm.currentChapter == 9 && vm.edits["grate"] != true },
            onInteract = {
                val ok = vm.openCodePuzzle(
                    title = "Ржавая решётка",
                    text = "Четыре цифры с автомобильного номера «7319»:",
                    targetCode = "7319"
                )
                if (ok) {
                    vm.audio.sfx("success"); vm.audio.sfx("rumble", durationSec = 1.4f)
                    vm.setEdit("grate", true)
                    vm.addClue("c9_grate_code")
                    vm.setObjective("Пройти тоннель мозаик и разгадать четыре рунные ниши")
                    vm.refreshSceneProps()
                }
            }
        ))
        list.add(Interactable(
            id = "ch9_niches", pos = Vec3(noX(74.4f), f9 + 0.8f, noZ(18.8f)), radius = 3.2f,
            labelProvider = { "Каменные ниши: вставить четыре руны" }, icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 9 && vm.edits["tunnelWall"] != true },
            onInteract = {
                if (!vm.hasItem("rune_map")) vm.giveItem("rune_map", silent = true)
                val ok = vm.openRunePuzzle(
                    kicker = "мозаика тоннеля",
                    title = "Четыре ниши обратного времени",
                    text = "Формы ниш повторяют руны переправы в обратном порядке (Лист, Волна, Луна, Солнце):",
                    solutions = listOf(listOf("leaf", "wave", "moon", "sun"), listOf("sun", "moon", "wave", "leaf"))
                )
                if (ok) {
                    vm.audio.sfx("success"); vm.audio.sfx("rumble", durationSec = 1.6f)
                    vm.setEdit("tunnelWall", true)
                    vm.addClue("c9_reverse_runes")
                    vm.refreshSceneProps()
                    vm.say("Каменная преграда отъехала! Зафиксируйте вывод Воскресенья и шагните в зал Источника.", 4.4f)
                    vm.setObjective("Зафиксировать вывод Главы 9 и войти в зал Источника")
                }
            }
        ))
        addExit(
            9, Vec3(noX(75.5f), f9 + 0.8f, m(136 + 536) - 0.8f),
            "Зал Источника: шагнуть за грань в Главу 10 («Между» →)",
            "Проход в грот (откройте каменную преграду и зафиксируйте вывод Воскресенья)"
        )

        // ================= CHAPTER 10 =================
        val plx = P_POOL.first + 0.25f; val plz = P_POOL.second + 0.25f
        list.add(Interactable(
            id = "ch10_pool", pos = Vec3(plx, f9 + 0.5f, plz + 2.8f), radius = 3.8f,
            labelProvider = { "Посмотреть в зеркальную воду Источника" }, icon = InteractIcon.EYE,
            condition = { vm.currentChapter == 10 && !vm.flags["flashback"].orFalse() },
            onInteract = { vm.runCh10SourceFlashback() }
        ))
        list.add(Interactable(
            id = "ch10_car_key", pos = Vec3(plx, f9 + 0.5f, plz + 3.6f), radius = 2.4f,
            labelProvider = { "Поднять ключ зажигания с брелоком" }, icon = InteractIcon.KEY,
            condition = { vm.currentChapter == 10 && vm.flags["flashback"].orFalse() && !vm.hasItem("car_key") },
            onInteract = {
                if (vm.pickupItem("car_key", "кромка воды")) {
                    vm.setFlag("car_key_taken", true)
                    vm.addClue("c10_car_key")
                    vm.refreshSceneProps()
                    val prof = vm.memoryProfile()
                    vm.say(vm.adapt(
                        defaultText = "Слева у воды стоит Михаил и протягивает руку. Справа — тёплый туман сна.",
                        truthText = "Слева у воды стоит Михаил и протягивает руку в реальную Палату № 7. Справа — туман сна.",
                        denialText = "Справа сияет тёплый выход в Вечный Понедельник. Слева — голос из холодной больницы.",
                        projectionText = "Справа — выход в одиночество, прочь от чужих голосов. Слева ждёт Михаил."
                    ), 5.0f)
                    val profLabel = when (prof.dominant) {
                        MemoryVector.TRUTH -> "Принятие правды"
                        MemoryVector.DENIAL -> "Иллюзия покоя"
                        MemoryVector.PROJECTION -> "Отрицание и тень"
                    }
                    vm.setObjective("Сделать финальный выбор (Профиль памяти: $profLabel)")
                }
            }
        ))
        list.add(Interactable(
            id = "ch10_east_portal", pos = Vec3(noX(90.5f), f9 + 0.9f, noZ(7.8f)), radius = 3.2f, holdSeconds = 1.0f,
            labelProvider = {
                if (vm.memoryProfile().dominant == MemoryVector.PROJECTION)
                    "Уйти в тень в одиночку (Концовка Проекции)"
                else "Шагнуть в тёплый свет иллюзии (Вечный Понедельник)"
            },
            icon = InteractIcon.SUN,
            condition = { vm.currentChapter == 10 && vm.hasItem("car_key") && !vm.flags["ended"].orFalse() },
            onInteract = {
                if (vm.memoryProfile().dominant == MemoryVector.PROJECTION) vm.triggerEndingProjection()
                else vm.triggerEndingDenial()
            }
        ))
        list.add(Interactable(
            id = "ch10_west_portal", pos = Vec3(noX(63.8f), f9 + 0.9f, noZ(7.75f)), radius = 3.2f, holdSeconds = 1.0f,
            labelProvider = {
                val p = vm.memoryProfile()
                if (p.truth >= p.denial && p.truth >= p.projection)
                    "Взять Михаила за руку (очнуться в Палате № 7)"
                else "Протянуть руку сквозь сомнения (Хрупкое пробуждение)"
            },
            icon = InteractIcon.HAND,
            condition = { vm.currentChapter == 10 && vm.hasItem("car_key") && !vm.flags["ended"].orFalse() },
            onInteract = {
                val p = vm.memoryProfile()
                if (p.truth >= p.denial && p.truth >= p.projection) vm.triggerEndingTruth()
                else vm.triggerEndingMixed()
            }
        ))

        return list
    }

    private fun Boolean?.orFalse(): Boolean = this == true
}
