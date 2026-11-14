package com.example

import android.opengl.GLSurfaceView
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.data.ActiveModal
import com.example.data.AppMode
import com.example.ui.GameViewModel
import com.example.ui.components.CinemaOverlay
import com.example.ui.components.CodePuzzleModal
import com.example.ui.components.EndingOverlay
import com.example.ui.components.HudOverlay
import com.example.ui.components.InspectModal
import com.example.ui.components.InventoryModal
import com.example.ui.components.LetterPuzzleModal
import com.example.ui.components.MainMenuScreen
import com.example.ui.components.MapPuzzleModal
import com.example.ui.components.MemoryBoardModal
import com.example.ui.components.NpcDialogueModal
import com.example.ui.components.PauseOverlay
import com.example.ui.components.ReaderModal
import com.example.ui.components.RunePuzzleModal
import com.example.ui.components.SaveLoadModal
import com.example.ui.components.SettingsModal
import com.example.ui.theme.MezhduTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MezhduTheme {
                MezhduAppRoot()
            }
        }
    }
}

@Composable
private fun MezhduAppRoot(vm: GameViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    val glView = remember {
        GLSurfaceView(context).apply {
            setEGLContextClientVersion(3)
            setRenderer(vm.renderer)
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        }
    }

    DisposableEffect(lifecycleOwner, glView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    glView.onResume()
                    vm.onAppResume()
                }
                Lifecycle.Event.ON_PAUSE -> {
                    glView.onPause()
                    vm.onAppPause()
                }
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    if (state.mode == AppMode.PLAYING && state.activeModal == null) {
        BackHandler { vm.togglePause() }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Keep GLSurfaceView mounted when in game/paused/cinema/ending
        if (state.mode != AppMode.MENU) {
            AndroidView(
                factory = { glView },
                modifier = Modifier.fillMaxSize()
            )
        }

        when (state.mode) {
            AppMode.MENU -> {
                MainMenuScreen(
                    hasAutoSave = state.hasAutoSave,
                    onContinue = { vm.continueFromAutoSave() },
                    onNewGame = { vm.startNewGame() },
                    onOpenLoad = { vm.openSaveLoad(isSaving = false) },
                    onOpenSettings = { vm.openSettings() }
                )
            }
            AppMode.PLAYING -> {
                HudOverlay(
                    state = state,
                    onJoystickMove = vm::setJoystick,
                    onLookDrag = vm::onLookDrag,
                    onActionStart = vm::onActionPressStart,
                    onActionEnd = vm::onActionPressEnd,
                    onToggleEye = vm::togglePeerEye,
                    onToggleFlash = vm::toggleFlashlight,
                    onUsePhoto = vm::useMemoryPhotoAnchor,
                    onOpenInventory = vm::openInventory,
                    onOpenBoard = vm::openMemoryBoard,
                    onTogglePause = vm::togglePause
                )
            }
            AppMode.PAUSED -> {
                PauseOverlay(
                    chapter = state.chapter,
                    chapterTitle = state.chapterTitle.ifEmpty { "Глава ${state.chapter}" },
                    onResume = vm::togglePause,
                    onOpenSave = { vm.openSaveLoad(isSaving = true) },
                    onOpenLoad = { vm.openSaveLoad(isSaving = false) },
                    onOpenSettings = vm::openSettings,
                    onReturnMenu = vm::returnToMainMenu
                )
            }
            AppMode.CINEMA -> {
                CinemaOverlay(
                    state = state,
                    onSkip = vm::skipIntroCinema
                )
            }
            AppMode.ENDING -> {
                state.endingState?.let { end ->
                    EndingOverlay(
                        ending = end,
                        onFinish = vm::returnToMainMenu
                    )
                }
            }
        }

        // Active Modal Overlays
        when (val m = state.activeModal) {
            is ActiveModal.Inventory -> {
                InventoryModal(
                    itemIds = state.inventory,
                    isNight = state.isNight,
                    onInspect = { modelId, name, desc ->
                        scope.launch {
                            vm.inspectModel(modelId, "осмотр предмета", name, desc)
                        }
                    },
                    onUseItem = vm::useInventoryItem,
                    onDismiss = vm::dismissActiveModal
                )
            }
            is ActiveModal.MemoryBoard -> {
                MemoryBoardModal(
                    state = state,
                    profile = vm.memoryProfile(),
                    isChapterExitReady = vm::isChapterExitReady,
                    isMandatoryWorldDone = vm::isMandatoryWorldDone,
                    onLockConclusion = vm::lockConclusion,
                    onAdvanceChapter = vm::advanceToChapter,
                    onDismiss = vm::dismissActiveModal
                )
            }
            is ActiveModal.SaveLoad -> {
                SaveLoadModal(
                    isSaving = m.isSaving,
                    slots = state.saveSlots,
                    onSaveSlot = { slotId -> vm.saveToSlot(slotId) },
                    onLoadSlot = { slotId -> vm.loadFromSlot(slotId) },
                    onDeleteSlot = { slotId -> vm.deleteSaveSlot(slotId) },
                    onDismiss = vm::dismissActiveModal
                )
            }
            is ActiveModal.Settings -> {
                SettingsModal(
                    settings = state.settings,
                    onUpdate = vm::updateSettings,
                    onDismiss = vm::dismissActiveModal
                )
            }
            is ActiveModal.Inspect -> {
                InspectModal(modal = m, onConfirm = vm::completeInspect)
            }
            is ActiveModal.Reader -> {
                ReaderModal(modal = m, onDismiss = vm::completeReader)
            }
            is ActiveModal.NpcDialogue -> {
                NpcDialogueModal(
                    modal = m,
                    onAskQuestion = vm::askNpcQuestion,
                    onRecordTestimony = vm::recordNpcTestimony,
                    onClose = vm::closeNpcDialog
                )
            }
            is ActiveModal.RunePuzzle -> {
                RunePuzzleModal(modal = m, onComplete = vm::completeRunePuzzle)
            }
            is ActiveModal.LetterPuzzle -> {
                LetterPuzzleModal(modal = m, onComplete = vm::completeLetterPuzzle)
            }
            is ActiveModal.CodePuzzle -> {
                CodePuzzleModal(modal = m, onComplete = vm::completeCodePuzzle)
            }
            is ActiveModal.MapPuzzle -> {
                MapPuzzleModal(modal = m, onComplete = vm::completeMapPuzzle)
            }
            null -> {}
        }
    }
}
