//! wgpu device on Vulkan, falling back to GLES when Vulkan is missing or fails.
use std::sync::Arc;
pub mod props;
pub mod world;
pub use wgpu;

pub struct Gfx {
    pub surface: wgpu::Surface<'static>,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub config: wgpu::SurfaceConfiguration,
    pub backend: wgpu::Backend,
    pub adapter_name: String,
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
        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("mezdu"),
                required_limits: limits,
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
        Ok(Gfx { surface, device, queue, config, backend: info.backend, adapter_name: info.name })
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.config.width = width;
        self.config.height = height;
        self.surface.configure(&self.device, &self.config);
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
        match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(t) => Some(t),
            wgpu::CurrentSurfaceTexture::Suboptimal(t) => {
                self.surface.configure(&self.device, &self.config);
                Some(t)
            }
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                self.surface.configure(&self.device, &self.config);
                None
            }
            _ => None, // timeout / occluded: skip the frame
        }
    }

    /// Builds the world; on GL inside an error scope, because a GLES driver may lack storage buffers in the vertex
    /// stage or enough bindings: then the world is not drawn and the status colour stays amber.
    pub fn try_world(&self, pack: &mezdu_core::Pack, chapter: u32) -> Result<world::World, String> {
        let gl = self.backend == wgpu::Backend::Gl;
        let q = if gl { world::Quality::GL } else { world::Quality::VULKAN };
        // shader translation failures are internal errors (e.g. textureLoad of a depth texture has no GLSL form)
        let internal = self.device.push_error_scope(wgpu::ErrorFilter::Internal);
        let validation = self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let w = world::World::new(&self.device, &self.queue, self.config.format, pack, chapter, q);
        let errs = [pollster::block_on(validation.pop()), pollster::block_on(internal.pop())];
        if let Some(e) = errs.into_iter().flatten().next() {
            return Err(format!("{:?}: {e}", self.backend));
        }
        w
    }

    /// Scene frame: the world through the game's shaders, then present.
    pub fn frame_world(&mut self, world: &mut world::World, cam: &world::Camera, time: f32) {
        let Some(tex) = self.acquire() else { return };
        let view = tex.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut enc = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        world.render(&self.device, &self.queue, &mut enc, &view, self.config.width, self.config.height, cam, time);
        self.queue.submit([enc.finish()]);
        self.queue.present(tex);
    }

    /// Status frame: clear to a colour.
    pub fn frame(&mut self, sky: [f64; 3]) {
        let tex = match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(t) => t,
            wgpu::CurrentSurfaceTexture::Suboptimal(t) => {
                self.surface.configure(&self.device, &self.config);
                t
            }
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                self.surface.configure(&self.device, &self.config);
                return;
            }
            _ => return, // timeout / occluded: skip the frame
        };
        let view = tex.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut enc = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let _pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("clear"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    depth_slice: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color { r: sky[0], g: sky[1], b: sky[2], a: 1.0 }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                ..Default::default()
            });
        }
        self.queue.submit([enc.finish()]);
        self.queue.present(tex);
    }
}
