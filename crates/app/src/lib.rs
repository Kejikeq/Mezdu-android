//! Window, lifecycle, screens and the frame loop. Android enters through `android_main`, desktop through `main.rs`.
//! Screens: loading (the world is built after the first frame shows it) → menu (the village behind) → game ⇄ pause.
use mezdu_core::Pack;
use mezdu_game::player::{Input, Player};
use mezdu_game::rig::{write_rig, RigModels};
use mezdu_game::voxels::Voxels;
use mezdu_gfx::world::{Camera, World};
use mezdu_gfx::Gfx;
use mezdu_ui::{egui, Phase, Ui, ACCENT, INK};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use winit::application::ApplicationHandler;
use winit::event::{ElementState, MouseButton, Touch, TouchPhase, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};

mod save;
mod url;

const FRAME: std::time::Duration = std::time::Duration::from_nanos(1_000_000_000 / 30);
const SKY: [f64; 3] = [0.051, 0.043, 0.063]; // --bg of the web version, behind the loading screen

/// chapter 1 spawn (chapters_data.js: voxel 454, 2234, facing +z) and a height hint above the ground floor
const SPAWN: [f32; 4] = [454.0 * 0.125, 8.5, 2234.0 * 0.125, 0.0];
/// the menu's view: the street in front of the chapter 1 house
const MENU_CAM: [f32; 5] = [54.0, 11.0, 312.0, -0.25, -0.18];

/// touch id, where the finger landed, where it is now
type Joystick = (u64, (f64, f64), (f64, f64));

/// the hero walking the voxel world (player.js) with the rig drawn by the renderer
struct Hero {
    vox: Voxels,
    player: Player,
    rig: Option<RigModels>,
    words: Vec<u32>,
    /// on-screen joystick: touch id, where it started, where it is
    joy: Option<Joystick>,
    look: [f32; 2],
}

/// megabytes with one decimal, as the loading screen shows them ("9,8 МБ")
fn mb(bytes: u64) -> String {
    format!("{:.1} МБ", bytes as f64 / 1_048_576.0).replace('.', ",")
}

/// the loading stages shown on the loading screen
const STAGES: [&str; 4] = ["Поиск обновлений", "Проверка целостности файлов", "Компиляция шейдеров под видеокарту", "Построение мира"];

#[derive(Default)]
struct LoadState {
    stage: usize,
    frac: f32,
    /// what the last stage found (shown under its line)
    notes: [String; 4],
}

struct Loaded {
    pack: Pack,
    vox: Option<Voxels>,
    world: World,
}

/// The loader thread: updates, integrity, shaders, world. Nothing in it touches the window.
fn load(ctx: mezdu_gfx::DeviceCtx, data_dir: PathBuf, fixed: Option<PathBuf>, st: Arc<Mutex<LoadState>>) -> Result<Loaded, String> {
    let set = |stage: usize, frac: f32| {
        if let Ok(mut s) = st.lock() {
            s.stage = stage;
            s.frac = frac;
        }
    };
    let note = |stage: usize, t: String| {
        if let Ok(mut s) = st.lock() {
            s.notes[stage] = t;
        }
    };
    // 1. updates: a newer pack of the release is downloaded and installed before anything reads it
    set(0, 0.0);
    if fixed.is_none() {
        mezdu_updater::install_staged(&data_dir);
        match mezdu_updater::update_now(&data_dir, &|done, total| {
            set(0, done as f32 / total.max(1) as f32);
            note(0, format!("скачивается: {} из {}", mb(done), mb(total)));
        }) {
            Ok(mezdu_updater::Outcome::Staged { commit, downloaded, dropped }) => note(0, format!("установлено обновление {}: скачано файлов {downloaded}, удалено {dropped}", &commit[..7.min(commit.len())])),
            Ok(mezdu_updater::Outcome::UpToDate) => note(0, "установлена последняя версия".into()),
            Ok(mezdu_updater::Outcome::Skipped(_)) => note(0, "установлена последняя версия".into()),
            Err(e) => {
                log::warn!("updates: {e}");
                note(0, "нет связи, проверка пропущена".into());
            }
        }
    } else {
        note(0, "пак задан вручную (MEZDU_PACK)".into());
    }
    // the game library itself: a newer one is downloaded now and starts with the next launch
    if let (Some(abi), false) = (ABI, BUILD.is_empty()) {
        let prev = st.lock().map(|s| s.notes[0].clone()).unwrap_or_default();
        match mezdu_updater::check_code(&data_dir, abi, BUILD, &|done, total| note(0, format!("{prev}; программа: {} из {}", mb(done), mb(total)))) {
            Ok(mezdu_updater::CodeOutcome::Staged { build, .. }) => note(0, format!("{prev}; программа {build} скачана, заработает при следующем запуске")),
            Ok(mezdu_updater::CodeOutcome::NeedApk { build }) => note(0, format!("{prev}; программа {build} требует установить новый APK")),
            Ok(mezdu_updater::CodeOutcome::UpToDate) => note(0, prev),
            Err(e) => {
                log::warn!("code update: {e}");
                note(0, prev);
            }
        }
    }
    // 2. integrity: every file against the manifest's sha256; broken ones are downloaded again
    set(1, 0.0);
    let dir = fixed.unwrap_or_else(|| data_dir.join("pack"));
    let mut pack = Pack::open(&dir).map_err(|e| format!("Нет данных игры: {e}"))?;
    let bad = pack.verify_with(&|f| set(1, f));
    if bad.is_empty() {
        note(1, format!("{} файлов в порядке", pack.manifest.files.len()));
    } else {
        log::warn!("integrity: {}", bad.join(", "));
        note(1, format!("повреждено файлов: {}, восстанавливаю…", bad.len()));
        let fixed = mezdu_updater::repair(&data_dir, &bad);
        pack = Pack::open(&dir).map_err(|e| e.to_string())?;
        let still = pack.verify();
        if !still.is_empty() {
            // the next start copies the pack bundled in the APK again
            let _ = std::fs::remove_file(data_dir.join("bundled.txt"));
            return Err(format!("Файлы игры повреждены ({}). Подключитесь к интернету или перезапустите приложение. {}", still.len(), fixed.err().unwrap_or_default()));
        }
        note(1, format!("восстановлено файлов: {}", bad.len()));
    }
    // 3-4. shaders for this GPU, then the world (pipelines through the on-disk cache)
    let world = mezdu_gfx::build_world(&ctx, &pack, 1, &data_dir.join("pipeline-cache"), &|stage, f| set(2 + stage as usize, f)).map_err(|e| {
        if ctx.backend == mezdu_gfx::wgpu::Backend::Gl {
            "Видеокарта без Vulkan: мир на запасном OpenGL ES пока не рисуется.".to_string()
        } else {
            format!("Мир не построился: {e}")
        }
    })?;
    note(2, format!("{} шейдеров", pack.manifest.of_kind("shader").count()));
    note(3, format!("{} участков, {} квадов", world.chunks(), world.quads));
    set(4, 1.0);
    let vox = Voxels::load(&pack).ok();
    Ok(Loaded { pack, vox, world })
}

/// the nightmare half of the logo and the hot end of the progress bar
const EMBER: egui::Color32 = egui::Color32::from_rgb(0xa8, 0x2c, 0x2a);

/// Metal of the logo, top of the letters to the bottom: a bright sky, a dark horizon a little below the middle,
/// the warm floor reflected under it (chrome). Silver is the dream, copper-crimson the nightmare.
const SILVER: [(f32, [u8; 3]); 5] = [(0.0, [0xff, 0xff, 0xff]), (0.46, [0xb8, 0xc2, 0xd0]), (0.52, [0x3c, 0x44, 0x52]), (0.62, [0x8e, 0x98, 0xa8]), (1.0, [0xe9, 0xee, 0xf5])];
const COPPER: [(f32, [u8; 3]); 5] = [(0.0, [0xff, 0xe6, 0xd2]), (0.46, [0xd8, 0x6a, 0x4c]), (0.52, [0x52, 0x10, 0x14]), (0.62, [0xa8, 0x2c, 0x2a]), (1.0, [0xff, 0x9c, 0x7a])];
/// the brass of the wheel
const BRASS: [u8; 3] = [0xc9, 0xa2, 0x5c];

fn ramp(stops: &[(f32, [u8; 3])], v: f32) -> egui::Color32 {
    let v = v.clamp(0.0, 1.0);
    let i = stops.iter().position(|s| s.0 >= v).unwrap_or(stops.len() - 1).max(1);
    let ((a, ca), (b, cb)) = (stops[i - 1], stops[i]);
    let t = ((v - a) / (b - a).max(1e-4)).clamp(0.0, 1.0);
    let l = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t) as u8;
    egui::Color32::from_rgb(l(ca[0], cb[0]), l(ca[1], cb[1]), l(ca[2], cb[2]))
}

/// brass lit from the upper left: `k` is how much a surface at angle `a` faces the light
fn brass(a: f32, alpha: f32) -> egui::Color32 {
    let k = 0.45 + 0.55 * (a + 2.3).cos().max(-0.6);
    let c = |x: u8| ((x as f32 * k * 1.25).min(255.0)) as u8;
    egui::Color32::from_rgb(c(BRASS[0]), c(BRASS[1]), c(BRASS[2])).gamma_multiply(alpha)
}

/// The wheel of samsara behind the word: a brass rim with eight knobs and eight spokes turning slowly one way,
/// a ring of marks turning the other way, a hub in the middle.
fn wheel(p: &egui::Painter, c: egui::Pos2, r: f32, t: f32) {
    let tau = std::f32::consts::TAU;
    let at = |a: f32, d: f32| c + egui::vec2(a.cos(), a.sin()) * d;
    let arc = |d: f32, w: f32, alpha: f32| {
        let n = 120;
        for i in 0..n {
            let (a0, a1) = (i as f32 / n as f32 * tau, (i + 1) as f32 / n as f32 * tau);
            p.line_segment([at(a0, d), at(a1, d)], egui::Stroke::new(w, brass((a0 + a1) * 0.5, alpha)));
        }
    };
    let rot = t * 0.22;
    p.circle_filled(c, r * 1.02, egui::Color32::from_rgba_unmultiplied(0x0a, 0x08, 0x0c, 0x90));
    arc(r, r * 0.06, 0.95);
    arc(r * 0.9, r * 0.012, 0.6);
    arc(r * 0.74, r * 0.025, 0.85);
    // the marks between the rims, against the turn
    for i in 0..48 {
        let a = i as f32 / 48.0 * tau - t * 0.11;
        let long = i % 6 == 0;
        p.line_segment([at(a, r * 0.78), at(a, r * if long { 0.88 } else { 0.84 })], egui::Stroke::new(r * 0.01, brass(a, 0.55)));
    }
    for i in 0..8 {
        let a = rot + i as f32 / 8.0 * tau;
        // a spoke: thin, swelling into a leaf before the rim
        p.line_segment([at(a, r * 0.2), at(a, r * 0.72)], egui::Stroke::new(r * 0.022, brass(a + 1.57, 0.85)));
        let (q, w) = (at(a, r * 0.56), egui::vec2(-a.sin(), a.cos()) * r * 0.045);
        p.add(egui::Shape::convex_polygon(vec![at(a, r * 0.46), q + w, at(a, r * 0.7), q - w], brass(a + 1.57, 0.8), egui::Stroke::NONE));
        // the knobs on the rim, between the spokes
        let k = a + tau / 16.0;
        p.circle_filled(at(k, r * 1.07), r * 0.045, brass(k, 0.95));
        p.circle_filled(at(k, r * 1.07) - egui::vec2(r * 0.012, r * 0.012), r * 0.015, egui::Color32::from_rgba_unmultiplied(255, 248, 230, 0xa0));
    }
    p.circle_filled(c, r * 0.2, egui::Color32::from_rgb(0x14, 0x10, 0x12));
    p.circle_stroke(c, r * 0.2, egui::Stroke::new(r * 0.035, brass(0.0, 0.95)));
    p.circle_stroke(c, r * 0.1, egui::Stroke::new(r * 0.02, brass(3.0, 0.8)));
}

/// The logo: МЕЖДУ in polished metal, cut in two along a diagonal — silver (the dream) on the upper left, copper
/// (the nightmare) on the lower right — a glint running over it now and then, and the turning wheel of samsara
/// behind it. Clip rectangles are straight, so the word is drawn in thin horizontal bands: each band has its own
/// colour of the metal and its own place of the cut and of the glint.
fn logo(ui: &mut egui::Ui, size: f32, t: f32) {
    let font = egui::FontId::proportional(size);
    let g = ui.painter().layout_no_wrap("МЕЖДУ".into(), font, egui::Color32::WHITE);
    let gs = g.size();
    let r = gs.y * 1.15;
    let (rect, _) = ui.allocate_exact_size(egui::vec2(gs.x.max(2.3 * r) + size * 0.3, 2.3 * r), egui::Sense::hover());
    let c = rect.center();
    let p = ui.painter();
    wheel(p, c, r, t);
    let pos = c - gs * 0.5;
    // letters made heavier and given an edge: the same layout drawn around a small circle
    let fat = (size * 0.022).max(1.0);
    let ring: [egui::Vec2; 8] = std::array::from_fn(|i| {
        let a = i as f32 / 8.0 * std::f32::consts::TAU;
        egui::vec2(a.cos(), a.sin()) * fat
    });
    let draw = |p: &egui::Painter, off: egui::Vec2, col: egui::Color32| {
        p.galley_with_override_text_color(pos + off, g.clone(), col);
        for o in ring {
            p.galley_with_override_text_color(pos + off + o, g.clone(), col);
        }
    };
    draw(&p.with_clip_rect(rect), egui::vec2(size * 0.03, size * 0.05), egui::Color32::from_black_alpha(0xb0));
    for o in [egui::vec2(-1.5, 0.0), egui::vec2(1.5, 0.0), egui::vec2(0.0, -1.5), egui::vec2(0.0, 1.5)] {
        draw(&p.with_clip_rect(rect), o, egui::Color32::from_rgb(0x12, 0x0e, 0x10));
    }
    // the glint crosses every 5 s, slanted the other way than the cut
    let sweep = (t % 5.0) / 1.6;
    let glint_x = |y: f32| rect.left() - 40.0 + (rect.width() + 80.0) * sweep + (y - c.y) * 0.7;
    let split_x = |y: f32| c.x - (y - c.y) * 0.55;
    let (top, h) = (pos.y + gs.y * 0.12, gs.y * 0.78);
    let n = 40;
    for i in 0..n {
        let (y0, y1) = (top + h * i as f32 / n as f32, top + h * (i + 1) as f32 / n as f32);
        let v = (i as f32 + 0.5) / n as f32;
        let ym = (y0 + y1) * 0.5;
        let xs = split_x(ym);
        let band = |x0: f32, x1: f32| p.with_clip_rect(egui::Rect::from_x_y_ranges(x0..=x1, y0..=y1 + 0.5));
        draw(&band(rect.left(), xs), egui::Vec2::ZERO, ramp(&SILVER, v));
        draw(&band(xs, rect.right()), egui::Vec2::ZERO, ramp(&COPPER, v));
        // the cut itself: a dark hairline between the metals
        draw(&band(xs - 1.0, xs + 1.0), egui::Vec2::ZERO, egui::Color32::from_rgb(0x10, 0x0c, 0x0e));
        if sweep < 1.0 {
            let xg = glint_x(ym);
            draw(&band(xg - 14.0, xg + 14.0), egui::Vec2::ZERO, egui::Color32::from_rgba_unmultiplied(255, 252, 245, 0x50));
            draw(&band(xg - 4.0, xg + 4.0), egui::Vec2::ZERO, egui::Color32::from_rgba_unmultiplied(255, 255, 255, 0xd0));
        }
    }
}

/// One loading bar for all the stages: a dark track, the done part as a gradient from the nightmare's ember to the
/// accent with a soft glow; while a stage has no measure yet a light runs along the done part.
fn progress_bar(ui: &mut egui::Ui, w: f32, frac: f32, t: f32, busy: bool) {
    let h = 6.0;
    let (r, _) = ui.allocate_exact_size(egui::vec2(w, h + 8.0), egui::Sense::hover());
    let p = ui.painter();
    let track = egui::Rect::from_center_size(r.center(), egui::vec2(w, h));
    p.rect_filled(track, h * 0.5, egui::Color32::from_rgba_unmultiplied(255, 245, 230, 0x14));
    let x1 = track.left() + w * frac.max(0.02);
    let fill = egui::Rect::from_x_y_ranges(track.left()..=x1, track.y_range());
    p.rect_filled(fill.expand(3.0), h, ACCENT.gamma_multiply(0.10));
    let mut m = egui::Mesh::default();
    for (x, c) in [(fill.left(), EMBER), (fill.right(), ACCENT)] {
        m.colored_vertex(egui::pos2(x, fill.top()), c);
        m.colored_vertex(egui::pos2(x, fill.bottom()), c);
    }
    m.add_triangle(0, 1, 2);
    m.add_triangle(1, 3, 2);
    p.with_clip_rect(fill).add(egui::Shape::mesh(m));
    p.circle_filled(egui::pos2(x1, track.center().y), h * 0.5, ACCENT);
    if busy {
        let x = fill.left() + fill.width() * (t * 0.7).fract();
        let glint = egui::Rect::from_x_y_ranges((x - 18.0).max(fill.left())..=(x + 18.0).min(fill.right()), track.y_range());
        p.rect_filled(glint, h * 0.5, egui::Color32::from_rgba_unmultiplied(255, 250, 240, 0x40));
    }
}

type LoadResult = std::sync::mpsc::Receiver<Result<Loaded, String>>;
/// stage, share done, notes: what the loading screen shows
type LoadView = (usize, f32, [String; 4]);

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Screen {
    Loading,
    Menu,
    Settings,
    Playing,
    Paused,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Action {
    NewGame,
    /// the autosave from the menu
    Continue,
    Resume,
    Settings,
    Back,
    ToMenu,
    Pause,
    UpdateApk,
    /// desktop only: Android apps are closed by the system
    #[cfg_attr(target_os = "android", allow(dead_code))]
    Quit,
}

pub struct App {
    data_dir: PathBuf,
    pack: Option<Pack>,
    window: Option<Arc<Window>>,
    gfx: Option<Gfx>,
    ui: Option<Ui>,
    world: Option<World>,
    /// the loader thread's progress and result
    loading: Option<(Arc<Mutex<LoadState>>, LoadResult)>,
    loading_frames: u32,
    load_error: Option<String>,
    /// what the last loading found: updates, integrity (shown in the menu and the settings)
    load_notes: [String; 4],
    screen: Screen,
    hero: Option<Hero>,
    cam: Camera,
    touches: HashMap<u64, (f64, f64)>,
    /// the finger the interface owns (it landed on a button or a window)
    ui_touch: Option<u64>,
    ui_mouse: bool,
    mouse: Option<(f64, f64)>,
    mouse_down: bool,
    keys: [bool; 7],
    last: Instant,
    start: Instant,
    next_frame: Instant,
    /// MEZDU_TIME=<seconds> freezes the animation clock (comparable screenshots on the desktop)
    frozen: Option<f32>,
    /// seconds of play since the last autosave
    save_t: f32,
    /// an autosave exists: «Продолжить» in the menu
    saved: bool,
    /// commit of a newer APK in the release, set by the updater thread
    apk: Arc<Mutex<Option<String>>>,
    frames: u32,
    fps_t: Instant,
    pub fps: f32,
}

impl App {
    pub fn new(data_dir: PathBuf, apk: Arc<Mutex<Option<String>>>) -> Self {
        let pack_dir = std::env::var("MEZDU_PACK").map(PathBuf::from).unwrap_or_else(|_| data_dir.join("pack"));
        let pack = match Pack::open(&pack_dir) {
            Ok(p) => {
                log::info!("pack {} ({}) from {}", p.manifest.version, &p.manifest.commit[..7.min(p.manifest.commit.len())], pack_dir.display());
                Some(p)
            }
            Err(e) => {
                log::warn!("no pack: {e}");
                None
            }
        };
        let hero = pack.as_ref().and_then(|p| match Voxels::load(p) {
            Ok(vox) => {
                let player = Player::new(&vox);
                Some(Hero { vox, player, rig: None, words: Vec::with_capacity(16 * 16), joy: None, look: [0.0; 2] })
            }
            Err(e) => {
                log::warn!("no voxels: {e}");
                None
            }
        });
        let saved = save::load(&data_dir).is_some();
        App {
            data_dir,
            pack,
            window: None,
            gfx: None,
            ui: None,
            world: None,
            loading: None,
            loading_frames: 0,
            load_error: None,
            load_notes: Default::default(),
            screen: Screen::Loading,
            hero,
            cam: Camera { pos: glam::Vec3::new(MENU_CAM[0], MENU_CAM[1], MENU_CAM[2]), yaw: MENU_CAM[3], pitch: MENU_CAM[4], fov_y: 1.0 },
            touches: HashMap::new(),
            ui_touch: None,
            ui_mouse: false,
            mouse: None,
            mouse_down: false,
            keys: [false; 7],
            last: Instant::now(),
            start: Instant::now(),
            next_frame: Instant::now(),
            frozen: std::env::var("MEZDU_TIME").ok().and_then(|v| v.parse().ok()),
            save_t: 0.0,
            saved,
            apk,
            frames: 0,
            fps_t: Instant::now(),
            fps: 0.0,
        }
    }

    fn sys_info(&self) -> String {
        let g = self.gfx.as_ref().map(|g| format!("{:?} · {}", g.backend, g.adapter_name)).unwrap_or_default();
        let p = self.pack.as_ref().map(|p| format!("пак {} · {} файлов", &p.manifest.commit[..7.min(p.manifest.commit.len())], p.manifest.files.len())).unwrap_or_else(|| "без пака".into());
        let build = if BUILD.is_empty() { "локальная" } else { BUILD };
        let upd = if self.load_notes[0].is_empty() { String::new() } else { format!("\nобновление: {} · целостность: {}", self.load_notes[0], self.load_notes[1]) };
        format!("сборка {build} · {g} · {:.0} FPS · {p}{upd}", self.fps)
    }

    fn start_loading(&mut self) {
        let Some(g) = &self.gfx else { return };
        let st = Arc::new(Mutex::new(LoadState::default()));
        let (tx, rx) = std::sync::mpsc::channel();
        let (ctx, dir, fixed, st2) = (g.ctx(), self.data_dir.clone(), std::env::var_os("MEZDU_PACK").map(PathBuf::from), st.clone());
        let _ = std::thread::Builder::new().name("loader".into()).spawn(move || {
            let _ = tx.send(load(ctx, dir, fixed, st2));
        });
        self.loading = Some((st, rx));
        self.loading_frames = 0;
        self.load_error = None;
    }

    /// takes the loader's result when it is ready
    fn poll_loading(&mut self) {
        let Some((_, rx)) = &self.loading else { return };
        let Ok(r) = rx.try_recv() else { return };
        if let Some(n) = self.loading.as_ref().and_then(|(s, _)| s.lock().ok().map(|s| s.notes.clone())) {
            self.load_notes = n;
        }
        self.loading = None;
        match r {
            Ok(l) => {
                log::info!("loaded: pack {} · quality {:?}", &l.pack.manifest.commit[..7.min(l.pack.manifest.commit.len())], l.world.quality);
                match (&mut self.hero, l.vox) {
                    (Some(h), Some(v)) => h.vox = v,
                    (None, Some(vox)) => {
                        let player = Player::new(&vox);
                        self.hero = Some(Hero { vox, player, rig: None, words: Vec::with_capacity(16 * 16), joy: None, look: [0.0; 2] });
                    }
                    _ => {}
                }
                if let Some(h) = &mut self.hero {
                    h.rig = RigModels::find("hero", &l.world.model_names());
                }
                self.pack = Some(l.pack);
                self.world = Some(l.world);
                if self.screen == Screen::Loading {
                    self.screen = Screen::Menu;
                    // the system closed the app during a game: it opens there again, paused
                    if save::load(&self.data_dir).is_some_and(|s| s.playing) && self.restore() {
                        self.screen = Screen::Paused;
                    }
                    // this library started and built the world: the launcher keeps it (crates/launcher)
                    let _ = std::fs::remove_file(self.data_dir.join("code").join("booting"));
                }
            }
            Err(e) => {
                log::error!("loading: {e}");
                self.load_error = Some(e);
                self.screen = Screen::Loading;
            }
        }
    }

    fn act(&mut self, a: Action, el: &ActiveEventLoop) {
        match a {
            Action::NewGame => {
                if let Some(h) = &mut self.hero {
                    // MEZDU_HERO=x,z (metres): desktop check of a place in the world
                    let at = std::env::var("MEZDU_HERO").ok().and_then(|v| {
                        let (x, z) = v.split_once(',')?;
                        Some((x.parse::<f32>().ok()?, z.parse::<f32>().ok()?))
                    });
                    let (x, z) = at.unwrap_or((SPAWN[0], SPAWN[2]));
                    h.player.spawn(&h.vox, x, z, SPAWN[1], SPAWN[3]);
                    log::info!("new game: hero at {:.2?}", h.player.pos);
                    self.screen = Screen::Playing;
                }
            }
            Action::Continue => {
                if self.restore() {
                    self.screen = Screen::Playing;
                }
            }
            Action::Resume => self.screen = Screen::Playing,
            Action::Pause => {
                self.screen = Screen::Paused;
                self.autosave();
            }
            Action::Settings => self.screen = Screen::Settings,
            Action::Back | Action::ToMenu => {
                if matches!(self.screen, Screen::Playing | Screen::Paused) {
                    self.autosave_as(false);
                }
                self.screen = Screen::Menu;
                self.cam = Camera { pos: glam::Vec3::new(MENU_CAM[0], MENU_CAM[1], MENU_CAM[2]), yaw: MENU_CAM[3], pitch: MENU_CAM[4], fov_y: 1.0 };
            }
            Action::UpdateApk => {
                #[cfg(target_os = "android")]
                if let Some(app) = ANDROID.get() {
                    // SAFETY: pointers of the running activity, valid while the app runs
                    if let Err(e) = unsafe { url::open(app.vm_as_ptr(), app.activity_as_ptr(), mezdu_updater::APK_URL) } {
                        log::error!("open url: {e}");
                    }
                }
                #[cfg(not(target_os = "android"))]
                log::info!("new APK: {}", mezdu_updater::APK_URL);
            }
            Action::Quit => el.exit(),
        }
        self.joystick_reset();
    }

    /// the hero where the autosave left him; false without a save or a hero
    fn restore(&mut self) -> bool {
        let (Some(s), Some(h)) = (save::load(&self.data_dir), &mut self.hero) else { return false };
        h.player.place(s.pos[0], s.pos[1], s.pos[2], s.yaw);
        h.player.cam_yaw = s.cam_yaw;
        h.player.cam_pitch = s.cam_pitch;
        log::info!("autosave: hero at {:.2?}", s.pos);
        true
    }

    fn autosave(&mut self) {
        if matches!(self.screen, Screen::Playing | Screen::Paused) {
            self.autosave_as(true);
        }
    }

    fn autosave_as(&mut self, playing: bool) {
        self.save_t = 0.0;
        if let Some(h) = &self.hero {
            let p = &h.player;
            save::store(&self.data_dir, &save::Save { pos: p.pos, yaw: p.yaw, cam_yaw: p.cam_yaw, cam_pitch: p.cam_pitch, playing });
            self.saved = true;
        }
    }

    fn joystick_reset(&mut self) {
        if let Some(h) = &mut self.hero {
            h.joy = None;
            h.look = [0.0; 2];
        }
        self.touches.clear();
        self.mouse_down = false;
    }

    /// the interface of the current screen; returns what the player pressed
    #[allow(clippy::too_many_arguments)]
    fn layout(ctx: &egui::Context, screen: Screen, saved: bool, info: &str, err: Option<&str>, apk: Option<&str>, joy: Option<(egui::Pos2, egui::Pos2)>, load: (f32, Option<&LoadView>), out: &mut Vec<Action>) {
        let big = |ui: &mut egui::Ui, text: &str, enabled: bool, act: Action, out: &mut Vec<Action>| {
            let b = egui::Button::new(egui::RichText::new(text).size(19.0).strong()).min_size(egui::vec2(260.0, 50.0));
            if ui.add_enabled(enabled, b).clicked() {
                out.push(act);
            }
        };
        let shade = |ctx: &egui::Context, a: u8| {
            ctx.layer_painter(egui::LayerId::background()).rect_filled(ctx.content_rect(), 0.0, egui::Color32::from_rgba_unmultiplied(0x0d, 0x0b, 0x10, a));
        };
        match screen {
            Screen::Loading => {
                shade(ctx, 255);
                egui::Area::new(egui::Id::unique("loading")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).order(egui::Order::Background).show(ctx, |ui| {
                    let w = 360.0;
                    ui.set_width(w);
                    ui.vertical_centered(|ui| {
                        logo(ui, 62.0, load.0);
                        ui.add_space(30.0);
                        let (stage, frac, notes) = load.1.map_or((STAGES.len(), 1.0, Default::default()), |(a, b, c)| (*a, *b, c.clone()));
                        // one line over one bar: the stage, and what it is doing now
                        let i = stage.min(STAGES.len() - 1);
                        let status = if notes[i].is_empty() { STAGES[i].to_string() } else { format!("{} · {}", STAGES[i], notes[i]) };
                        ui.label(egui::RichText::new(status).size(14.0).color(INK.gamma_multiply(0.8)));
                        ui.add_space(8.0);
                        let all = ((stage as f32 + frac.clamp(0.0, 1.0)) / STAGES.len() as f32).clamp(0.0, 1.0);
                        progress_bar(ui, w, all, load.0, err.is_none() && frac < 0.001);
                        if let Some(e) = err {
                            ui.add_space(12.0);
                            ui.label(egui::RichText::new(e).size(14.0).color(egui::Color32::from_rgb(0xe0, 0x50, 0x3f)));
                        }
                    });
                });
            }
            Screen::Menu => {
                // the village shows through on the right, as the web menu over its scene
                let r = ctx.content_rect();
                let mut m = egui::Mesh::default();
                let dark = egui::Color32::from_rgba_premultiplied(0x0b, 0x09, 0x0d, 0xd8);
                let clear = egui::Color32::TRANSPARENT;
                let x1 = r.left() + r.width() * 0.62;
                for (x, c) in [(r.left(), dark), (r.left() + r.width() * 0.25, dark), (x1, clear)] {
                    m.colored_vertex(egui::pos2(x, r.top()), c);
                    m.colored_vertex(egui::pos2(x, r.bottom()), c);
                }
                m.add_triangle(0, 1, 2);
                m.add_triangle(1, 3, 2);
                m.add_triangle(2, 3, 4);
                m.add_triangle(3, 5, 4);
                ctx.layer_painter(egui::LayerId::background()).add(egui::Shape::mesh(m));
                egui::Area::new(egui::Id::unique("menu")).anchor(egui::Align2::LEFT_CENTER, egui::vec2(48.0, 0.0)).show(ctx, |ui| {
                    ui.label(egui::RichText::new("воксельный психологический триллер").size(14.0).color(ACCENT));
                    logo(ui, 52.0, load.0);
                    ui.label(egui::RichText::new("Мир помнит то, что ты забыл.").size(16.0).italics().color(INK.gamma_multiply(0.75)));
                    ui.add_space(22.0);
                    if saved {
                        big(ui, "Продолжить", true, Action::Continue, out);
                    }
                    big(ui, "Начать игру", true, Action::NewGame, out);
                    big(ui, "Настройки", true, Action::Settings, out);
                    #[cfg(not(target_os = "android"))]
                    big(ui, "Выход", true, Action::Quit, out);
                    if let Some(c) = apk {
                        ui.add_space(16.0);
                        ui.label(egui::RichText::new(format!("Доступна новая версия приложения ({c})")).color(ACCENT));
                        big(ui, "Скачать и установить", true, Action::UpdateApk, out);
                    }
                });
                egui::Area::new(egui::Id::unique("foot")).anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-20.0, -14.0)).order(egui::Order::Background).show(ctx, |ui| {
                    ui.with_layout(egui::Layout::top_down(egui::Align::RIGHT), |ui| {
                        ui.label(egui::RichText::new(info).size(11.0).color(INK.gamma_multiply(0.6)));
                    });
                });
            }
            Screen::Settings => {
                shade(ctx, 0xb0);
                egui::Area::new(egui::Id::unique("settings")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).show(ctx, |ui| {
                    egui::Frame::window(ui.style()).inner_margin(28.0).corner_radius(18.0).show(ui, |ui| {
                        ui.label(egui::RichText::new("Настройки").size(28.0).strong());
                        ui.add_space(8.0);
                        ui.label("Качество подобрано под Redmi 10S: 30 кадров в секунду, тени, туман, отражения и сглаживание как в веб-версии.");
                        ui.label("Обновления игры скачиваются сами, пока есть интернет, и ставятся при следующем входе в игру.");
                        ui.add_space(8.0);
                        ui.label(egui::RichText::new(info).size(12.0).color(INK.gamma_multiply(0.6)));
                        ui.add_space(14.0);
                        big(ui, "Назад", true, Action::Back, out);
                    });
                });
            }
            Screen::Playing => {
                egui::Area::new(egui::Id::unique("pause")).anchor(egui::Align2::RIGHT_TOP, egui::vec2(-18.0, 18.0)).show(ctx, |ui| {
                    let b = egui::Button::new("").min_size(egui::vec2(52.0, 52.0)).corner_radius(26.0);
                    let r = ui.add(b);
                    // the pause sign: two bars (the font has no glyph for it)
                    let c = r.rect.center();
                    for dx in [-5.5, 5.5] {
                        ui.painter().rect_filled(egui::Rect::from_center_size(c + egui::vec2(dx, 0.0), egui::vec2(5.0, 18.0)), 1.5, INK);
                    }
                    if r.clicked() {
                        out.push(Action::Pause);
                    }
                });
                if let Some((c, k)) = joy {
                    let p = ctx.layer_painter(egui::LayerId::background());
                    let r = 52.0;
                    let d = k - c;
                    let k = c + if d.length() > r { d * (r / d.length()) } else { d };
                    p.circle(c, r, egui::Color32::from_rgba_unmultiplied(13, 11, 16, 60), egui::Stroke::new(1.5, egui::Color32::from_rgba_unmultiplied(242, 200, 121, 110)));
                    p.circle_filled(k, 22.0, egui::Color32::from_rgba_unmultiplied(242, 200, 121, 120));
                }
            }
            Screen::Paused => {
                shade(ctx, 0xa0);
                egui::Area::new(egui::Id::unique("paused")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).show(ctx, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(egui::RichText::new("Пауза").size(36.0).strong());
                        ui.add_space(16.0);
                        big(ui, "Продолжить", true, Action::Resume, out);
                        big(ui, "Настройки", true, Action::Settings, out);
                        big(ui, "В главное меню", true, Action::ToMenu, out);
                    });
                });
            }
        }
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        let window = match &self.window {
            Some(w) => w.clone(),
            None => {
                let w = Arc::new(el.create_window(Window::default_attributes().with_title("МЕЖДУ")).expect("window"));
                self.window = Some(w.clone());
                w
            }
        };
        let size = window.inner_size();
        // back from the background: the device, the world and the interface are still here, only the surface is new
        if let Some(g) = &mut self.gfx {
            match g.resume(window.clone(), size.width, size.height) {
                Ok(()) => {
                    log::info!("resumed: {:?}", self.screen);
                    self.last = Instant::now();
                    window.request_redraw();
                    return;
                }
                Err(e) => {
                    log::warn!("resume: {e}; the device is created again");
                    self.world = None;
                    self.ui = None;
                    self.gfx = None;
                }
            }
        }
        match Gfx::new(window.clone(), size.width, size.height) {
            Ok(g) => {
                self.ui = Some(Ui::new(&g.device, g.config.format, window.scale_factor() as f32));
                self.gfx = Some(g);
                self.start_loading();
                if self.screen == Screen::Playing {
                    self.screen = Screen::Paused; // back from the background: the game waits
                }
                if self.screen != Screen::Paused {
                    self.screen = Screen::Loading;
                }
            }
            Err(e) => log::error!("no GPU device: {e}"),
        }
        log::info!("data dir {}", self.data_dir.display());
        window.request_redraw();
    }

    /// QUALITY.fps = 30: one frame every 33 ms, the event loop sleeps in between (battery); vsync alone would draw 60
    fn about_to_wait(&mut self, el: &ActiveEventLoop) {
        if self.gfx.as_ref().is_none_or(|g| g.surface.is_none()) {
            el.set_control_flow(ControlFlow::Wait);
            return;
        }
        let now = Instant::now();
        if now >= self.next_frame {
            self.next_frame = (self.next_frame + FRAME).max(now);
            if let Some(w) = &self.window {
                w.request_redraw();
            }
        }
        el.set_control_flow(ControlFlow::WaitUntil(self.next_frame));
    }

    // Android destroys the native window in the background: only the surface goes (rendering stops: battery); the
    // world stays in memory and the game continues where it was. If the system closes the app, the autosave does.
    fn suspended(&mut self, _el: &ActiveEventLoop) {
        if let Some(g) = &mut self.gfx {
            g.suspend();
        }
        self.autosave();
        if self.screen == Screen::Playing {
            self.screen = Screen::Paused;
        }
        self.joystick_reset();
    }

    fn window_event(&mut self, el: &ActiveEventLoop, _id: WindowId, ev: WindowEvent) {
        match ev {
            WindowEvent::CloseRequested => el.exit(),
            WindowEvent::Resized(s) => {
                if let Some(g) = &mut self.gfx {
                    g.resize(s.width, s.height);
                }
            }
            WindowEvent::Touch(t) => self.touch(t),
            WindowEvent::MouseInput { state, button: MouseButton::Left, .. } => {
                let (x, y) = self.mouse.unwrap_or_default();
                let down = state == ElementState::Pressed;
                let to_ui = if down { self.screen != Screen::Playing || self.ui.as_ref().is_some_and(|u| u.covers(x, y)) } else { self.ui_mouse };
                if to_ui {
                    self.ui_mouse = down;
                    if let Some(u) = &mut self.ui {
                        u.pointer(x, y, if down { Phase::Down } else { Phase::Up });
                    }
                } else {
                    self.mouse_down = down;
                }
            }
            WindowEvent::CursorMoved { position, .. } => {
                if let (Some((x, y)), true) = (self.mouse, self.mouse_down) {
                    self.look(position.x - x, position.y - y);
                }
                self.mouse = Some((position.x, position.y));
                if let Some(u) = &mut self.ui {
                    u.pointer(position.x, position.y, Phase::Move);
                }
            }
            WindowEvent::KeyboardInput { event, .. } => {
                if event.physical_key == PhysicalKey::Code(KeyCode::Escape) && event.state == ElementState::Pressed {
                    match self.screen {
                        Screen::Playing => self.act(Action::Pause, el),
                        Screen::Paused => self.act(Action::Resume, el),
                        Screen::Settings => self.act(Action::Back, el),
                        _ => {}
                    }
                    return;
                }
                let k = match event.physical_key {
                    PhysicalKey::Code(KeyCode::KeyW) => 0,
                    PhysicalKey::Code(KeyCode::KeyS) => 1,
                    PhysicalKey::Code(KeyCode::KeyA) => 2,
                    PhysicalKey::Code(KeyCode::KeyD) => 3,
                    PhysicalKey::Code(KeyCode::KeyE) => 4,
                    PhysicalKey::Code(KeyCode::KeyQ) => 5,
                    PhysicalKey::Code(KeyCode::ShiftLeft) => 6,
                    _ => return,
                };
                self.keys[k] = event.state == ElementState::Pressed;
            }
            WindowEvent::RedrawRequested => self.redraw(el),
            _ => {}
        }
    }
}

impl App {
    fn redraw(&mut self, el: &ActiveEventLoop) {
        let dt = self.last.elapsed().as_secs_f32().min(0.1);
        self.last = Instant::now();
        self.poll_loading();
        self.loading_frames += 1;
        let time = self.frozen.unwrap_or_else(|| self.start.elapsed().as_secs_f32());
        let size = self.window.as_ref().map(|w| w.inner_size()).unwrap_or_default();
        let mut focus = self.cam.pos;
        let playing = self.screen == Screen::Playing;
        let k = |i: usize| if self.keys[i] { 1.0 } else { 0.0 };
        let (fw, st) = (k(0) - k(1), k(3) - k(2));
        let ppp = self.ui.as_ref().map_or(1.0, |u| u.ppp);
        let mut joy_vis = None;
        if let Some(h) = &mut self.hero {
            if matches!(self.screen, Screen::Playing | Screen::Paused) {
                let mut mv = [st, fw];
                if let Some((_, s0, s1)) = h.joy {
                    // full speed at 9 % of the short side from where the finger landed
                    let r = (size.width.min(size.height) as f64 * 0.09).max(1.0);
                    let (x, y) = (((s1.0 - s0.0) / r) as f32, (-(s1.1 - s0.1) / r) as f32);
                    let l = x.hypot(y).max(1.0);
                    mv = [x / l, y / l];
                    joy_vis = Some((egui::pos2(s0.0 as f32 / ppp, s0.1 as f32 / ppp), egui::pos2(s1.0 as f32 / ppp, s1.1 as f32 / ppp)));
                }
                if playing {
                    self.save_t += dt;
                    let inp = Input { mv, look: h.look, run: self.keys[6] };
                    h.look = [0.0; 2];
                    h.player.update(dt, &inp, &h.vox);
                    h.player.update_camera(dt, &inp, &h.vox, size.height > size.width);
                }
                let (p, t) = (glam::Vec3::from(h.player.cam_pos), glam::Vec3::from(h.player.cam_target));
                let f = (t - p).normalize_or(glam::Vec3::NEG_Z);
                self.cam = Camera { pos: p, yaw: f.x.atan2(-f.z), pitch: f.y.clamp(-1.0, 1.0).asin(), fov_y: self.cam.fov_y };
                let pp = h.player.pos;
                focus = glam::Vec3::new(pp[0], h.player.vis_y, pp[2]);
            }
            if let (Some(rig), Some(w), Some(g)) = (&h.rig, &mut self.world, &self.gfx) {
                h.words.clear();
                if matches!(self.screen, Screen::Playing | Screen::Paused) {
                    write_rig(&mut h.words, rig, focus.to_array(), h.player.yaw, h.player.walking && playing, h.player.phase, h.player.speed, time);
                }
                w.set_dynamic(&g.queue, &h.words);
            }
        }
        if playing && self.save_t >= save::AUTOSAVE {
            self.autosave();
        }
        if matches!(self.screen, Screen::Menu | Screen::Settings) {
            // the menu's view drifts a little, as a camera on a tripod in the wind
            self.cam.yaw = MENU_CAM[3] + (time * 0.07).sin() * 0.06;
        }
        let info = self.sys_info();
        let apk = self.apk.lock().ok().and_then(|a| a.clone());
        let (screen, err, saved) = (self.screen, self.load_error.clone(), self.saved);
        let lt = self.loading_frames as f32 / 30.0;
        let ls = self.loading.as_ref().and_then(|(s, _)| s.lock().ok().map(|s| (s.stage, s.frac, s.notes.clone())));
        let mut actions = Vec::new();
        let (Some(g), Some(ui)) = (&mut self.gfx, &mut self.ui) else { return };
        let world = if screen == Screen::Loading { None } else { self.world.as_mut() };
        g.render(world, &self.cam, focus, time, SKY, |d, q, enc, view, w, h| {
            ui.frame(d, q, enc, view, w, h, |ctx| Self::layout(ctx, screen, saved, &info, err.as_deref(), apk.as_deref(), joy_vis, (lt, ls.as_ref()), &mut actions));
        });
        for a in actions {
            self.act(a, el);
        }
        self.frames += 1;
        let el_t = self.fps_t.elapsed().as_secs_f32();
        if el_t >= 2.0 {
            self.fps = self.frames as f32 / el_t;
            self.frames = 0;
            self.fps_t = Instant::now();
            match &self.world {
                Some(w) => log::info!("{:?} · {} · {} quads, {} instances, {} draws · hero {:.2?}", self.screen, self.sys_info(), w.quads, w.instances, w.calls, self.hero.as_ref().map(|h| h.player.pos)),
                None => log::info!("{:?} · {}", self.screen, self.sys_info()),
            }
        }
    }

    fn look(&mut self, dx: f64, dy: f64) {
        if self.screen != Screen::Playing {
            return;
        }
        if let Some(h) = &mut self.hero {
            h.look[0] += dx as f32;
            h.look[1] += dy as f32;
        }
    }

    /// A finger on a button or window belongs to the interface; in the game a finger landing on the left 45 % of
    /// the screen is the joystick, any other finger looks around.
    fn touch(&mut self, t: Touch) {
        let p = (t.location.x, t.location.y);
        let width = self.window.as_ref().map_or(1, |w| w.inner_size().width) as f64;
        if t.phase == TouchPhase::Started && self.ui_touch.is_none() && (self.screen != Screen::Playing || self.ui.as_ref().is_some_and(|u| u.covers(p.0, p.1))) {
            self.ui_touch = Some(t.id);
        }
        if self.ui_touch == Some(t.id) {
            let ph = match t.phase {
                TouchPhase::Started => Phase::Down,
                TouchPhase::Moved => Phase::Move,
                _ => Phase::Up,
            };
            if let Some(u) = &mut self.ui {
                u.pointer(p.0, p.1, ph);
            }
            if ph == Phase::Up {
                self.ui_touch = None;
            }
            return;
        }
        if self.screen != Screen::Playing {
            return;
        }
        let Some(h) = &mut self.hero else { return };
        match t.phase {
            TouchPhase::Started if h.joy.is_none() && p.0 < width * 0.45 => h.joy = Some((t.id, p, p)),
            TouchPhase::Moved if h.joy.is_some_and(|j| j.0 == t.id) => {
                if let Some(j) = &mut h.joy {
                    j.2 = p;
                }
            }
            TouchPhase::Ended | TouchPhase::Cancelled if h.joy.is_some_and(|j| j.0 == t.id) => h.joy = None,
            TouchPhase::Started => {
                self.touches.insert(t.id, p);
            }
            TouchPhase::Moved => {
                if let Some(old) = self.touches.insert(t.id, p) {
                    self.look(p.0 - old.0, p.1 - old.1);
                }
            }
            TouchPhase::Ended | TouchPhase::Cancelled => {
                self.touches.remove(&t.id);
            }
        }
    }
}

#[cfg(target_os = "android")]
static ANDROID: std::sync::OnceLock<winit::platform::android::activity::AndroidApp> = std::sync::OnceLock::new();

/// commit of this build (set by CI for the APK; empty in local builds: no APK update check)
pub const BUILD: &str = match option_env!("MEZDU_BUILD") {
    Some(b) => b,
    None => "",
};

/// ABI of the downloadable game library (release "app": libmezdu-<abi>.so.zst); none on the desktop
pub const ABI: Option<&str> = if cfg!(not(target_os = "android")) {
    None
} else if cfg!(target_arch = "aarch64") {
    Some("arm64-v8a")
} else if cfg!(target_arch = "x86_64") {
    Some("x86_64")
} else {
    None
};

pub fn run(event_loop: EventLoop<()>, data_dir: PathBuf) {
    event_loop.set_control_flow(ControlFlow::Wait);
    let apk = Arc::new(Mutex::new(None));
    // the pack in the data dir is checked against the release in the background; with MEZDU_PACK (a pack picked
    // by hand on the desktop) nothing is downloaded
    if std::env::var_os("MEZDU_PACK").is_none() {
        mezdu_updater::install_staged(&data_dir);
        let (dir, slot) = (data_dir.clone(), apk.clone());
        let _ = std::thread::Builder::new().name("updater".into()).spawn(move || {
            mezdu_updater::watch(dir, BUILD, ABI, move |c| {
                log::info!("a newer APK ({c}) is available");
                if let Ok(mut s) = slot.lock() {
                    *s = Some(c);
                }
            });
        });
    }
    let mut app = App::new(data_dir, apk);
    if let Err(e) = event_loop.run_app(&mut app) {
        log::error!("event loop: {e}");
    }
}

/// Copies the pack bundled in the APK (assets/pack) into the data dir once per bundled commit (after an install or
/// an update of the APK); a pack downloaded by the updater afterwards is never overwritten by the older bundled one.
#[cfg(target_os = "android")]
fn install_bundled_pack(app: &winit::platform::android::activity::AndroidApp, data_dir: &std::path::Path) {
    use std::io::Read;
    let am = app.asset_manager();
    let read = |p: &str| -> Option<Vec<u8>> {
        let name = std::ffi::CString::new(format!("pack/{p}")).ok()?;
        let mut a = am.open(&name)?;
        let mut v = Vec::new();
        a.read_to_end(&mut v).ok()?;
        Some(v)
    };
    let Some(json) = read("manifest.json") else { return };
    let Ok(m) = mezdu_core::Manifest::parse(&json) else { return };
    let dst = data_dir.join("pack");
    let mark = data_dir.join("bundled.txt");
    let installed_once = std::fs::read_to_string(&mark).map(|c| c.trim() == m.commit).unwrap_or(false);
    if installed_once && Pack::open(&dst).is_ok() {
        return;
    }
    let tmp = data_dir.join("pack.tmp");
    let _ = std::fs::remove_dir_all(&tmp);
    let write = |rel: &str, d: &[u8]| -> std::io::Result<()> {
        let f = tmp.join(rel);
        std::fs::create_dir_all(f.parent().unwrap_or(&tmp))?;
        std::fs::write(f, d)
    };
    for f in &m.files {
        match read(&f.path) {
            Some(d) if write(&f.path, &d).is_ok() => {}
            _ => log::warn!("bundled pack: {} missing", f.path),
        }
    }
    if write("manifest.json", &json).is_ok() {
        let _ = std::fs::remove_dir_all(&dst);
        match std::fs::rename(&tmp, &dst) {
            Ok(()) => {
                let _ = std::fs::write(&mark, &m.commit);
                log::info!("bundled pack {} installed", m.version);
            }
            Err(e) => log::error!("bundled pack: {e}"),
        }
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    use winit::platform::android::EventLoopBuilderExtAndroid;
    android_logger::init_once(android_logger::Config::default().with_max_level(log::LevelFilter::Info).with_tag("mezdu"));
    let data_dir = app.internal_data_path().unwrap_or_else(|| PathBuf::from("/data/local/tmp/mezdu"));
    mezdu_updater::install_staged(&data_dir);
    install_bundled_pack(&app, &data_dir);
    let _ = ANDROID.set(app.clone());
    let el = EventLoop::builder().with_android_app(app).build().expect("event loop");
    run(el, data_dir);
}
