//! Desktop build (Linux/Windows) for development: `cargo run -p mezdu-app` (MEZDU_PACK=<dir>, MEZDU_BACKEND=gl|vulkan).
#[cfg(not(target_os = "android"))]
fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    let data = std::env::current_dir().unwrap_or_default();
    mezdu::run(winit::event_loop::EventLoop::new().expect("event loop"), data);
}

#[cfg(target_os = "android")]
fn main() {} // Android starts the cdylib through android_main
