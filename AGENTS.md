# МЕЖДУ — нативный клиент (Rust + wgpu)

Инструкция для любого ИИ-агента (Claude, Gemini, Jules). Читать целиком перед работой. Отвечать пользователю по-русски.

## Что это
Нативный Android-клиент игры «МЕЖДУ» — воксельного детектива о советском посёлке 1980-х. Основная игра — веб-версия в репозитории **Kejikeq/-** (JS, WebGPU, WGSL). Она остаётся главной и **только для чтения** отсюда. Этот репозиторий рисует тот же мир нативно: wgpu на Vulkan, с откатом на GLES, на Redmi 10S (Helio G95, Mali-G76 MC4) с целью 30 FPS при минимуме батареи.

## Контракт: контент-пак
Всё, что веб-версия вычисляет в JS, приходит сюда готовыми файлами. Пак собирает `node tools/export-native.mjs <out>` в репозитории Kejikeq/-:
- `manifest.json` — format, version, commit, constants (VS, WX/WY/WZ, TILE, ATLAS_W/H, флаги материалов…), files[{path, sha256, size, kind…}];
- `shaders/*.wgsl` — готовый WGSL (14 шейдеров, все проходят naga);
- `atlas/{det,pbr}_L0..4.bin.zst` — RGBA8 мип-уровни атласа, zstd, размеры в manifest. det хранит цвет/среднее ×0.25, шейдер умножает на 4;
- `tex/fog.bin`, `tex/lut.bin` — маленькие запечённые текстуры;
- `materials.bin` — f32, 256 × 8 (раскладка в manifest); `materials.json` — имена;
- `world/<tx>_<tz>.bin.zst` — тайл 256×128×256 вокселей u16, индекс x + 256*(z + 256*y). Младший байт — материал Сна, старший — Кошмара. Воксель 0,125 м.

**Пак и шейдеры здесь не править и формат не придумывать.** Если чего-то не хватает или шейдер не принимается — напиши пользователю блок «ДЛЯ CLAUDE» с точным текстом проблемы; правка делается в Kejikeq/-.

## Устройство репозитория
- `crates/core` — формат пака (`Pack`, `Manifest`), zstd (ruzstd), sha256, проверка WGSL через naga. `cargo run --release -p mezdu-core --bin packcheck -- <пак>` — проверка пака.
- `crates/gfx` — wgpu: `Gfx::new` пробует Vulkan, затем GL; `compile_shaders`; кадр.
- `crates/app` — winit 0.30: `android_main` (NativeActivity через cargo-apk) и десктоп `main.rs`. Переменные: `MEZDU_PACK=<папка пака>`, `MEZDU_BACKEND=gl|vulkan`.
- `.github/workflows/android.yml` — clippy и APK при каждом push в main → релиз `app` (`mezhdu.apk`).
- `.github/workflows/pack.yml` — каждые 30 мин берёт main из Kejikeq/- (секрет `GAME_REPO_TOKEN`), собирает и проверяет пак → релиз `pack`. Имена файлов: `/` → `__` (`mezdu_core::asset_name`).

## Правила
- Rust, без Java/Kotlin (исключение — минимальная прослойка для установки APK, если без неё никак).
- Никаких аллокаций в кадре; тяжёлый CPU — в потоках; рендер останавливается в фоне (`suspended`).
- Перед коммитом: `cargo clippy --release -- -D warnings` и то же для `--target aarch64-linux-android -p mezdu-app`. Десктоп: `MEZDU_PACK=pack cargo run --release -p mezdu-app` — смотреть лог.
- Крейты добавлять только с причиной. Версии: wgpu 30, naga 30, winit 0.30.
- Один этап за запрос. Итог пользователю — до 8 строк: что сделано, что проверить на телефоне, блок «ДЛЯ CLAUDE», если нужен.
- Логику, сюжет и UI из JS не переписывать, пока пользователь не попросит.

## Этапы
- [x] **1. Каркас.** Окно, wgpu с Vulkan→GL, очистка экрана, FPS в логе и заголовке, компиляция всех шейдеров пака, CI с APK.
- [ ] **2. Обновления.** `crates/updater`: скачать `manifest.json` из `https://github.com/Kejikeq/Mezdu-android/releases/download/pack/`, докачать файлы с другим sha256 (`asset_name`), атомарно заменить папку `pack` в каталоге данных, работать офлайн с последним паком. Проверка нового APK через `releases/download/app/apk-version.txt` и предложение установить. Нужен публичный репозиторий. HTTP — ureq с rustls.
- [ ] **3. Атлас и материалы на GPU.** Текстуры det/pbr с 5 мипами, таблица материалов, fog/lut.
- [ ] **4. Мир.** Распаковка тайлов, многопоточный мешер чанков под входы `vsTerrain` в `shaders/world.wgsl`, камера-облёт (касание — поворот, два пальца — движение), квады и вызовы в оверлее.
- [ ] **5. Проходы рендера** в порядке веб-версии (`src/gfx/renderer.js` в Kejikeq/-): тени, AO, SSR, объём, TAA, экспозиция, композит; замер времени проходов.
- [ ] **6. Профиль качества** как `QUALITY` в `src/main.js` Kejikeq/-; урезанный профиль для GL; ограничение 30 FPS.

Отмечай выполненный этап `[x]` в этом файле в том же коммите.
