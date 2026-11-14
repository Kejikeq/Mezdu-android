//! Window, lifecycle and the frame loop. Android enters through `android_main`, desktop through `main.rs`.
use mezdu_core::Pack;
use mezdu_gfx::Gfx;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::window::{Window, WindowId};

const SKY: [f64; 3] = [0.36, 0.47, 0.58];

pub struct App {
    data_dir: PathBuf,
    pack: Option<Pack>,
    window: Option<Arc<Window>>,
    gfx: Option<Gfx>,
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
        App { data_dir, pack, window: None, gfx: None, frames: 0, fps_t: Instant::now(), fps: 0.0 }
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
                if let Some(p) = &self.pack {
                    let bad = g.compile_shaders(&p.shaders());
                    for (n, e) in &bad {
                        log::error!("shader {n}: {e}");
                    }
                    log::info!("shaders: {} compiled, {} failed", p.manifest.of_kind("shader").count() - bad.len(), bad.len());
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
            WindowEvent::RedrawRequested => {
                let Some(g) = &mut self.gfx else { return };
                g.frame(SKY);
                self.frames += 1;
                let dt = self.fps_t.elapsed().as_secs_f32();
                if dt >= 2.0 {
                    self.fps = self.frames as f32 / dt;
                    self.frames = 0;
                    self.fps_t = Instant::now();
                    let s = self.status();
                    log::info!("{s}");
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

pub fn run(event_loop: EventLoop<()>, data_dir: PathBuf) {
    event_loop.set_control_flow(ControlFlow::Wait);
    let mut app = App::new(data_dir);
    if let Err(e) = event_loop.run_app(&mut app) {
        log::error!("event loop: {e}");
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    use winit::platform::android::EventLoopBuilderExtAndroid;
    android_logger::init_once(android_logger::Config::default().with_max_level(log::LevelFilter::Info).with_tag("mezdu"));
    let data_dir = app.internal_data_path().unwrap_or_else(|| PathBuf::from("/data/local/tmp/mezdu"));
    let el = EventLoop::builder().with_android_app(app).build().expect("event loop");
    run(el, data_dir);
}
