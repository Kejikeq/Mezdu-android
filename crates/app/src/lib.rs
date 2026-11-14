//! Window, lifecycle and the frame loop. Android enters through `android_main`, desktop through `main.rs`.
use mezdu_core::Pack;
use mezdu_gfx::world::{Camera, World};
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
const SKY_VULKAN: [f64; 3] = [0.36, 0.47, 0.58];
const SKY_GL: [f64; 3] = [0.62, 0.48, 0.22];
const SKY_ERROR: [f64; 3] = [0.45, 0.06, 0.05];

pub struct App {
    data_dir: PathBuf,
    pack: Option<Pack>,
    window: Option<Arc<Window>>,
    gfx: Option<Gfx>,
    world: Option<World>,
    cam: Camera,
    touches: HashMap<u64, (f64, f64)>,
    mouse: Option<(f64, f64)>,
    mouse_down: bool,
    keys: [bool; 6],
    last: Instant,
    start: Instant,
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
        App { data_dir, pack, window: None,
            gfx: None,
            world: None,
            // chapter 1: in the street in front of the house, looking north at it
            cam: Camera { pos: glam::Vec3::new(54.0, 11.0, 312.0), yaw: -0.25, pitch: -0.18, fov_y: 1.0 },
            touches: HashMap::new(),
            mouse: None,
            mouse_down: false,
            keys: [false; 6],
            last: Instant::now(),
            start: Instant::now(),
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
                    } else if g.backend != mezdu_gfx::wgpu::Backend::Gl {
                        match World::new(&g.device, &g.queue, g.config.format, p, 1) {
                            Ok(w) => self.world = Some(w),
                            Err(e) => {
                                log::error!("world: {e}");
                                self.sky = SKY_ERROR;
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
                    _ => return,
                };
                self.keys[k] = event.state == ElementState::Pressed;
            }
            WindowEvent::RedrawRequested => {
                let dt = self.last.elapsed().as_secs_f32().min(0.1);
                self.last = Instant::now();
                let k = |i: usize| if self.keys[i] { 1.0 } else { 0.0 };
                let (fw, st, up) = (k(0) - k(1), k(3) - k(2), k(4) - k(5));
                if fw != 0.0 || st != 0.0 || up != 0.0 {
                    let c = &mut self.cam;
                    c.pos += (c.forward() * fw + c.right() * st + glam::Vec3::Y * up) * 6.0 * dt;
                }
                let Some(g) = &mut self.gfx else { return };
                match &mut self.world {
                    Some(w) => g.frame_world(w, &self.cam, self.start.elapsed().as_secs_f32()),
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
                        Some(w) => log::info!("{s} · {} quads, {} instances, {} draws · cam {:.1?}", w.quads, w.instances, w.calls, self.cam.pos),
                        None => log::info!("{s}"),
                    }
                    if let Some(w) = &self.window {
                        w.set_title(&s);
                    }
                }
                if let Some(w) = &self.window {
                    w.request_redraw();
                }
            }
            _ => {}
        }
    }
}

impl App {
    fn look(&mut self, dx: f64, dy: f64) {
        self.cam.yaw += dx as f32 * 0.005;
        self.cam.pitch = (self.cam.pitch - dy as f32 * 0.005).clamp(-1.5, 1.5);
    }

    /// One finger looks around; two fingers move: drag up/down = forward/back, left/right = sideways.
    fn touch(&mut self, t: Touch) {
        let p = (t.location.x, t.location.y);
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

pub fn run(event_loop: EventLoop<()>, data_dir: PathBuf) {
    event_loop.set_control_flow(ControlFlow::Wait);
    let mut app = App::new(data_dir);
    if let Err(e) = event_loop.run_app(&mut app) {
        log::error!("event loop: {e}");
    }
}

/// Copies the pack bundled in the APK (assets/pack) into the data dir when the data dir holds another commit.
/// Stage 2 (updater) must not let this overwrite a newer downloaded pack.
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
    if Pack::open(&dst).map(|p| p.manifest.commit == m.commit).unwrap_or(false) {
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
            Ok(()) => log::info!("bundled pack {} installed", m.version),
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
    install_bundled_pack(&app, &data_dir);
    let el = EventLoop::builder().with_android_app(app).build().expect("event loop");
    run(el, data_dir);
}
