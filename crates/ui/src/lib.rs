//! The interface: egui (immediate-mode UI with Cyrillic fonts) laid out by the app and drawn here with one wgpu
//! pass over the finished frame. Style after the web version's style.css: dark ink, warm gold accent, pill buttons.
use std::collections::HashMap;
use std::sync::Arc;

pub use egui;

const SHADER: &str = r#"
struct U { size: vec2f, _p: vec2f };
@group(0) @binding(0) var<uniform> u: U;
@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var smp: sampler;
struct V { @builtin(position) pos: vec4f, @location(0) uv: vec2f, @location(1) col: vec4f };
@vertex fn vs(@location(0) p: vec2f, @location(1) uv: vec2f, @location(2) c: vec4f) -> V {
  return V(vec4f(p.x / u.size.x * 2.0 - 1.0, 1.0 - p.y / u.size.y * 2.0, 0.0, 1.0), uv, c);
}
// egui colours and textures are premultiplied gamma-space sRGBA; the swapchain is not sRGB, so no conversion
@fragment fn fs(v: V) -> @location(0) vec4f { return v.col * textureSample(tex, smp, v.uv); }
"#;

struct Tex {
    tex: wgpu::Texture,
    bg: wgpu::BindGroup,
}

pub struct Ui {
    pub ctx: egui::Context,
    pipeline: wgpu::RenderPipeline,
    tex_layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,
    ubuf: wgpu::Buffer,
    ubg: wgpu::BindGroup,
    vbuf: wgpu::Buffer,
    ibuf: wgpu::Buffer,
    textures: HashMap<egui::TextureId, Tex>,
    events: Vec<egui::Event>,
    pointer: Option<egui::Pos2>,
    pub ppp: f32,
    start: std::time::Instant,
}

pub const INK: egui::Color32 = egui::Color32::from_rgb(0xec, 0xe4, 0xd6);
pub const BG: egui::Color32 = egui::Color32::from_rgb(0x0d, 0x0b, 0x10);
pub const ACCENT: egui::Color32 = egui::Color32::from_rgb(0xf2, 0xc8, 0x79);

impl Ui {
    pub fn new(d: &wgpu::Device, format: wgpu::TextureFormat, ppp: f32) -> Self {
        let ctx = egui::Context::default();
        ctx.set_theme(egui::Theme::Dark);
        let mut style = (*ctx.style_of(egui::Theme::Dark)).clone();
        style.visuals = egui::Visuals::dark();
        style.visuals.override_text_color = Some(INK);
        style.visuals.panel_fill = egui::Color32::TRANSPARENT;
        style.visuals.window_fill = egui::Color32::from_rgba_unmultiplied(0x0d, 0x0b, 0x10, 0xe6);
        let wv = &mut style.visuals.widgets;
        for (w, a) in [(&mut wv.inactive, 0x10), (&mut wv.hovered, 0x1f), (&mut wv.active, 0x2c)] {
            w.weak_bg_fill = egui::Color32::from_rgba_unmultiplied(255, 245, 230, a);
            w.bg_fill = w.weak_bg_fill;
            w.bg_stroke = egui::Stroke::new(1.0, egui::Color32::from_rgba_unmultiplied(242, 200, 121, if a > 0x10 { 0x73 } else { 0x30 }));
            w.corner_radius = egui::CornerRadius::same(255);
            w.fg_stroke = egui::Stroke::new(1.0, INK);
        }
        // text is to be read, not selected (egui selects labels by default)
        style.interaction.selectable_labels = false;
        style.interaction.multi_widget_text_select = false;
        style.spacing.button_padding = egui::vec2(22.0, 12.0);
        style.spacing.item_spacing = egui::vec2(10.0, 12.0);
        style.text_styles.insert(egui::TextStyle::Button, egui::FontId::proportional(18.0));
        style.text_styles.insert(egui::TextStyle::Body, egui::FontId::proportional(16.0));
        style.text_styles.insert(egui::TextStyle::Heading, egui::FontId::proportional(52.0));
        ctx.set_style_of(egui::Theme::Dark, style);

        let shader = d.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("ui"), source: wgpu::ShaderSource::Wgsl(SHADER.into()) });
        let ul = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("ui u"),
            entries: &[wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::VERTEX, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None }],
        });
        let tex_layout = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("ui tex"),
            entries: &[
                wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: true }, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false }, count: None },
                wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
            ],
        });
        let layout = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("ui"), bind_group_layouts: &[Some(&ul), Some(&tex_layout)], immediate_size: 0 });
        let blend = wgpu::BlendState {
            color: wgpu::BlendComponent { src_factor: wgpu::BlendFactor::One, dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha, operation: wgpu::BlendOperation::Add },
            alpha: wgpu::BlendComponent { src_factor: wgpu::BlendFactor::OneMinusDstAlpha, dst_factor: wgpu::BlendFactor::One, operation: wgpu::BlendOperation::Add },
        };
        let pipeline = d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("ui"),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs"),
                compilation_options: Default::default(),
                buffers: &[Some(wgpu::VertexBufferLayout {
                    array_stride: 20,
                    step_mode: wgpu::VertexStepMode::Vertex,
                    attributes: &wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32x2, 2 => Unorm8x4],
                })],
            },
            fragment: Some(wgpu::FragmentState { module: &shader, entry_point: Some("fs"), compilation_options: Default::default(), targets: &[Some(wgpu::ColorTargetState { format, blend: Some(blend), write_mask: wgpu::ColorWrites::ALL })] }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: Default::default(),
            multiview_mask: None,
            cache: None,
        });
        let ubuf = d.create_buffer(&wgpu::BufferDescriptor { label: Some("ui u"), size: 16, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let ubg = d.create_bind_group(&wgpu::BindGroupDescriptor { label: Some("ui u"), layout: &ul, entries: &[wgpu::BindGroupEntry { binding: 0, resource: ubuf.as_entire_binding() }] });
        let mk = |label, usage| d.create_buffer(&wgpu::BufferDescriptor { label: Some(label), size: 1 << 20, usage: usage | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        Ui {
            ctx,
            pipeline,
            tex_layout,
            sampler: d.create_sampler(&wgpu::SamplerDescriptor { mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() }),
            ubuf,
            ubg,
            vbuf: mk("ui v", wgpu::BufferUsages::VERTEX),
            ibuf: mk("ui i", wgpu::BufferUsages::INDEX),
            textures: HashMap::new(),
            events: Vec::new(),
            pointer: None,
            ppp,
            start: std::time::Instant::now(),
        }
    }

    /// A finger or the mouse, in physical pixels: down / moved / up. egui sees it as the primary pointer.
    pub fn pointer(&mut self, x: f64, y: f64, phase: Phase) {
        let p = egui::pos2(x as f32 / self.ppp, y as f32 / self.ppp);
        self.events.push(egui::Event::PointerMoved(p));
        let pressed = match phase {
            Phase::Down => Some(true),
            Phase::Up => Some(false),
            Phase::Move => None,
        };
        if let Some(pressed) = pressed {
            self.events.push(egui::Event::PointerButton { pos: p, button: egui::PointerButton::Primary, pressed, modifiers: Default::default() });
        }
        if phase == Phase::Up {
            self.events.push(egui::Event::PointerGone);
        }
        self.pointer = if phase == Phase::Up { None } else { Some(p) };
    }

    /// true when the point (physical pixels) is over a window or widget of the last frame: the game ignores it
    pub fn covers(&self, x: f64, y: f64) -> bool {
        let p = egui::pos2(x as f32 / self.ppp, y as f32 / self.ppp);
        self.ctx.layer_id_at(p).is_some_and(|l| l.order != egui::Order::Background)
    }

    /// Lays out one frame (`build` adds the windows and widgets) and draws it over `view`.
    #[allow(clippy::too_many_arguments)]
    pub fn frame(&mut self, d: &wgpu::Device, q: &wgpu::Queue, enc: &mut wgpu::CommandEncoder, view: &wgpu::TextureView, w: u32, h: u32, build: impl FnMut(&egui::Context)) {
        let size = egui::vec2(w as f32 / self.ppp, h as f32 / self.ppp);
        let mut input = egui::RawInput {
            screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, size)),
            time: Some(self.start.elapsed().as_secs_f64()),
            events: std::mem::take(&mut self.events),
            ..Default::default()
        };
        input.viewports.entry(egui::ViewportId::ROOT).or_default().native_pixels_per_point = Some(self.ppp);
        let out = self.ctx.run_pass(input, build);
        for (id, deltas) in &out.textures_delta.set {
            for delta in deltas {
                self.set_texture(d, q, *id, delta);
            }
        }
        let prims = self.ctx.tessellate(out.shapes, self.ppp);
        q.write_buffer(&self.ubuf, 0, &[size.x.to_le_bytes(), size.y.to_le_bytes(), [0; 4], [0; 4]].concat());
        // vertices and indices of all meshes in one upload (grown when a frame needs more)
        let (mut vb, mut ib, mut draws) = (Vec::new(), Vec::new(), Vec::new());
        for p in &prims {
            if let egui::epaint::Primitive::Mesh(m) = &p.primitive {
                let (v0, i0) = (vb.len() as u32 / 20, ib.len() as u32 / 4);
                for v in &m.vertices {
                    vb.extend_from_slice(&v.pos.x.to_le_bytes());
                    vb.extend_from_slice(&v.pos.y.to_le_bytes());
                    vb.extend_from_slice(&v.uv.x.to_le_bytes());
                    vb.extend_from_slice(&v.uv.y.to_le_bytes());
                    vb.extend_from_slice(&v.color.to_array());
                }
                for i in &m.indices {
                    ib.extend_from_slice(&(i + v0).to_le_bytes());
                }
                draws.push((p.clip_rect, m.texture_id, i0, m.indices.len() as u32));
            }
        }
        if vb.len() as u64 > self.vbuf.size() {
            self.vbuf = d.create_buffer(&wgpu::BufferDescriptor { label: Some("ui v"), size: (vb.len() as u64).next_power_of_two(), usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        }
        if ib.len() as u64 > self.ibuf.size() {
            self.ibuf = d.create_buffer(&wgpu::BufferDescriptor { label: Some("ui i"), size: (ib.len() as u64).next_power_of_two(), usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        }
        if !vb.is_empty() {
            q.write_buffer(&self.vbuf, 0, &vb);
            q.write_buffer(&self.ibuf, 0, &ib);
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("ui"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store } })],
                ..Default::default()
            });
            p.set_pipeline(&self.pipeline);
            p.set_bind_group(0, &self.ubg, &[]);
            p.set_vertex_buffer(0, self.vbuf.slice(..));
            p.set_index_buffer(self.ibuf.slice(..), wgpu::IndexFormat::Uint32);
            for (clip, tex, i0, n) in draws {
                let Some(t) = self.textures.get(&tex) else { continue };
                let x0 = (clip.min.x * self.ppp).clamp(0.0, w as f32) as u32;
                let y0 = (clip.min.y * self.ppp).clamp(0.0, h as f32) as u32;
                let x1 = (clip.max.x * self.ppp).clamp(0.0, w as f32) as u32;
                let y1 = (clip.max.y * self.ppp).clamp(0.0, h as f32) as u32;
                if x1 <= x0 || y1 <= y0 {
                    continue;
                }
                p.set_scissor_rect(x0, y0, x1 - x0, y1 - y0);
                p.set_bind_group(1, &t.bg, &[]);
                p.draw_indexed(i0..i0 + n, 0, 0..1);
            }
        }
        for id in &out.textures_delta.free {
            self.textures.remove(id);
        }
    }

    fn set_texture(&mut self, d: &wgpu::Device, q: &wgpu::Queue, id: egui::TextureId, delta: &egui::epaint::ImageDelta) {
        let egui::ImageData::Color(img) = &delta.image;
        let img: &Arc<egui::ColorImage> = img;
        let [w, h] = img.size;
        let px: Vec<u8> = img.pixels.iter().flat_map(|c| c.to_array()).collect();
        let size = wgpu::Extent3d { width: w as u32, height: h as u32, depth_or_array_layers: 1 };
        let origin = match delta.pos {
            Some([x, y]) => wgpu::Origin3d { x: x as u32, y: y as u32, z: 0 },
            None => {
                let tex = d.create_texture(&wgpu::TextureDescriptor {
                    label: Some("ui tex"),
                    size,
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: wgpu::TextureDimension::D2,
                    format: wgpu::TextureFormat::Rgba8Unorm,
                    usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                    view_formats: &[],
                });
                let view = tex.create_view(&Default::default());
                let bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("ui tex"),
                    layout: &self.tex_layout,
                    entries: &[wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&view) }, wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::Sampler(&self.sampler) }],
                });
                self.textures.insert(id, Tex { tex, bg });
                wgpu::Origin3d::ZERO
            }
        };
        let Some(t) = self.textures.get(&id) else { return };
        q.write_texture(
            wgpu::TexelCopyTextureInfo { texture: &t.tex, mip_level: 0, origin, aspect: wgpu::TextureAspect::All },
            &px,
            wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(w as u32 * 4), rows_per_image: Some(h as u32) },
            size,
        );
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Phase {
    Down,
    Move,
    Up,
}
