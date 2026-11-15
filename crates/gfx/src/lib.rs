//! wgpu device on Vulkan, falling back to GLES when Vulkan is missing or fails.
use std::sync::Arc;
pub mod props;
pub mod world;
pub use wgpu;

pub struct Gfx {
    /// none while the app is in the background (Android takes the native window away); device, world and
    /// everything on the GPU stay, so coming back needs only a new surface
    pub surface: Option<wgpu::Surface<'static>>,
    instance: wgpu::Instance,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub config: wgpu::SurfaceConfiguration,
    pub backend: wgpu::Backend,
    pub adapter_name: String,
    pub adapter_info: wgpu::AdapterInfo,
}

fn backends_in_order() -> Vec<wgpu::Backends> {
    // MEZDU_BACKEND=gl|vulkan forces one backend (desktop testing of the fallback)
    match std::env::var("MEZDU_BACKEND").ok().as_deref() {
        Some("gl") => vec![wgpu::Backends::GL],
        Some("vulkan") => vec![wgpu::Backends::VULKAN],
        _ if cfg!(target_os = "android") => vec![wgpu::Backends::VULKAN, wgpu::Backends::GL],
        _ => vec![wgpu::Backends::PRIMARY, wgpu::Backends::GL],
    }
}

impl Gfx {
    pub fn new<W>(window: Arc<W>, width: u32, height: u32) -> Result<Self, String>
    where
        W: wgpu::rwh::HasWindowHandle + wgpu::rwh::HasDisplayHandle + std::fmt::Debug + Send + Sync + 'static,
    {
        let mut errors = Vec::new();
        for backends in backends_in_order() {
            match pollster::block_on(Self::try_backend(backends, window.clone(), width, height)) {
                Ok(g) => return Ok(g),
                Err(e) => {
                    log::warn!("{backends:?}: {e}");
                    errors.push(format!("{backends:?}: {e}"));
                }
            }
        }
        Err(errors.join("; "))
    }

    async fn try_backend<W>(backends: wgpu::Backends, window: Arc<W>, width: u32, height: u32) -> Result<Self, String>
    where
        W: wgpu::rwh::HasWindowHandle + wgpu::rwh::HasDisplayHandle + std::fmt::Debug + Send + Sync + 'static,
    {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends,
            ..wgpu::InstanceDescriptor::new_with_display_handle(Box::new(window.clone()))
        });
        let surface = instance.create_surface(window).map_err(|e| e.to_string())?;
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: Some(&surface),
                ..Default::default()
            })
            .await
            .map_err(|e| e.to_string())?;
        let info = adapter.get_info();
        // the world bind group has 7 storage buffers and 11 textures per stage (renderer.js L0): ask for what the GPU has
        // (GLES included: whether its limits are enough is decided when the world is built, see World::try_new)
        let limits = adapter.limits();
        // compiled pipelines kept on disk between starts (Vulkan): the second start skips the driver's compile
        let required_features = adapter.features() & wgpu::Features::PIPELINE_CACHE;
        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("mezdu"),
                required_limits: limits,
                required_features,
                ..Default::default()
            })
            .await
            .map_err(|e| e.to_string())?;
        let caps = surface.get_capabilities(&adapter);
        let format = caps.formats.iter().copied().find(|f| !f.is_srgb()).unwrap_or(caps.formats[0]);
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            color_space: Default::default(),
            width: width.max(1),
            height: height.max(1),
            // Fifo = vsync: no wasted frames, the cheapest mode for the battery
            present_mode: wgpu::PresentMode::Fifo,
            desired_maximum_frame_latency: 2,
            alpha_mode: caps.alpha_modes[0],
            view_formats: vec![],
        };
        surface.configure(&device, &config);
        log::info!("gfx: {:?} · {} · {:?}", info.backend, info.name, format);
        Ok(Gfx { surface: Some(surface), instance, device, queue, config, backend: info.backend, adapter_name: info.name.clone(), adapter_info: info })
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.config.width = width;
        self.config.height = height;
        if let Some(s) = &self.surface {
            s.configure(&self.device, &self.config);
        }
    }

    /// The app went to the background: only the surface goes, the device and the world stay in memory.
    pub fn suspend(&mut self) {
        self.surface = None;
    }

    /// Back from the background: a surface on the new native window of the same device.
    pub fn resume<W>(&mut self, window: Arc<W>, width: u32, height: u32) -> Result<(), String>
    where
        W: wgpu::rwh::HasWindowHandle + wgpu::rwh::HasDisplayHandle + std::fmt::Debug + Send + Sync + 'static,
    {
        let s = self.instance.create_surface(window).map_err(|e| e.to_string())?;
        self.config.width = width.max(1);
        self.config.height = height.max(1);
        s.configure(&self.device, &self.config);
        self.surface = Some(s);
        Ok(())
    }

    /// Compiles every pack shader on this device; returns (name, error) for the ones the driver rejects.
    pub fn compile_shaders(&self, shaders: &[(String, String)]) -> Vec<(String, String)> {
        let mut bad = Vec::new();
        for (name, src) in shaders {
            let scope = self.device.push_error_scope(wgpu::ErrorFilter::Validation);
            let _m = self.device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(name),
                source: wgpu::ShaderSource::Wgsl(src.as_str().into()),
            });
            if let Some(e) = pollster::block_on(scope.pop()) {
                bad.push((name.clone(), e.to_string()));
            }
        }
        bad
    }

    fn acquire(&mut self) -> Option<wgpu::SurfaceTexture> {
        let surface = self.surface.as_ref()?;
        match surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(t) => Some(t),
            wgpu::CurrentSurfaceTexture::Suboptimal(t) => {
                surface.configure(&self.device, &self.config);
                Some(t)
            }
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                surface.configure(&self.device, &self.config);
                None
            }
            _ => None, // timeout / occluded: skip the frame
        }
    }

    /// One frame: the world through the game's shaders (or a plain colour without one), then `overlay` draws on top
    /// (the interface), then present.
    #[allow(clippy::too_many_arguments)]
    pub fn render(
        &mut self,
        world: Option<&mut world::World>,
        cam: &world::Camera,
        focus: glam::Vec3,
        time: f32,
        sky: [f64; 3],
        overlay: impl FnOnce(&wgpu::Device, &wgpu::Queue, &mut wgpu::CommandEncoder, &wgpu::TextureView, u32, u32),
    ) {
        let Some(tex) = self.acquire() else { return };
        let view = tex.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut enc = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let (w, h) = (self.config.width, self.config.height);
        match world {
            Some(wd) => wd.render(&self.device, &self.queue, &mut enc, &view, w, h, cam, focus, time),
            None => {
                enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("clear"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &view,
                        resolve_target: None,
                        depth_slice: None,
                        ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r: sky[0], g: sky[1], b: sky[2], a: 1.0 }), store: wgpu::StoreOp::Store },
                    })],
                    ..Default::default()
                });
            }
        }
        overlay(&self.device, &self.queue, &mut enc, &view, w, h);
        self.queue.submit([enc.finish()]);
        self.queue.present(tex);
    }
}

/// What the loader thread needs of the device: everything is cloneable and Send.
#[derive(Clone)]
pub struct DeviceCtx {
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub format: wgpu::TextureFormat,
    pub backend: wgpu::Backend,
    pub info: wgpu::AdapterInfo,
}

impl Gfx {
    pub fn ctx(&self) -> DeviceCtx {
        DeviceCtx { device: self.device.clone(), queue: self.queue.clone(), format: self.config.format, backend: self.backend, info: self.adapter_info.clone() }
    }
}

/// The loading stages that need the GPU: compiles every shader of the pack for this device (`progress` gets the
/// share done), then builds the world with its pipelines through the on-disk pipeline cache in `cache_dir`.
/// On GL inside error scopes: a GLES driver may lack what the world needs, then Err and the status stays amber.
pub fn build_world(ctx: &DeviceCtx, pack: &mezdu_core::Pack, chapter: u32, cache_dir: &std::path::Path, progress: &dyn Fn(u32, f32)) -> Result<world::World, String> {
    let d = &ctx.device;
    let shaders = pack.shaders();
    for (i, (name, src)) in shaders.iter().enumerate() {
        progress(0, i as f32 / shaders.len().max(1) as f32);
        let scope = d.push_error_scope(wgpu::ErrorFilter::Validation);
        let _m = d.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some(name), source: wgpu::ShaderSource::Wgsl(src.as_str().into()) });
        if let Some(e) = pollster::block_on(scope.pop()) {
            return Err(format!("шейдер {name}: {e}"));
        }
    }
    progress(0, 1.0);
    std::thread::sleep(std::time::Duration::from_millis(150));
    progress(1, 0.0);
    let key = wgpu::util::pipeline_cache_key(&ctx.info).filter(|_| d.features().contains(wgpu::Features::PIPELINE_CACHE));
    let file = key.map(|k| cache_dir.join(k));
    let data = file.as_ref().and_then(|f| std::fs::read(f).ok());
    // SAFETY: the data was written by get_data of this app for this adapter (the key holds vendor, device, driver)
    let cache = file.as_ref().map(|_| unsafe { d.create_pipeline_cache(&wgpu::PipelineCacheDescriptor { label: Some("mezdu"), data: data.as_deref(), fallback: true }) });
    log::info!("pipeline cache: {}", match (&cache, &data) { (Some(_), Some(b)) => format!("{} KB from disk", b.len() / 1024), (Some(_), None) => "new".into(), _ => "not supported".into() });
    let gl = ctx.backend == wgpu::Backend::Gl;
    let q = if gl { world::Quality::GL } else { world::Quality::VULKAN };
    // shader translation failures are internal errors (e.g. textureLoad of a depth texture has no GLSL form)
    let internal = d.push_error_scope(wgpu::ErrorFilter::Internal);
    let validation = d.push_error_scope(wgpu::ErrorFilter::Validation);
    let w = world::World::new(d, &ctx.queue, ctx.format, pack, chapter, q, cache.as_ref());
    let errs = [pollster::block_on(validation.pop()), pollster::block_on(internal.pop())];
    if let Some(e) = errs.into_iter().flatten().next() {
        return Err(format!("{:?}: {e}", ctx.backend));
    }
    if let (Some(c), Some(f)) = (&cache, &file) {
        if let Some(bytes) = c.get_data() {
            let _ = std::fs::create_dir_all(cache_dir);
            let _ = std::fs::write(f, bytes);
        }
    }
    progress(1, 1.0);
    w
}
