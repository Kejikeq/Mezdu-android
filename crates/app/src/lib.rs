//! Window, lifecycle and the frame loop. Android enters through `android_main`, desktop through `main.rs`.
use mezdu_core::Pack;
use mezdu_gfx::world::{Camera, World};
use mezdu_game::player::{Input, Player};
use mezdu_game::rig::{write_rig, RigModels};
use mezdu_game::voxels::Voxels;
use mezdu_gfx::Gfx;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use winit::application::ApplicationHandler;
use winit::event::{ElementState, MouseButton, Touch, TouchPhase, WindowEvent};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::window::{Window, WindowId};

// Until there is text on screen, the clear colour reports the state: sky = Vulkan, amber = GL fallback,
// dark red = some pack shader failed on this device.
const FRAME: std::time::Duration = std::time::Duration::from_nanos(1_000_000_000 / 30);
const SKY_VULKAN: [f64; 3] = [0.36, 0.47, 0.58];
const SKY_GL: [f64; 3] = [0.62, 0.48, 0.22];
const SKY_ERROR: [f64; 3] = [0.45, 0.06, 0.05];

/// chapter 1 spawn (chapters_data.js: voxel 454, 2234, facing +z) and a height hint above the ground floor
const SPAWN: [f32; 4] = [454.0 * 0.125, 8.5, 2234.0 * 0.125, 0.0];

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

pub struct App {
    data_dir: PathBuf,
    pack: Option<Pack>,
    window: Option<Arc<Window>>,
    gfx: Option<Gfx>,
    world: Option<World>,
    hero: Option<Hero>,
    cam: Camera,
    touches: HashMap<u64, (f64, f64)>,
    mouse: Option<(f64, f64)>,
    mouse_down: bool,
    keys: [bool; 7],
    last: Instant,
    start: Instant,
    next_frame: Instant,
    /// MEZDU_TIME=<seconds> freezes the animation clock (comparable screenshots on the desktop)
    frozen: Option<f32>,
    sky: [f64; 3],
    frames: u32,
    fps_t: Instant,
    pub fps: f32,
}

impl App {
    pub fn new(data_dir: PathBuf) -> Self {
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
                let mut player = Player::new(&vox);
                player.spawn(&vox, SPAWN[0], SPAWN[2], SPAWN[1], SPAWN[3]);
                log::info!("hero at {:.2?}", player.pos);
                Some(Hero { vox, player, rig: None, words: Vec::with_capacity(16 * 16), joy: None, look: [0.0; 2] })
            }
            Err(e) => {
                log::warn!("no voxels, free camera: {e}");
                None
            }
        });
        App { data_dir, pack, window: None,
            gfx: None,
            world: None,
            hero,
            // chapter 1: in the street in front of the house, looking north at it
            cam: Camera { pos: glam::Vec3::new(54.0, 11.0, 312.0), yaw: -0.25, pitch: -0.18, fov_y: 1.0 },
            touches: HashMap::new(),
            mouse: None,
            mouse_down: false,
            keys: [false; 7],
            last: Instant::now(),
            start: Instant::now(),
            next_frame: Instant::now(),
            frozen: std::env::var("MEZDU_TIME").ok().and_then(|v| v.parse().ok()),
            sky: SKY_VULKAN,
            frames: 0, fps_t: Instant::now(), fps: 0.0 }
    }

    fn status(&self) -> String {
        let g = self.gfx.as_ref().map(|g| format!("{:?} · {}", g.backend, g.adapter_name)).unwrap_or_default();
        let p = self.pack.as_ref().map(|p| p.manifest.version.clone()).unwrap_or_else(|| "без пака".into());
        format!("МЕЖДУ · {g} · {:.0} FPS · {p}", self.fps)
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        // a pack the updater staged while the game ran: installed now, before the world is built again
        if self.world.is_none() && std::env::var_os("MEZDU_PACK").is_none() && self.data_dir.join("pack.next/manifest.json").exists() {
            mezdu_updater::install_staged(&self.data_dir);
            self.reload_pack();
        }
        let window = match &self.window {
            Some(w) => w.clone(),
            None => {
                let w = Arc::new(el.create_window(Window::default_attributes().with_title("МЕЖДУ")).expect("window"));
                self.window = Some(w.clone());
                w
            }
        };
        let size = window.inner_size();
        match Gfx::new(window.clone(), size.width, size.height) {
            Ok(g) => {
                self.sky = if g.backend == mezdu_gfx::wgpu::Backend::Gl { SKY_GL } else { SKY_VULKAN };
                if let Some(p) = &self.pack {
                    let bad = g.compile_shaders(&p.shaders());
                    for (n, e) in &bad {
                        log::error!("shader {n}: {e}");
                    }
                    log::info!("shaders: {} compiled, {} failed", p.manifest.of_kind("shader").count() - bad.len(), bad.len());
                    if !bad.is_empty() {
                        self.sky = SKY_ERROR;
                    } else {
                        match g.try_world(p, 1) {
                            Ok(w) => {
                                log::info!("quality: {:?}", w.quality);
                                if let Some(h) = &mut self.hero {
                                    h.rig = RigModels::find("hero", &w.model_names());
                                }
                                self.world = Some(w);
                            }
                            Err(e) => {
                                log::error!("world: {e}");
                                if g.backend != mezdu_gfx::wgpu::Backend::Gl {
                                    self.sky = SKY_ERROR;
                                }
                            }
                        }
                    }
                }
                self.gfx = Some(g);
            }
            Err(e) => log::error!("no GPU device: {e}"),
        }
        log::info!("data dir {}", self.data_dir.display());
        window.request_redraw();
    }

    /// QUALITY.fps = 30: one frame every 33 ms, the event loop sleeps in between (battery); vsync alone would draw 60
    fn about_to_wait(&mut self, el: &ActiveEventLoop) {
        if self.gfx.is_none() {
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

    // Android destroys the native window in the background: drop the surface, stop rendering (battery)
    fn suspended(&mut self, _el: &ActiveEventLoop) {
        self.world = None;
        self.gfx = None;
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
            WindowEvent::MouseInput { state, button: MouseButton::Left, .. } => self.mouse_down = state == ElementState::Pressed,
            WindowEvent::CursorMoved { position, .. } => {
                if let (Some((x, y)), true) = (self.mouse, self.mouse_down) {
                    self.look(position.x - x, position.y - y);
                }
                self.mouse = Some((position.x, position.y));
            }
            WindowEvent::KeyboardInput { event, .. } => {
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
            WindowEvent::RedrawRequested => {
                let dt = self.last.elapsed().as_secs_f32().min(0.1);
                self.last = Instant::now();
                let k = |i: usize| if self.keys[i] { 1.0 } else { 0.0 };
                let (fw, st, up) = (k(0) - k(1), k(3) - k(2), k(4) - k(5));
                let time = self.frozen.unwrap_or_else(|| self.start.elapsed().as_secs_f32());
                let mut focus = self.cam.pos;
                let size = self.window.as_ref().map(|w| w.inner_size()).unwrap_or_default();
                if let Some(h) = &mut self.hero {
                    // joystick: the finger's offset from where it touched down, full speed at 9 % of the short side
                    let mut mv = [st, fw];
                    if let Some((_, s0, s1)) = h.joy {
                        let r = (size.width.min(size.height) as f64 * 0.09).max(1.0);
                        let (x, y) = (((s1.0 - s0.0) / r) as f32, (-(s1.1 - s0.1) / r) as f32);
                        let l = x.hypot(y).max(1.0);
                        mv = [x / l, y / l];
                    }
                    let inp = Input { mv, look: h.look, run: self.keys[6] };
                    h.look = [0.0; 2];
                    h.player.update(dt, &inp, &h.vox);
                    h.player.update_camera(dt, &inp, &h.vox, size.height > size.width);
                    let (p, t) = (glam::Vec3::from(h.player.cam_pos), glam::Vec3::from(h.player.cam_target));
                    let f = (t - p).normalize_or(glam::Vec3::NEG_Z);
                    self.cam = Camera { pos: p, yaw: f.x.atan2(-f.z), pitch: f.y.clamp(-1.0, 1.0).asin(), fov_y: self.cam.fov_y };
                    let pp = h.player.pos;
                    focus = glam::Vec3::new(pp[0], h.player.vis_y, pp[2]);
                    if let (Some(rig), Some(w), Some(g)) = (&h.rig, &mut self.world, &self.gfx) {
                        h.words.clear();
                        write_rig(&mut h.words, rig, focus.to_array(), h.player.yaw, h.player.walking, h.player.phase, h.player.speed, time);
                        w.set_dynamic(&g.queue, &h.words);
                    }
                } else if fw != 0.0 || st != 0.0 || up != 0.0 {
                    let c = &mut self.cam;
                    c.pos += (c.forward() * fw + c.right() * st + glam::Vec3::Y * up) * 6.0 * dt;
                }
                let Some(g) = &mut self.gfx else { return };
                match &mut self.world {
                    Some(w) => g.frame_world(w, &self.cam, focus, time),
                    None => g.frame(self.sky),
                }
                self.frames += 1;
                let dt = self.fps_t.elapsed().as_secs_f32();
                if dt >= 2.0 {
                    self.fps = self.frames as f32 / dt;
                    self.frames = 0;
                    self.fps_t = Instant::now();
                    let s = self.status();
                    match &self.world {
                        Some(w) => log::info!("{s} · {} quads, {} instances, {} draws · cam {:.1?} · hero {:.2?}", w.quads, w.instances, w.calls, self.cam.pos, self.hero.as_ref().map(|h| h.player.pos)),
                        None => log::info!("{s}"),
                    }
                    if let Some(w) = &self.window {
                        w.set_title(&s);
                    }
                }
            }
            _ => {}
        }
    }
}

impl App {
    /// re-opens the pack after an update; the hero keeps where it stands
    fn reload_pack(&mut self) {
        let Ok(p) = Pack::open(self.data_dir.join("pack")) else { return };
        log::info!("pack {} ({}) loaded", p.manifest.version, &p.manifest.commit[..7.min(p.manifest.commit.len())]);
        if let (Some(h), Ok(vox)) = (&mut self.hero, Voxels::load(&p)) {
            h.vox = vox;
        }
        self.pack = Some(p);
    }

    fn look(&mut self, dx: f64, dy: f64) {
        if let Some(h) = &mut self.hero {
            h.look[0] += dx as f32;
            h.look[1] += dy as f32;
            return;
        }
        self.cam.yaw += dx as f32 * 0.005;
        self.cam.pitch = (self.cam.pitch - dy as f32 * 0.005).clamp(-1.5, 1.5);
    }

    /// With the hero: a finger that lands on the left 45 % of the screen is the joystick, any other finger looks
    /// around. Without it (free camera): one finger looks, two fingers move.
    fn touch(&mut self, t: Touch) {
        let p = (t.location.x, t.location.y);
        let width = self.window.as_ref().map_or(1, |w| w.inner_size().width) as f64;
        if let Some(h) = &mut self.hero {
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
            return;
        }
        match t.phase {
            TouchPhase::Started => {
                self.touches.insert(t.id, p);
            }
            TouchPhase::Ended | TouchPhase::Cancelled => {
                self.touches.remove(&t.id);
            }
            TouchPhase::Moved => {
                let Some(old) = self.touches.insert(t.id, p) else { return };
                let (dx, dy) = (p.0 - old.0, p.1 - old.1);
                match self.touches.len() {
                    1 => self.look(dx, dy),
                    2 => {
                        // each of the two fingers reports its own move: half the step per finger
                        let c = &mut self.cam;
                        let fwd = glam::Vec3::new(c.yaw.sin(), 0.0, -c.yaw.cos());
                        c.pos += (fwd * (-dy as f32) + c.right() * (dx as f32)) * 0.02;
                    }
                    _ => {}
                }
            }
        }
    }
}

/// commit of this build (set by CI for the APK; empty in local builds: no APK update check)
pub const BUILD: &str = match option_env!("MEZDU_BUILD") {
    Some(b) => b,
    None => "",
};

pub fn run(event_loop: EventLoop<()>, data_dir: PathBuf) {
    event_loop.set_control_flow(ControlFlow::Wait);
    // the pack in the data dir is checked against the release in the background; with MEZDU_PACK (a pack picked
    // by hand on the desktop) nothing is downloaded
    if std::env::var_os("MEZDU_PACK").is_none() {
        mezdu_updater::install_staged(&data_dir);
        let dir = data_dir.clone();
        let _ = std::thread::Builder::new().name("updater".into()).spawn(move || {
            mezdu_updater::watch(dir, BUILD, |c| log::info!("a newer APK ({c}) is available"));
        });
    }
    let mut app = App::new(data_dir);
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
    let el = EventLoop::builder().with_android_app(app).build().expect("event loop");
    run(el, data_dir);
}
