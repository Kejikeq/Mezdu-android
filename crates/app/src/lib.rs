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
use std::rc::Rc;
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
    /// shared with the story scripts (they ask about walls); the story's world edits write into it
    vox: Rc<std::cell::RefCell<Voxels>>,
    player: Player,
    rig: Option<RigModels>,
    words: Vec<u32>,
    /// on-screen joystick: touch id, where it started, where it is
    joy: Option<Joystick>,
    look: [f32; 2],
}

/// The voxels as the story scripts ask about them (mezdu_script::World).
struct VoxWorld(Rc<std::cell::RefCell<Voxels>>);
impl mezdu_script::World for VoxWorld {
    fn solid(&self, x: i32, y: i32, z: i32, w: u8) -> bool {
        self.0.borrow().solid_in(x, y, z, w == 1)
    }
    fn hazard(&self, x: f32, y: f32, z: f32, w: u8) -> bool {
        self.0.borrow().hazard_m(x, y, z, w == 1)
    }
    fn ground(&self, x: f32, z: f32) -> f32 {
        let v = self.0.borrow();
        let (ix, iz) = ((x / v.vs).floor() as i32, (z / v.vs).floor() as i32);
        (1..v.wy).rev().find(|&y| v.solid(ix, y - 1, iz)).map_or(0.0, |y| y as f32 * v.vs)
    }
}

/// The story's worlds as the scene takes them (crates/gfx WorldFrame).
fn world_frame(ws: &mezdu_script::WorldState) -> mezdu_gfx::world::WorldFrame {
    mezdu_gfx::world::WorldFrame {
        blur: ws.headache,
        night_share: ws.night_share,
        wave_c: ws.wave_c,
        wave_r: ws.wave_r,
        wave_from: ws.wave_from,
        wave_to: ws.wave_to,
        wave_active: ws.wave_active,
        base: ws.base,
        wave2_c: ws.wave2_c,
        wave2_r: ws.wave2_r,
        cull: ws.cull,
    }
}

/// A window of the story over the game: a text to read or a thing found, answered by a button.
#[derive(Clone)]
enum Panel {
    Read { id: u32, title: String, paras: Vec<String>, night: bool },
    Inspect { id: u32, kicker: String, title: String, desc: String, buttons: Vec<(String, serde_json::Value)> },
    /// a conversation with a witness (story/dialogue.js)
    Dialog { id: u32, role: String, name: String, context: String, speech: String, questions: Vec<(String, bool)>, testimony: mezdu_script::Testimony },
}

/// the buttons of a conversation beside its questions (Action::Answer indices)
const DIALOG_RECORD: usize = 1000;
const DIALOG_LEAVE: usize = 1001;

/// What the story shows over the game.
#[derive(Default)]
struct Hud {
    /// the line being said: who, what, until when (seconds of the clock)
    say: Option<(String, String, f32)>,
    objective: String,
    /// the action button: what it does here ("" = nothing near)
    prompt: String,
    panel: Option<Panel>,
    /// «вглядеться» offered (Some(on) when offered: the button shows whether it is on)
    eye: Option<bool>,
    /// a cinematic or a collapse holds the hero
    locked: bool,
    /// the screen's darkness (main.js fade): now, where it goes, how fast (per second)
    fade: f32,
    fade_to: f32,
    fade_speed: f32,
    /// the backpack as the scripts keep it, and the item looked at
    items: Vec<mezdu_script::Item>,
    sel: usize,
    /// the story's colliders by id: box and whether it blocks
    colliders: HashMap<u32, ([f32; 6], bool)>,
    /// the story's figures (G.figures): model index per list entry (u32::MAX: not in the pack), where they stand
    fig_models: Vec<u32>,
    figs: Vec<mezdu_script::Figure>,
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

/// What the updater found for the player, shared by the loader, the watch thread and the interface.
#[derive(Default)]
struct Updates {
    /// a newer APK must be installed (a newer launcher is needed)
    apk: Option<String>,
    /// a newer game library is downloaded: «для применения обновления требуется перезапуск»
    code: Option<String>,
}

type SharedUpdates = Arc<Mutex<Updates>>;

fn found(up: &SharedUpdates, f: mezdu_updater::Found) {
    if let Ok(mut u) = up.lock() {
        match f {
            mezdu_updater::Found::Apk(b) => u.apk = Some(b),
            mezdu_updater::Found::Code(b) => u.code = Some(b),
        }
    }
}

/// The loader thread: updates, integrity, shaders, world. Nothing in it touches the window.
fn load(ctx: mezdu_gfx::DeviceCtx, data_dir: PathBuf, fixed: Option<PathBuf>, st: Arc<Mutex<LoadState>>, up: SharedUpdates) -> Result<Loaded, String> {
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
        match mezdu_updater::check_code(&data_dir, abi, BUILD, &|done, total| {
            set(0, done as f32 / total.max(1) as f32);
            note(0, format!("программа: {} из {}", mb(done), mb(total)));
        }) {
            Ok(mezdu_updater::CodeOutcome::Staged { build, .. }) => {
                // the player is asked once the menu is up (this build is known to work by then)
                note(0, format!("программа {build} скачана"));
                found(&up, mezdu_updater::Found::Code(build));
            }
            Ok(mezdu_updater::CodeOutcome::NeedApk { build }) => {
                note(0, format!("{prev}; программа {build} требует установить новый APK"));
                found(&up, mezdu_updater::Found::Apk(build));
            }
            Ok(mezdu_updater::CodeOutcome::UpToDate) => note(0, prev),
            Err(e) => {
                log::warn!("code update: {e}");
                note(0, prev);
            }
        }
    }
    // every stage ends with a full bar, shown for a moment
    let done = |stage: usize| {
        set(stage, 1.0);
        std::thread::sleep(std::time::Duration::from_millis(150));
    };
    done(0);
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
    done(1);
    // 3-4. shaders for this GPU, then the world (pipelines through the on-disk cache)
    let world = mezdu_gfx::build_world(&ctx, &pack, 1, &data_dir.join("pipeline-cache"), &|stage, f| set(2 + stage as usize, f)).map_err(|e| {
        if ctx.backend == mezdu_gfx::wgpu::Backend::Gl {
            "Видеокарта без Vulkan: мир на запасном OpenGL ES пока не рисуется.".to_string()
        } else {
            format!("Мир не построился: {e}")
        }
    })?;
    note(2, format!("{} шейдеров", pack.manifest.of_kind("shader").count()));
    done(3);
    note(3, format!("{} участков, {} квадов", world.chunks(), world.quads));
    set(4, 1.0);
    let vox = Voxels::load(&pack).ok();
    Ok(Loaded { pack, vox, world })
}

/// the nightmare half of the logo and the hot end of the progress bar
const EMBER: egui::Color32 = egui::Color32::from_rgb(0xc8, 0x46, 0x5e);

/// The letters of the logo on a pixel grid, 11 rows each, strokes two pixels thick ('#' = a pixel).
const GLYPHS: [&[&str]; 5] = [
    // М: two posts, the V between them reaching the middle
    &["##.....##", "###...###", "####.####", "##.###.##", "##..#..##", "##.....##", "##.....##", "##.....##", "##.....##", "##.....##", "##.....##"],
    // Е: the middle bar a little shorter than the others
    &["#######", "#######", "##.....", "##.....", "######.", "######.", "##.....", "##.....", "##.....", "#######", "#######"],
    // Ж: a stem, two arms up, two arms down
    &["##...##...##", "##...##...##", ".##..##..##.", "..##.##.##..", "...######...", "....####....", "...######...", "..##.##.##..", ".##..##..##.", "##...##...##", "##...##...##"],
    // Д: a roof, a slanting left side, the base with two feet
    &["...######.", "...######.", "...##..##.", "...##..##.", "..##...##.", "..##...##.", ".##....##.", "##########", "##########", "##......##", "##......##"],
    // У: two arms, the right one going on down to the lower left
    &["##.....##", "##.....##", ".##...##.", ".##...##.", "..##.##..", "..##.##..", "...###...", "...##....", "..##.....", "###......", "##......."],
];
/// Where Ж tears, row by row: pixels from this column on are the nightmare's. It runs along the rising arms, between
/// the two pixels of each, and steps down through the stem — each arm splits lengthwise into a gold and a red half.
const ZH_TEAR: [usize; 11] = [11, 11, 10, 9, 7, 6, 5, 3, 2, 1, 1];
/// blank pixels between letters (the wide spacing of the web title)
const TRACK: usize = 3;
/// the dream's gold and the nightmare's crimson, top row → bottom row
const GOLD: [[u8; 3]; 2] = [[0xf3, 0xd3, 0x8c], [0xb8, 0x86, 0x3c]];
const CRIMSON: [[u8; 3]; 2] = [[0xe8, 0x6a, 0x80], [0x96, 0x26, 0x3e]];

fn shade(c: [[u8; 3]; 2], v: f32, k: f32) -> egui::Color32 {
    let l = |a: u8, b: u8| ((a as f32 + (b as f32 - a as f32) * v) * k).clamp(0.0, 255.0) as u8;
    egui::Color32::from_rgb(l(c[0][0], c[1][0]), l(c[0][1], c[1][1]), l(c[0][2], c[1][2]))
}

/// The logo: МЕЖДУ in pixels, as the web title. Ж is torn along its rising diagonal (ZH_TEAR): the gold of the dream (М, Е and
/// the upper left of Ж) is lifted by a pixel, the crimson of the nightmare (the lower right of Ж, Д, У) let down by a
/// pixel: along the stepped tear the halves no longer meet. Every pixel is lit from above (a light top edge, a
/// dark bottom edge, a hard shadow), and a glint runs over the word now and then.
fn logo(ui: &mut egui::Ui, size: f32, t: f32) {
    let ppp = ui.ctx().pixels_per_point();
    // whole screen pixels per logo pixel: crisp edges
    let px = ((size / 11.0) * ppp).round().max(2.0) / ppp;
    let cols: usize = GLYPHS.iter().map(|g| g[0].len()).sum::<usize>() + TRACK * (GLYPHS.len() - 1);
    let (rect, _) = ui.allocate_exact_size(egui::vec2(cols as f32 * px, 15.0 * px), egui::Sense::hover());
    let p = ui.painter();
    let o = rect.min + egui::vec2(0.0, 2.0 * px);
    // the glint: a slanted band crossing every 6 s
    let sweep = (t % 6.0) / 1.4;
    for pass in 0..2 {
        let mut x0 = 0usize;
        for (li, g) in GLYPHS.iter().enumerate() {
            let w = g[0].len();
            for (y, row) in g.iter().enumerate() {
                for (x, ch) in row.bytes().enumerate() {
                    if ch != b'#' {
                        continue;
                    }
                    // which side of the tear: Ж is cut along x + y·w/11 = w (lower left → upper right)
                    let night = match li {
                        0 | 1 => false,
                        2 => x >= ZH_TEAR[y],
                        _ => true,
                    };
                    let lift = if night { 1.0 } else { -1.0 };
                    let at = o + egui::vec2((x0 + x) as f32 * px, (y as f32 + lift) * px);
                    let cell = egui::Rect::from_min_size(at, egui::vec2(px, px));
                    if pass == 0 {
                        // the hard shadow, down and to the right
                        p.rect_filled(cell.translate(egui::vec2(px * 0.6, px * 0.8)), 0.0, egui::Color32::from_black_alpha(0xa0));
                        continue;
                    }
                    let filled = |dy: i32| {
                        let yy = y as i32 + dy;
                        yy >= 0 && (yy as usize) < g.len() && g[yy as usize].as_bytes().get(x) == Some(&b'#')
                    };
                    let v = y as f32 / 10.0;
                    let pal = if night { CRIMSON } else { GOLD };
                    p.rect_filled(cell, 0.0, shade(pal, v, 1.0));
                    let e = (px * 0.25).max(1.0 / ppp);
                    if !filled(-1) {
                        p.rect_filled(egui::Rect::from_min_size(at, egui::vec2(px, e)), 0.0, shade(pal, v, 1.25));
                    }
                    if !filled(1) {
                        p.rect_filled(egui::Rect::from_min_size(at + egui::vec2(0.0, px - e), egui::vec2(px, e)), 0.0, shade(pal, v, 0.6));
                    }
                    if sweep < 1.0 {
                        let gx = sweep * (cols as f32 + 22.0) - 11.0 + y as f32 * 0.6;
                        let d = ((x0 + x) as f32 - gx).abs();
                        if d < 1.6 {
                            p.rect_filled(cell, 0.0, egui::Color32::from_rgba_unmultiplied(255, 250, 235, ((1.6 - d) / 1.6 * 150.0) as u8));
                        }
                    }
                }
            }
            x0 += w + TRACK;
        }
    }
}

/// The loading bar of the current stage (it starts again with every stage): a dark track, the done part as a gradient from the nightmare's ember to the
/// accent with a soft glow; while a stage has no measure yet a light runs along the done part.
fn progress_bar(ui: &mut egui::Ui, w: f32, frac: f32, t: f32, busy: bool) {
    let h = 6.0;
    let (r, _) = ui.allocate_exact_size(egui::vec2(w, h + 8.0), egui::Sense::hover());
    let p = ui.painter();
    let track = egui::Rect::from_center_size(r.center(), egui::vec2(w, h));
    p.rect_filled(track, h * 0.5, egui::Color32::from_rgba_unmultiplied(255, 245, 230, 0x14));
    let x1 = track.left() + w * frac.max(0.02);
    let fill = egui::Rect::from_x_y_ranges(track.left()..=x1, track.y_range());
    p.rect_filled(fill.expand(3.0), h, EMBER.gamma_multiply(0.12));
    let mut m = egui::Mesh::default();
    for (x, c) in [(fill.left(), ACCENT), (fill.right(), EMBER)] {
        m.colored_vertex(egui::pos2(x, fill.top()), c);
        m.colored_vertex(egui::pos2(x, fill.bottom()), c);
    }
    m.add_triangle(0, 1, 2);
    m.add_triangle(1, 3, 2);
    p.with_clip_rect(fill).add(egui::Shape::mesh(m));
    p.circle_filled(egui::pos2(x1, track.center().y), h * 0.5, EMBER);
    if busy {
        let x = fill.left() + fill.width() * (t * 0.7).fract();
        let glint = egui::Rect::from_x_y_ranges((x - 18.0).max(fill.left())..=(x + 18.0).min(fill.right()), track.y_range());
        p.rect_filled(glint, h * 0.5, egui::Color32::from_rgba_unmultiplied(255, 250, 240, 0x40));
    }
}

/// The story over the game: the objective, the backpack button, the line being said, the action button and the
/// story's windows (a text to read, a thing found).
fn story_hud(ctx: &egui::Context, hud: &Hud, out: &mut Vec<Action>) {
    if hud.fade > 0.001 {
        ctx.layer_painter(egui::LayerId::background()).rect_filled(ctx.content_rect(), 0.0, egui::Color32::from_black_alpha((hud.fade * 255.0) as u8));
    }
    if !hud.objective.is_empty() {
        egui::Area::new(egui::Id::unique("objective")).anchor(egui::Align2::LEFT_TOP, egui::vec2(18.0, 34.0)).order(egui::Order::Background).show(ctx, |ui| {
            ui.set_max_width(320.0);
            ui.label(egui::RichText::new("цель").size(11.0).color(ACCENT));
            ui.label(egui::RichText::new(&hud.objective).size(13.0).color(INK.gamma_multiply(0.85)));
        });
    }
    let sw = ctx.content_rect().width();
    // «вглядеться»: offered by the story; the label says whether the eye is on (main.js ui.eye)
    if let Some(on) = hud.eye.filter(|_| hud.panel.is_none()) {
        egui::Area::new(egui::Id::unique("eye")).anchor(egui::Align2::RIGHT_TOP, egui::vec2(-146.0, 18.0)).show(ctx, |ui| {
            let b = egui::Button::new(egui::RichText::new(if on { "Не смотреть" } else { "Вглядеться" }).size(12.0).color(if on { ACCENT } else { INK })).min_size(egui::vec2(124.0, 36.0)).wrap_mode(egui::TextWrapMode::Extend).corner_radius(18.0);
            if ui.add(b).clicked() {
                out.push(Action::Eye);
            }
        });
    }
    // the backpack: a bag drawn by hand, with the count of things not looked at yet (not while a window is open)
    egui::Area::new(egui::Id::unique("bag")).anchor(egui::Align2::RIGHT_TOP, egui::vec2(-82.0, 18.0)).enabled(hud.panel.is_none()).show(ctx, |ui| {
        let r = ui.add(egui::Button::new("").min_size(egui::vec2(52.0, 52.0)).corner_radius(26.0));
        let (c, p) = (r.rect.center(), ui.painter());
        p.rect_stroke(egui::Rect::from_center_size(c + egui::vec2(0.0, 3.0), egui::vec2(20.0, 16.0)), 4.0, egui::Stroke::new(2.0, INK), egui::StrokeKind::Middle);
        p.rect_stroke(egui::Rect::from_center_size(c + egui::vec2(0.0, -7.0), egui::vec2(9.0, 6.0)), 3.0, egui::Stroke::new(2.0, INK), egui::StrokeKind::Middle);
        let new = hud.items.iter().filter(|i| !i.seen).count();
        if new > 0 {
            let b = r.rect.right_top() + egui::vec2(-8.0, 8.0);
            p.circle_filled(b, 9.0, EMBER);
            p.text(b, egui::Align2::CENTER_CENTER, new.to_string(), egui::FontId::proportional(11.0), INK);
        }
        if r.clicked() {
            out.push(Action::OpenBag);
        }
    });
    if let Some((who, text, _)) = &hud.say {
        egui::Area::new(egui::Id::unique("say")).anchor(egui::Align2::CENTER_BOTTOM, egui::vec2(0.0, -22.0)).order(egui::Order::Background).interactable(false).show(ctx, |ui| {
            egui::Frame::new().fill(egui::Color32::from_rgba_unmultiplied(10, 8, 12, 0xb0)).corner_radius(12.0).inner_margin(egui::Margin::symmetric(16, 8)).show(ui, |ui| {
                ui.set_max_width((sw - 64.0).min(560.0));
                if !who.is_empty() {
                    ui.label(egui::RichText::new(who).size(12.0).color(ACCENT));
                }
                ui.label(egui::RichText::new(text).size(15.0).color(INK));
            });
        });
    }
    if !hud.prompt.is_empty() && hud.panel.is_none() {
        egui::Area::new(egui::Id::unique("use")).anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-24.0, -96.0)).show(ctx, |ui| {
            ui.spacing_mut().button_padding = egui::vec2(16.0, 8.0);
            let b = egui::Button::new(egui::RichText::new(&hud.prompt).size(14.0).color(INK)).wrap().corner_radius(16.0).min_size(egui::vec2(200.0, 44.0));
            ui.set_max_width(300.0);
            if ui.add(b).clicked() {
                out.push(Action::Use);
            }
        });
    }
    let Some(panel) = &hud.panel else { return };
    ctx.layer_painter(egui::LayerId::new(egui::Order::Middle, egui::Id::unique("panel dim"))).rect_filled(ctx.content_rect(), 0.0, egui::Color32::from_black_alpha(0x90));
    egui::Area::new(egui::Id::unique("panel")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).order(egui::Order::Foreground).show(ctx, |ui| {
        egui::Frame::window(ui.style()).inner_margin(20.0).corner_radius(18.0).show(ui, |ui| {
            ui.set_width((sw - 72.0).min(440.0));
            ui.spacing_mut().button_padding = egui::vec2(14.0, 4.0);
            match panel {
                Panel::Read { id, title, paras, night } => {
                    if !title.is_empty() {
                        ui.label(egui::RichText::new(title).size(13.0).color(if *night { EMBER } else { ACCENT }));
                    }
                    egui::ScrollArea::vertical().max_height(230.0).show(ui, |ui| {
                        for p in paras {
                            ui.label(egui::RichText::new(p).size(15.0).color(INK));
                        }
                    });
                    ui.add_space(6.0);
                    if ui.add(egui::Button::new(egui::RichText::new("Закрыть").size(15.0)).min_size(egui::vec2(140.0, 32.0))).clicked() {
                        out.push(Action::Answer(*id, 0));
                    }
                }
                Panel::Dialog { id, role, name, context, speech, questions, testimony } => {
                    ui.label(egui::RichText::new(role).size(11.0).color(ACCENT));
                    ui.label(egui::RichText::new(name).size(19.0).strong());
                    egui::ScrollArea::vertical().max_height(260.0).show(ui, |ui| {
                        ui.label(egui::RichText::new(context).size(13.0).italics().color(INK.gamma_multiply(0.7)));
                        egui::Frame::new().fill(egui::Color32::from_rgba_unmultiplied(25, 33, 48, 0xc0)).corner_radius(8.0).inner_margin(egui::Margin::symmetric(12, 8)).show(ui, |ui| {
                            ui.label(egui::RichText::new(speech).size(14.0).color(INK));
                        });
                        ui.add_space(4.0);
                        ui.label(egui::RichText::new("Вопросы для выяснения правды:").size(11.0).color(INK.gamma_multiply(0.55)));
                        for (k, (q, asked)) in questions.iter().enumerate() {
                            // (the interface font has no ✓ / ▸ of the web: asked ones are grey and marked in words)
                            let t = if *asked { egui::RichText::new(format!("— {q} (спрошено)")).size(13.0).color(INK.gamma_multiply(0.55)) } else { egui::RichText::new(format!("— {q}")).size(13.0).color(ACCENT) };
                            if ui.add(egui::Button::new(t).wrap().min_size(egui::vec2(ui.available_width(), 30.0))).clicked() {
                                out.push(Action::Answer(*id, k));
                            }
                        }
                    });
                    ui.add_space(6.0);
                    ui.horizontal(|ui| {
                        match testimony {
                            mezdu_script::Testimony::Offer => {
                                if ui.add(egui::Button::new(egui::RichText::new("Записать показание").size(14.0).color(ACCENT)).min_size(egui::vec2(170.0, 32.0))).clicked() {
                                    out.push(Action::Answer(*id, DIALOG_RECORD));
                                }
                            }
                            mezdu_script::Testimony::Recorded => {
                                ui.label(egui::RichText::new("Показание записано").size(13.0).color(INK.gamma_multiply(0.6)));
                            }
                            mezdu_script::Testimony::None => {}
                        }
                        if ui.add(egui::Button::new(egui::RichText::new("Отойти").size(14.0)).min_size(egui::vec2(110.0, 32.0))).clicked() {
                            out.push(Action::Answer(*id, DIALOG_LEAVE));
                        }
                    });
                }
                Panel::Inspect { id, kicker, title, desc, buttons } => {
                    if !kicker.is_empty() {
                        ui.label(egui::RichText::new(kicker).size(12.0).color(ACCENT));
                    }
                    ui.label(egui::RichText::new(title).size(19.0).strong());
                    egui::ScrollArea::vertical().max_height(180.0).show(ui, |ui| {
                        ui.label(egui::RichText::new(desc).size(14.0).color(INK.gamma_multiply(0.85)));
                    });
                    ui.add_space(6.0);
                    ui.horizontal(|ui| {
                        for (k, (label, _)) in buttons.iter().enumerate() {
                            let t = egui::RichText::new(label).size(15.0);
                            let t = if k == 0 { t.color(ACCENT) } else { t };
                            if ui.add(egui::Button::new(t).min_size(egui::vec2(120.0, 32.0))).clicked() {
                                out.push(Action::Answer(*id, k));
                            }
                        }
                    });
                }
            }
        });
    });
}

/// The backpack (the inventory of the web game): the things on the left, the one picked on the right.
fn bag(ctx: &egui::Context, hud: &Hud, out: &mut Vec<Action>) {
    let w = (ctx.content_rect().width() - 60.0).min(600.0);
    egui::Area::new(egui::Id::unique("bag screen")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).show(ctx, |ui| {
        egui::Frame::window(ui.style()).inner_margin(18.0).corner_radius(18.0).show(ui, |ui| {
            ui.set_width(w);
            ui.label(egui::RichText::new("Вещи").size(22.0).strong());
            if hud.items.is_empty() {
                ui.label(egui::RichText::new("Пока пусто. Найденное ляжет сюда.").size(14.0).color(INK.gamma_multiply(0.6)));
            } else {
                ui.horizontal_top(|ui| {
                    ui.vertical(|ui| {
                        ui.set_width(w * 0.38);
                        egui::ScrollArea::vertical().id_salt("items").max_height(240.0).show(ui, |ui| {
                            for (i, it) in hud.items.iter().enumerate() {
                                let t = egui::RichText::new(if it.seen { it.name.clone() } else { format!("{} (новое)", it.name) }).size(13.0);
                                let t = if i == hud.sel { t.color(ACCENT) } else { t };
                                if ui.add(egui::Button::new(t).wrap().min_size(egui::vec2(w * 0.36, 30.0))).clicked() {
                                    out.push(Action::Item(i));
                                }
                            }
                        });
                    });
                    if let Some(it) = hud.items.get(hud.sel) {
                        ui.vertical(|ui| {
                            ui.set_width(w * 0.58);
                            egui::ScrollArea::vertical().id_salt("item").max_height(240.0).show(ui, |ui| {
                                ui.label(egui::RichText::new(&it.name).size(17.0).strong());
                                ui.label(egui::RichText::new(&it.desc).size(14.0).color(INK.gamma_multiply(0.85)));
                                if !it.hint.is_empty() {
                                    ui.add_space(4.0);
                                    ui.label(egui::RichText::new(&it.hint).size(12.0).italics().color(ACCENT.gamma_multiply(0.85)));
                                }
                            });
                        });
                    }
                });
            }
            ui.add_space(6.0);
            back(ui, out);
        });
    });
}

/// the compact «Назад» of the settings and the slot screens
fn back(ui: &mut egui::Ui, out: &mut Vec<Action>) {
    let b = egui::Button::new(egui::RichText::new("Назад").size(15.0)).min_size(egui::vec2(160.0, 32.0));
    if ui.add(b).clicked() {
        out.push(Action::Back);
    }
}

/// One slot as loadPanel draws it: the number large on the left, the chapter and the details beside it; true when
/// tapped.
fn slot_row(ui: &mut egui::Ui, label: &str, title: &str, meta: &str, enabled: bool) -> bool {
    let sense = if enabled { egui::Sense::click() } else { egui::Sense::hover() };
    let (rect, resp) = ui.allocate_exact_size(egui::vec2(300.0, 46.0), sense);
    let v = if enabled { ui.style().interact(&resp) } else { &ui.style().visuals.widgets.noninteractive };
    let p = ui.painter();
    p.rect(rect, 14.0, v.bg_fill, v.bg_stroke, egui::StrokeKind::Inside);
    let fade = if enabled { 1.0 } else { 0.45 };
    let left = rect.left() + 18.0;
    p.text(egui::pos2(left, rect.center().y), egui::Align2::LEFT_CENTER, label, egui::FontId::proportional(22.0), ACCENT.gamma_multiply(fade));
    p.text(egui::pos2(left + 34.0, rect.top() + 15.0), egui::Align2::LEFT_CENTER, title, egui::FontId::proportional(15.0), INK.gamma_multiply(fade));
    p.text(egui::pos2(left + 34.0, rect.bottom() - 13.0), egui::Align2::LEFT_CENTER, meta, egui::FontId::proportional(12.0), INK.gamma_multiply(0.55 * fade));
    enabled && resp.clicked()
}

/// A question over the menu or the pause: the update windows.
struct Prompt {
    title: &'static str,
    text: String,
    yes: (&'static str, Action),
    no: (&'static str, Action),
}

/// what the slot screens and the menu show of the saves
struct SlotsView<'a> {
    rows: &'a [Option<(String, String)>; 4],
    confirm: Option<usize>,
    toast: Option<&'a str>,
    fps: f32,
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
    /// the slots to load from (from the menu or the pause)
    Load,
    /// the slots 1-3 to save into (from the pause)
    Save,
    /// the backpack (from the game or the pause)
    Bag,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Action {
    NewGame,
    /// the newest save from the menu
    Continue,
    OpenLoad,
    OpenSave,
    /// a slot picked on the Load or the Save screen (index in save::SLOTS)
    Slot(usize),
    AskDelete(usize),
    Delete(usize),
    CancelDelete,
    /// the restart window: start the app again on the new game library / not now
    Restart,
    Later,
    /// «Нет» on the new-APK window
    ApkLater,
    /// the action button of the story (what the prompt says)
    Use,
    /// a story window closed by its button (window id, button)
    Answer(u32, usize),
    OpenBag,
    /// an item picked in the backpack
    Item(usize),
    /// «вглядеться» (the eye button)
    Eye,
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
    /// the web game's story scripts from the pack (crates/script)
    script: Option<mezdu_script::Script>,
    hud: Hud,
    /// where the backpack returns to (the game or the pause)
    bag_back: Screen,
    cam: Camera,
    touches: HashMap<u64, (f64, f64)>,
    /// the finger the interface owns (it landed on a button or a window)
    ui_touch: Option<u64>,
    ui_mouse: bool,
    mouse: Option<(f64, f64)>,
    mouse_down: bool,
    keys: [bool; 8],
    /// «вглядеться» pressed since the last frame (R or the eye button): one toggle, as the web's eyeTap
    eye_tap: bool,
    last: Instant,
    start: Instant,
    next_frame: Instant,
    /// MEZDU_TIME=<seconds> freezes the animation clock (comparable screenshots on the desktop)
    frozen: Option<f32>,
    /// seconds of play since the last autosave
    save_t: f32,
    /// the saves on disk, read when they change: what the menu and the slot screens show
    slots: [Option<save::Save>; 4],
    /// the same as text: (title, details) of every filled slot
    slot_rows: [Option<(String, String)>; 4],
    /// the slot whose deletion waits for «Да»
    confirm: Option<usize>,
    /// where Back leads from the settings and the slot screens
    back_to: Screen,
    /// seconds of play in this game
    playtime: f64,
    settings: save::Settings,

    /// a short message at the top («Сохранено») and when it was shown
    toast: Option<(String, Instant)>,
    /// commit of a newer APK in the release, set by the updater thread
    updates: SharedUpdates,
    /// «Позже» on the restart window: not asked again in this run
    update_later: bool,
    /// «Нет» on the new-APK window: the menu still has its button
    apk_later: bool,
    frames: u32,
    fps_t: Instant,
    pub fps: f32,
}

impl App {
    fn new(data_dir: PathBuf, updates: SharedUpdates) -> Self {
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
                Some(Hero { vox: Rc::new(std::cell::RefCell::new(vox)), player, rig: None, words: Vec::with_capacity(16 * mezdu_gfx::props::DYN), joy: None, look: [0.0; 2] })
            }
            Err(e) => {
                log::warn!("no voxels: {e}");
                None
            }
        });
        let settings = save::read_settings(&data_dir);
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
            script: None,
            hud: Hud::default(),
            bag_back: Screen::Playing,
            cam: Camera { pos: glam::Vec3::new(MENU_CAM[0], MENU_CAM[1], MENU_CAM[2]), yaw: MENU_CAM[3], pitch: MENU_CAM[4], fov_y: 1.0 },
            touches: HashMap::new(),
            ui_touch: None,
            ui_mouse: false,
            mouse: None,
            mouse_down: false,
            keys: [false; 8],
            eye_tap: false,
            last: Instant::now(),
            start: Instant::now(),
            next_frame: Instant::now(),
            frozen: std::env::var("MEZDU_TIME").ok().and_then(|v| v.parse().ok()),
            save_t: 0.0,
            slots: [None; 4],
            slot_rows: Default::default(),
            confirm: None,
            back_to: Screen::Menu,
            playtime: 0.0,
            toast: None,
            settings,
            updates,
            update_later: false,
            apk_later: false,
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
        let (ctx, dir, fixed, st2, up) = (g.ctx(), self.data_dir.clone(), std::env::var_os("MEZDU_PACK").map(PathBuf::from), st.clone(), self.updates.clone());
        let _ = std::thread::Builder::new().name("loader".into()).spawn(move || {
            let _ = tx.send(load(ctx, dir, fixed, st2, up));
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
                    (Some(h), Some(v)) => h.vox = Rc::new(std::cell::RefCell::new(v)),
                    (None, Some(vox)) => {
                        let player = Player::new(&vox);
                        self.hero = Some(Hero { vox: Rc::new(std::cell::RefCell::new(vox)), player, rig: None, words: Vec::with_capacity(16 * mezdu_gfx::props::DYN), joy: None, look: [0.0; 2] });
                    }
                    _ => {}
                }
                if let Some(h) = &mut self.hero {
                    h.rig = RigModels::find("hero", &l.world.model_names());
                }
                // the story: the pack's scripts over these voxels
                self.script = match (&self.hero, &l.pack) {
                    (Some(h), p) => match mezdu_script::sources(p).and_then(|src| mezdu_script::Script::new(src, Rc::new(VoxWorld(h.vox.clone())))) {
                        Ok(s) => Some(s),
                        Err(e) => {
                            log::warn!("story: {e}");
                            None
                        }
                    },
                    _ => None,
                };
                self.pack = Some(l.pack);
                self.world = Some(l.world);
                if self.screen == Screen::Loading {
                    self.screen = Screen::Menu;
                    // the menu first, always: «Продолжить» leads back into the game
                    self.refresh_slots();
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
                    h.player.spawn(&h.vox.borrow(), x, z, SPAWN[1], SPAWN[3]);
                    log::info!("new game: hero at {:.2?}", h.player.pos);
                    self.screen = Screen::Playing;
                    self.playtime = 0.0;
                }
                self.hud = Hud::default();
                if let Some(sc) = &self.script {
                    sc.new_game();
                }
                self.story_events();
            }
            Action::Continue => {
                if let Some((slot, s)) = save::latest(&self.data_dir) {
                    self.apply(slot, &s);
                    self.screen = Screen::Playing;
                }
            }
            Action::OpenLoad | Action::OpenSave => {
                self.refresh_slots();
                self.remember_back();
                self.confirm = None;
                self.screen = if a == Action::OpenLoad { Screen::Load } else { Screen::Save };
            }
            Action::Slot(i) => {
                let slot = save::SLOTS[i];
                match self.screen {
                    Screen::Load => {
                        if let Some(s) = self.slots[i] {
                            log::info!("load slot {slot}");
                            self.apply(slot, &s);
                            self.screen = Screen::Playing;
                        }
                    }
                    Screen::Save if i > 0 => {
                        if self.write_slot_as(slot, true) {
                            self.toast = Some(("Сохранено".into(), Instant::now()));
                        }
                        self.screen = Screen::Paused;
                    }
                    _ => {}
                }
            }
            Action::Use => {
                if let (Some(sc), None) = (&self.script, &self.hud.panel) {
                    sc.act();
                }
                self.story_events();
            }
            Action::Answer(id, k) => {
                let v = match &self.hud.panel {
                    Some(Panel::Inspect { id: pid, buttons, .. }) if *pid == id => buttons.get(k).map(|b| b.1.clone()).unwrap_or(serde_json::Value::Bool(false)),
                    Some(Panel::Dialog { id: pid, .. }) if *pid == id => match k {
                        DIALOG_RECORD => serde_json::json!({ "record": true }),
                        DIALOG_LEAVE => serde_json::json!({ "leave": true }),
                        k => serde_json::json!({ "ask": k }),
                    },
                    _ => serde_json::Value::Bool(true),
                };
                self.hud.panel = None;
                if let Some(sc) = &self.script {
                    sc.answer(id, &v);
                }
                self.story_events();
            }
            Action::Eye => self.eye_tap = true,
            Action::OpenBag => {
                if let Some(sc) = &self.script {
                    self.hud.items = sc.inventory();
                }
                self.hud.sel = self.hud.sel.min(self.hud.items.len().saturating_sub(1));
                self.bag_back = if self.screen == Screen::Paused { Screen::Paused } else { Screen::Playing };
                self.screen = Screen::Bag;
                self.mark_seen();
            }
            Action::Item(i) => {
                self.hud.sel = i;
                self.mark_seen();
            }
            Action::Later => self.update_later = true,
            Action::ApkLater => self.apk_later = true,
            Action::Restart => {
                self.autosave();
                #[cfg(target_os = "android")]
                if let Some(app) = ANDROID.get() {
                    // SAFETY: pointers of the running activity, valid while the app runs
                    if let Err(e) = unsafe { url::restart(app.vm_as_ptr(), app.activity_as_ptr()) } {
                        log::error!("restart: {e}");
                    }
                }
                #[cfg(not(target_os = "android"))]
                log::info!("restart: start the game again for the new build");
                self.update_later = true;
            }
            Action::AskDelete(i) => self.confirm = Some(i),
            Action::CancelDelete => self.confirm = None,
            Action::Delete(i) => {
                save::delete(&self.data_dir, save::SLOTS[i]);
                save::delete_story(&self.data_dir, save::SLOTS[i]);
                self.confirm = None;
                self.refresh_slots();
            }
            Action::Resume => self.screen = Screen::Playing,
            Action::Pause => {
                self.screen = Screen::Paused;
                self.autosave();
            }
            Action::Settings => {
                self.remember_back();
                self.screen = Screen::Settings;
            }
            Action::Back if self.screen == Screen::Bag => self.screen = self.bag_back,
            // from the settings or the slots: where they were opened
            Action::Back if self.back_to == Screen::Paused => self.screen = Screen::Paused,
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

    /// the item looked at in the backpack is no longer new
    fn mark_seen(&mut self) {
        if let (Some(sc), Some(it)) = (&self.script, self.hud.items.get_mut(self.hud.sel)) {
            if !it.seen {
                sc.seen(&it.id);
                it.seen = true;
            }
        }
    }

    /// What the story said since the last frame: lines, the objective, the action button, its windows, props and
    /// the hero's moves.
    fn story_events(&mut self) {
        let Some(sc) = &self.script else { return };
        let now = self.start.elapsed().as_secs_f32();
        for e in sc.drain() {
            use mezdu_script::Event as E;
            match e {
                E::Say { text, dur, who } => self.hud.say = Some((who, text, now + dur)),
                E::Objective(t) => self.hud.objective = t,
                E::Toast(t) => self.toast = Some((t, Instant::now())),
                E::Prompt { label, .. } => self.hud.prompt = label,
                E::Read { id, title, paras, night } => self.hud.panel = Some(Panel::Read { id, title, paras, night }),
                E::Inspect { id, kicker, title, desc, buttons, .. } => self.hud.panel = Some(Panel::Inspect { id, kicker, title, desc, buttons }),
                E::Dialog { id, role, name, context, speech, questions, testimony } => self.hud.panel = Some(Panel::Dialog { id, role, name, context, speech, questions, testimony }),
                E::Prop { model, pos, on } => {
                    if let (Some(w), Some(g)) = (&mut self.world, &self.gfx) {
                        w.set_prop_visible(&g.queue, &model, pos, on);
                    }
                }
                E::Teleport { pos, yaw, safe } => {
                    if let Some(h) = &mut self.hero {
                        if safe {
                            // placeSafe: the ground under (x, z) near the hint where the whole body fits
                            let vox = h.vox.clone();
                            h.player.spawn(&vox.borrow(), pos[0], pos[2], pos[1] + 1.0, yaw);
                        } else {
                            h.player.place(pos[0], pos[1], pos[2], yaw);
                        }
                    }
                }
                E::Fade { to, dur } => {
                    self.hud.fade_to = to.clamp(0.0, 1.0);
                    self.hud.fade_speed = (self.hud.fade_to - self.hud.fade).abs() / dur.max(0.01);
                }
                E::Move { model, home, to, yaw } => {
                    if let (Some(w), Some(g)) = (&mut self.world, &self.gfx) {
                        w.move_prop(&g.queue, &model, home, to, yaw);
                    }
                }
                E::Collider { id, aabb, on } => {
                    self.hud.colliders.insert(id, (aabb, on));
                    if let Some(h) = &mut self.hero {
                        h.player.colliders.clear();
                        h.player.colliders.extend(self.hud.colliders.values().filter(|c| c.1).map(|c| c.0));
                    }
                }
                E::Edit { name, on } => {
                    if let (Some(w), Some(p)) = (&mut self.world, &self.pack) {
                        w.set_edit(&name, on);
                        if let (Some(h), Ok(e)) = (&self.hero, p.read_data(&format!("edit/{name}.vox.zst")).and_then(|b| mezdu_core::EditBox::parse(&b))) {
                            h.vox.borrow_mut().apply_edit(&e, on);
                        }
                    }
                }
                E::Inventory => self.hud.items = sc.inventory(),
                E::Menu => self.screen = Screen::Menu,
                E::Figures(models) => {
                    let names = self.world.as_ref().map(|w| w.model_names()).unwrap_or_default();
                    self.hud.fig_models = models.iter().map(|m| names.iter().position(|n| n == m).map_or(u32::MAX, |i| i as u32)).collect();
                    if let Some(m) = models.iter().zip(&self.hud.fig_models).find(|(_, &i)| i == u32::MAX) {
                        log::warn!("figure model {} is not in the pack", m.0);
                    }
                }
                // the mind gave out: the collapse back to the road is not ported yet (the hero stays where he is)
                E::Collapse => log::warn!("stability 0: the collapse to the road is not ported yet"),
            }
        }
    }

    /// where Back returns from the settings or the slots: only the menu or the pause count (a tap that arrives
    /// twice must not make the settings their own way back)
    fn remember_back(&mut self) {
        if matches!(self.screen, Screen::Menu | Screen::Paused) {
            self.back_to = self.screen;
        }
    }

    /// the game where a save left it
    fn apply(&mut self, slot: &str, s: &save::Save) {
        // the story first: its restore may move the hero, the save's place wins
        self.hud = Hud::default();
        if let Some(sc) = &self.script {
            match save::read_story(&self.data_dir, slot) {
                Some(j) => sc.restore(&j),
                None => sc.new_game(),
            }
        }
        self.story_events();
        if let Some(h) = &mut self.hero {
            h.player.place(s.pos[0], s.pos[1], s.pos[2], s.yaw);
            h.player.cam_yaw = s.cam_yaw;
            h.player.cam_pitch = s.cam_pitch;
            // the camera behind him at once (it follows smoothly, and a paused game would not move it)
            for _ in 0..30 {
                h.player.update_camera(0.1, &Input::default(), &h.vox.borrow(), false);
            }
            log::info!("save: hero at {:.2?}", s.pos);
        }
        self.playtime = s.playtime;
        self.save_t = 0.0;
    }

    fn autosave(&mut self) {
        if matches!(self.screen, Screen::Playing | Screen::Paused) {
            self.autosave_as(true);
        }
    }

    fn autosave_as(&mut self, playing: bool) {
        self.save_t = 0.0;
        self.write_slot_as("auto", playing);
    }

    fn write_slot_as(&mut self, slot: &str, playing: bool) -> bool {
        let Some(h) = &self.hero else { return false };
        let p = &h.player;
        let s = save::Save { pos: p.pos, yaw: p.yaw, cam_yaw: p.cam_yaw, cam_pitch: p.cam_pitch, playing, chapter: 1, playtime: self.playtime, time: save::now() };
        let ok = save::write(&self.data_dir, slot, &s);
        if let Some(sc) = &self.script {
            save::write_story(&self.data_dir, slot, &sc.serialize());
        }
        self.refresh_slots();
        ok
    }

    /// reads the slots again (after a write or a deletion, never every frame)
    fn refresh_slots(&mut self) {
        for (i, slot) in save::SLOTS.iter().enumerate() {
            self.slots[i] = save::read(&self.data_dir, slot);
            self.slot_rows[i] = self.slots[i].map(|s| (format!("Глава {}", s.chapter), format!("{} · {}", save::fmt_playtime(s.playtime), save::fmt_date(s.time))));
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
    fn layout(ctx: &egui::Context, screen: Screen, hud: &Hud, sv: &SlotsView, st: &mut save::Settings, prompt: Option<&Prompt>, info: &str, err: Option<&str>, apk: Option<&str>, joy: Option<(egui::Pos2, egui::Pos2)>, load: (f32, Option<&LoadView>), out: &mut Vec<Action>) {
        let shade = |ctx: &egui::Context, a: u8| {
            ctx.layer_painter(egui::LayerId::background()).rect_filled(ctx.content_rect(), 0.0, egui::Color32::from_rgba_unmultiplied(0x0d, 0x0b, 0x10, a));
        };
        if let Some(pr) = prompt {
            ctx.layer_painter(egui::LayerId::new(egui::Order::Foreground, egui::Id::unique("dim"))).rect_filled(ctx.content_rect(), 0.0, egui::Color32::from_black_alpha(0x90));
            egui::Area::new(egui::Id::unique("update")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).order(egui::Order::Tooltip).show(ctx, |ui| {
                egui::Frame::window(ui.style()).inner_margin(20.0).corner_radius(18.0).show(ui, |ui| {
                    ui.set_width(340.0);
                    ui.label(egui::RichText::new(pr.title).size(20.0).strong());
                    ui.label(egui::RichText::new(&pr.text).size(14.0).color(INK.gamma_multiply(0.8)));
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        ui.spacing_mut().button_padding = egui::vec2(14.0, 4.0);
                        let go = egui::Button::new(egui::RichText::new(pr.yes.0).size(15.0).color(ACCENT)).min_size(egui::vec2(170.0, 32.0));
                        if ui.add(go).clicked() {
                            out.push(pr.yes.1);
                        }
                        if ui.add(egui::Button::new(egui::RichText::new(pr.no.0).size(15.0)).min_size(egui::vec2(110.0, 32.0))).clicked() {
                            out.push(pr.no.1);
                        }
                    });
                });
            });
            return;
        }
        if let Some(t) = sv.toast {
            egui::Area::new(egui::Id::unique("toast")).anchor(egui::Align2::CENTER_TOP, egui::vec2(0.0, 24.0)).order(egui::Order::Foreground).show(ctx, |ui| {
                egui::Frame::window(ui.style()).inner_margin(egui::Margin::symmetric(22, 10)).corner_radius(255).show(ui, |ui| {
                    ui.label(egui::RichText::new(t).size(16.0).color(ACCENT));
                });
            });
        }
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
                        let n = STAGES.len();
                        let status = if notes[i].is_empty() { format!("{}/{n} · {}", i + 1, STAGES[i]) } else { format!("{}/{n} · {} · {}", i + 1, STAGES[i], notes[i]) };
                        ui.label(egui::RichText::new(status).size(14.0).color(INK.gamma_multiply(0.8)));
                        ui.add_space(8.0);
                        // the bar runs from the start to the end within every stage
                        let cur = if stage >= STAGES.len() { 1.0 } else { frac.clamp(0.0, 1.0) };
                        progress_bar(ui, w, cur, load.0, err.is_none() && cur < 0.001);
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
                    // compact: a phone in landscape has about 390 points of height
                    ui.spacing_mut().item_spacing.y = 6.0;
                    ui.spacing_mut().button_padding = egui::vec2(18.0, 4.0);
                    ui.label(egui::RichText::new("воксельный психологический триллер").size(12.0).color(ACCENT));
                    logo(ui, 38.0, load.0);
                    ui.label(egui::RichText::new("Мир помнит то, что ты забыл.").size(13.0).italics().color(INK.gamma_multiply(0.75)));
                    ui.add_space(10.0);
                    let item = |ui: &mut egui::Ui, text: &str, enabled: bool, act: Action, out: &mut Vec<Action>| {
                        let b = egui::Button::new(egui::RichText::new(text).size(15.0)).min_size(egui::vec2(220.0, 32.0));
                        if ui.add_enabled(enabled, b).clicked() {
                            out.push(act);
                        }
                    };
                    let any = sv.rows.iter().any(Option::is_some);
                    if any {
                        item(ui, "Продолжить", true, Action::Continue, out);
                    }
                    item(ui, "Начать игру", true, Action::NewGame, out);
                    item(ui, "Загрузить", any, Action::OpenLoad, out);
                    item(ui, "Настройки", true, Action::Settings, out);
                    #[cfg(not(target_os = "android"))]
                    item(ui, "Выход", true, Action::Quit, out);
                    if apk.is_some() {
                        let b = egui::Button::new(egui::RichText::new("Обновить приложение").size(15.0).color(ACCENT)).min_size(egui::vec2(220.0, 32.0));
                        if ui.add(b).clicked() {
                            out.push(Action::UpdateApk);
                        }
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
                        ui.set_width(380.0);
                        ui.label(egui::RichText::new("Настройки").size(26.0).strong());
                        ui.add_space(10.0);
                        ui.label(egui::RichText::new("Чувствительность обзора").size(15.0));
                        ui.spacing_mut().slider_width = 300.0;
                        ui.add(egui::Slider::new(&mut st.sens, 0.3..=2.5).show_value(false));
                        ui.add_space(6.0);
                        ui.checkbox(&mut st.invert_y, egui::RichText::new("Инвертировать обзор по вертикали").size(15.0));
                        ui.checkbox(&mut st.show_fps, egui::RichText::new("Показывать FPS").size(15.0));
                        ui.add_space(14.0);
                        back(ui, out);
                    });
                });
            }
            Screen::Playing => {
                if st.show_fps {
                    egui::Area::new(egui::Id::unique("fps")).anchor(egui::Align2::LEFT_TOP, egui::vec2(16.0, 12.0)).order(egui::Order::Background).show(ctx, |ui| {
                        ui.add(egui::Label::new(egui::RichText::new(format!("{:.0} FPS", sv.fps)).size(13.0).color(INK.gamma_multiply(0.7))).extend());
                    });
                }
                story_hud(ctx, hud, out);
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
            Screen::Bag => {
                shade(ctx, 0xb0);
                bag(ctx, hud, out);
            }
            Screen::Paused => {
                shade(ctx, 0xa0);
                egui::Area::new(egui::Id::unique("paused")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).show(ctx, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(egui::RichText::new("Пауза").size(22.0).strong());
                        ui.add_space(6.0);
                        ui.spacing_mut().item_spacing.y = 6.0;
                        ui.spacing_mut().button_padding = egui::vec2(16.0, 4.0);
                        for (t, act) in [("Продолжить", Action::Resume), ("Вещи", Action::OpenBag), ("Сохранить", Action::OpenSave), ("Загрузить", Action::OpenLoad), ("Настройки", Action::Settings), ("В главное меню", Action::ToMenu)] {
                            let b = egui::Button::new(egui::RichText::new(t).size(14.0)).min_size(egui::vec2(190.0, 30.0));
                            if ui.add(b).clicked() {
                                out.push(act);
                            }
                        }
                    });
                });
            }
            Screen::Load | Screen::Save => {
                shade(ctx, 0xb0);
                let saving = screen == Screen::Save;
                egui::Area::new(egui::Id::unique("slots")).anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0)).show(ctx, |ui| {
                    egui::Frame::window(ui.style()).inner_margin(18.0).corner_radius(18.0).show(ui, |ui| {
                        // room for the «Удалить · Нет» of a deletion: the window does not jump when it shows
                        ui.set_width(440.0);
                        ui.label(egui::RichText::new(if saving { "Сохранить" } else { "Загрузить" }).size(22.0).strong());
                        ui.spacing_mut().item_spacing.y = 6.0;
                        ui.spacing_mut().button_padding = egui::vec2(14.0, 4.0);
                        // loadPanel of the web game: the autosave «А» only to load from, slots 1-3 both ways
                        for (i, row) in sv.rows.iter().enumerate() {
                            if saving && i == 0 {
                                continue;
                            }
                            let label = if i == 0 { "А" } else { save::SLOTS[i] };
                            let name = if i == 0 { "Автосохранение".to_string() } else { format!("Слот {label}") };
                            let (title, meta) = row.as_ref().map_or(("Пусто", name.as_str()), |(t, m)| (t.as_str(), m.as_str()));
                            ui.horizontal(|ui| {
                                if slot_row(ui, label, title, meta, saving || row.is_some()) {
                                    out.push(Action::Slot(i));
                                }
                                if !saving && row.is_some() {
                                    if sv.confirm == Some(i) {
                                        let yes = egui::Button::new(egui::RichText::new("Удалить").color(egui::Color32::from_rgb(0xe0, 0x50, 0x3f)));
                                        if ui.add(yes).clicked() {
                                            out.push(Action::Delete(i));
                                        }
                                        if ui.button("Нет").clicked() {
                                            out.push(Action::CancelDelete);
                                        }
                                    } else if ui.add(egui::Button::new(egui::RichText::new("Удалить").size(14.0).color(INK.gamma_multiply(0.7))).min_size(egui::vec2(0.0, 40.0))).clicked() {
                                        out.push(Action::AskDelete(i));
                                    }
                                }
                            });
                        }
                        ui.add_space(4.0);
                        back(ui, out);
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
                        Screen::Settings | Screen::Load | Screen::Save | Screen::Bag => self.act(Action::Back, el),
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
                    PhysicalKey::Code(KeyCode::KeyF) if event.state == ElementState::Pressed && self.screen == Screen::Playing => {
                        self.act(Action::Use, el);
                        return;
                    }
                    PhysicalKey::Code(KeyCode::KeyR) if event.state == ElementState::Pressed && self.screen == Screen::Playing => {
                        self.eye_tap = true;
                        return;
                    }
                    PhysicalKey::Code(KeyCode::KeyI) if event.state == ElementState::Pressed && self.screen == Screen::Playing => {
                        self.act(Action::OpenBag, el);
                        return;
                    }
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
        // the story's world first (the script's Duality: the wave, «вглядеться», the stability): the hero moves in the
        // world it stands in, and the frame shows the same worlds
        let eye = std::mem::take(&mut self.eye_tap);
        if let (true, None, Some(sc), Some(h)) = (playing, &self.hud.panel, &self.script, &self.hero) {
            let p = &h.player;
            let (c, t) = (glam::Vec3::from(p.cam_pos), glam::Vec3::from(p.cam_target));
            sc.tick(dt, p.pos, p.yaw, p.cam_pos, (t - c).normalize_or(glam::Vec3::Z).to_array(), eye, p.on_ground);
        }
        if let Some(sc) = &self.script {
            let ws = sc.world();
            self.hud.eye = ws.eye_available.then_some(ws.peering);
            self.hud.locked = ws.locked;
            if let Some(h) = &mut self.hero {
                h.player.night = ws.night;
            }
            if let Some(w) = &mut self.world {
                w.set_world(&world_frame(&ws));
            }
        }
        if let Some(h) = &mut self.hero {
            if matches!(self.screen, Screen::Playing | Screen::Paused | Screen::Bag) {
                let mut mv = [st, fw];
                if let Some((_, s0, s1)) = h.joy {
                    // full speed at 9 % of the short side from where the finger landed
                    let r = (size.width.min(size.height) as f64 * 0.09).max(1.0);
                    let (x, y) = (((s1.0 - s0.0) / r) as f32, (-(s1.1 - s0.1) / r) as f32);
                    let l = x.hypot(y).max(1.0);
                    mv = [x / l, y / l];
                    joy_vis = Some((egui::pos2(s0.0 as f32 / ppp, s0.1 as f32 / ppp), egui::pos2(s1.0 as f32 / ppp, s1.1 as f32 / ppp)));
                }
                if playing && self.hud.panel.is_none() {
                    self.save_t += dt;
                    self.playtime += dt as f64;
                    // a cinematic or a collapse holds the hero (player.js locked): the view still turns
                    let inp = if self.hud.locked { Input { mv: [0.0; 2], look: h.look, run: false } } else { Input { mv, look: h.look, run: self.keys[6] } };
                    h.look = [0.0; 2];
                    h.player.update(dt, &inp, &h.vox.borrow());
                    h.player.update_camera(dt, &inp, &h.vox.borrow(), size.height > size.width);
                }
                let (p, t) = (glam::Vec3::from(h.player.cam_pos), glam::Vec3::from(h.player.cam_target));
                let f = (t - p).normalize_or(glam::Vec3::NEG_Z);
                self.cam = Camera { pos: p, yaw: f.x.atan2(-f.z), pitch: f.y.clamp(-1.0, 1.0).asin(), fov_y: self.cam.fov_y };
                let pp = h.player.pos;
                focus = glam::Vec3::new(pp[0], h.player.vis_y, pp[2]);
            }
            if let (Some(rig), Some(w), Some(g)) = (&h.rig, &mut self.world, &self.gfx) {
                h.words.clear();
                if matches!(self.screen, Screen::Playing | Screen::Paused | Screen::Bag) {
                    write_rig(&mut h.words, rig, focus.to_array(), h.player.yaw, h.player.walking && playing, h.player.phase, h.player.speed, time);
                    // the witnesses and NPCs where the story stands them (creatures.js Figures.write: writeSimple)
                    if let Some(sc) = &self.script {
                        sc.figures(&mut self.hud.figs);
                        for f in &self.hud.figs {
                            if let Some(&mi) = self.hud.fig_models.get(f.idx).filter(|&&i| i != u32::MAX) {
                                mezdu_game::rig::instance(&mut h.words, &mezdu_game::rig::m34_trs(f.pos[0], f.pos[1], f.pos[2], f.yaw, 0.0, 0.0, f.scale), mi, f.mask);
                            }
                        }
                    }
                }
                w.set_dynamic(&g.queue, &h.words);
            }
        }
        self.story_events();
        // the fade of the story (respawn, collapse): eased toward its target
        let hf = &mut self.hud;
        if hf.fade != hf.fade_to {
            let step = hf.fade_speed * dt;
            hf.fade = if hf.fade < hf.fade_to { (hf.fade + step).min(hf.fade_to) } else { (hf.fade - step).max(hf.fade_to) };
        }
        if self.hud.say.as_ref().is_some_and(|s| s.2 < self.start.elapsed().as_secs_f32()) {
            self.hud.say = None;
        }
        if playing && self.save_t >= save::AUTOSAVE {
            self.autosave();
        }
        // the settings opened from the pause keep the game behind them
        if self.screen == Screen::Menu || (self.screen == Screen::Settings && self.back_to == Screen::Menu) {
            // the menu's view drifts a little, as a camera on a tripod in the wind
            self.cam.yaw = MENU_CAM[3] + (time * 0.07).sin() * 0.06;
        }
        let info = self.sys_info();
        let (apk, code) = self.updates.lock().map(|u| (u.apk.clone(), u.code.clone())).unwrap_or_default();
        // the restart window: on the menu and the pause, until «Позже»
        // a window over the menu (and the pause): a newer APK first, then a downloaded build waiting for a restart
        let calm = matches!(self.screen, Screen::Menu | Screen::Paused);
        let prompt = if let Some(b) = apk.as_ref().filter(|_| calm && !self.apk_later) {
            Some(Prompt {
                title: "Скачайте новую версию",
                text: format!("Вышла новая версия приложения ({b}). Скачайте и установите APK — игра и сохранения останутся."),
                yes: ("Скачать", Action::UpdateApk),
                no: ("Нет", Action::ApkLater),
            })
        } else {
            code.filter(|_| calm && !self.update_later).map(|b| Prompt {
                title: "Обновление готово",
                text: format!("Сборка {b} скачана. Для применения обновления требуется перезапуск."),
                yes: ("Перезапустить", Action::Restart),
                no: ("Позже", Action::Later),
            })
        };
        let (screen, err) = (self.screen, self.load_error.clone());
        let hud = &self.hud;
        if self.toast.as_ref().is_some_and(|(_, t)| t.elapsed().as_secs_f32() > 2.5) {
            self.toast = None;
        }
        let sv = SlotsView { rows: &self.slot_rows, confirm: self.confirm, toast: self.toast.as_ref().map(|t| t.0.as_str()), fps: self.fps };
        let mut st = self.settings;
        let lt = self.loading_frames as f32 / 30.0;
        let ls = self.loading.as_ref().and_then(|(s, _)| s.lock().ok().map(|s| (s.stage, s.frac, s.notes.clone())));
        let mut actions = Vec::new();
        let (Some(g), Some(ui)) = (&mut self.gfx, &mut self.ui) else { return };
        let world = if screen == Screen::Loading { None } else { self.world.as_mut() };
        g.render(world, &self.cam, focus, time, SKY, |d, q, enc, view, w, h| {
            ui.frame(d, q, enc, view, w, h, |ctx| Self::layout(ctx, screen, hud, &sv, &mut st, prompt.as_ref(), &info, err.as_deref(), apk.as_deref(), joy_vis, (lt, ls.as_ref()), &mut actions));
        });
        if st != self.settings {
            self.settings = st;
            save::write_settings(&self.data_dir, &st);
        }
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
            let k = self.settings.sens;
            h.look[0] += dx as f32 * k;
            h.look[1] += dy as f32 * k * if self.settings.invert_y { -1.0 } else { 1.0 };
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
    let updates: SharedUpdates = Arc::default();
    // the pack in the data dir is checked against the release in the background; with MEZDU_PACK (a pack picked
    // by hand on the desktop) nothing is downloaded
    if std::env::var_os("MEZDU_PACK").is_none() {
        mezdu_updater::install_staged(&data_dir);
        let (dir, up) = (data_dir.clone(), updates.clone());
        let _ = std::thread::Builder::new().name("updater".into()).spawn(move || {
            mezdu_updater::watch(dir, BUILD, ABI, move |f| {
                log::info!("updater found {f:?}");
                found(&up, f);
            });
        });
    }
    let mut app = App::new(data_dir, updates);
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
