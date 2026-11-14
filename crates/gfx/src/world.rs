//! The village drawn with the game's own WORLD_SHADER (vsTerrain + fsTerrain / fsLeaf, dream world) into an HDR
//! target, then tone-mapped to the screen. Bind group 0 mirrors renderer.js `L0` binding for binding; resources the
//! native client does not have yet (shadows, AO, SSR, props, particles, environment bake) are neutral stand-ins.
use mezdu_core::{f32s, MacroMesh, Pack, PerFrame};
use wgpu::util::DeviceExt;

const HDR: wgpu::TextureFormat = wgpu::TextureFormat::Rgba16Float;
const GBUF: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
const DEPTH: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;

// Stand-in for COMP_SHADER until stage 5: the same exposure, AgX curve, 3D LUT and dream grade as the end of fsComp
// (src/gfx/wgsl.js), without fog, sky, bloom, DOF, vignette and grain.
const PRESENT_WGSL: &str = r#"
@group(0) @binding(0) var hdr: texture_2d<f32>;
@group(0) @binding(1) var<uniform> P: vec4f; // x: exposure
@group(0) @binding(2) var lut: texture_3d<f32>;
@group(0) @binding(3) var smp: sampler;
@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
  let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
  return vec4f(p * 2.0 - 1.0, 0.0, 1.0);
}
fn agxCurve(x: vec3f) -> vec3f {
  let x2 = x * x;
  let x4 = x2 * x2;
  return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}
fn agx(c: vec3f) -> vec3f {
  let toAgx = mat3x3f(0.842479062253094, 0.0423282422610123, 0.0423756549057051, 0.0784335999999992, 0.878468636469772, 0.0784336, 0.0792237451477643, 0.0791661274605434, 0.879142973793104);
  let fromAgx = mat3x3f(1.19687900512017, -0.0528968517574562, -0.0529716355144438, -0.0980208811401368, 1.15190312990417, -0.0980434501171241, -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
  var v = toAgx * max(c, vec3f(0.0));
  v = clamp((log2(max(v, vec3f(1e-10))) + 12.47393) / 16.5, vec3f(0.0), vec3f(1.0));
  v = agxCurve(v);
  let l = dot(v, vec3f(0.2126, 0.7152, 0.0722));
  v = pow(max(v, vec3f(0.0)), vec3f(1.08));
  v = max(vec3f(l) + (v - vec3f(l)) * 1.3, vec3f(0.0));
  return pow(max(fromAgx * v, vec3f(0.0)), vec3f(2.2));
}
@fragment fn fs(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let c = clamp(agx(textureLoad(hdr, vec2i(fc.xy), 0).rgb * P.x), vec3f(0.0), vec3f(1.0));
  let g = textureSampleLevel(lut, smp, c * (15.0 / 16.0) + (0.5 / 16.0), 0.0).rgb;
  let d = mix(g, g * g * (3.0 - 2.0 * g), 0.35) * vec3f(1.0, 1.0, 0.99) + vec3f(0.006, 0.008, 0.012);
  return vec4f(pow(max(d, vec3f(0.0)), vec3f(1.0 / 2.2)), 1.0);
}
"#;

struct Draw {
    base: u32,
    opaque: u32,
    leaves: u32,
    leaf_base: u32,
}

pub struct World {
    frame: Vec<f32>,
    pf: PerFrame,
    frame_buf: wgpu::Buffer,
    bg0: wgpu::BindGroup,
    bg1: wgpu::BindGroup,
    idx: wgpu::Buffer,
    p_terrain: wgpu::RenderPipeline,
    p_leaf: wgpu::RenderPipeline,
    p_present: wgpu::RenderPipeline,
    present_layout: wgpu::BindGroupLayout,
    present_u: wgpu::Buffer,
    lut: wgpu::TextureView,
    lin_smp: wgpu::Sampler,
    targets: Option<Targets>,
    draws: Vec<Draw>,
    pub quads: u32,
    pub calls: u32,
    prev_vp: [f32; 16],
}

struct Targets {
    w: u32,
    h: u32,
    hdr: wgpu::TextureView,
    gbuf: wgpu::TextureView,
    depth: wgpu::TextureView,
    present_bg: wgpu::BindGroup,
}

fn tex(d: &wgpu::Device, label: &str, size: wgpu::Extent3d, dim: wgpu::TextureDimension, format: wgpu::TextureFormat, mips: u32, usage: wgpu::TextureUsages) -> wgpu::Texture {
    d.create_texture(&wgpu::TextureDescriptor { label: Some(label), size, mip_level_count: mips, sample_count: 1, dimension: dim, format, usage, view_formats: &[] })
}

fn ext(w: u32, h: u32, l: u32) -> wgpu::Extent3d {
    wgpu::Extent3d { width: w, height: h, depth_or_array_layers: l }
}

fn upload(q: &wgpu::Queue, t: &wgpu::Texture, mip: u32, data: &[u8], bpr: u32, rows: u32, size: wgpu::Extent3d) {
    q.write_texture(
        wgpu::TexelCopyTextureInfo { texture: t, mip_level: mip, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
        data,
        wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(bpr), rows_per_image: Some(rows) },
        size,
    );
}

impl World {
    pub fn new(d: &wgpu::Device, q: &wgpu::Queue, surface_format: wgpu::TextureFormat, pack: &Pack, chapter: u32) -> Result<Self, String> {
        let m = &pack.manifest;
        let c = &m.constants;
        let pf = m.per_frame.ok_or("pack has no perFrame (old export)")?;
        let frame = f32s(&pack.read(&format!("frame/ch{chapter}.bin"))?);
        let world_src = String::from_utf8(pack.read("shaders/world.wgsl")?).map_err(|e| e.to_string())?;
        let tb = wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST;

        // atlas: detail colour and pbr, 5 mips each
        let mut atlas = Vec::new();
        for kind in ["det", "pbr"] {
            let t = tex(d, kind, ext(c.ATLAS_W, c.ATLAS_H, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba8Unorm, c.ATLAS_MIPS, tb);
            for l in 0..c.ATLAS_MIPS {
                let data = pack.read_data(&format!("atlas/{kind}_L{l}.bin.zst"))?;
                let (w, h) = (c.ATLAS_W >> l, c.ATLAS_H >> l);
                upload(q, &t, l, &data, w * 4, h, ext(w, h, 1));
            }
            atlas.push(t.create_view(&Default::default()));
        }
        let view3d = wgpu::TextureViewDescriptor { dimension: Some(wgpu::TextureViewDimension::D3), ..Default::default() };
        let noise = tex(d, "noise3", ext(32, 32, 32), wgpu::TextureDimension::D3, wgpu::TextureFormat::R8Unorm, 1, tb);
        upload(q, &noise, 0, &pack.read("tex/fog.bin")?, 32, 32, ext(32, 32, 32));
        let lut = tex(d, "lut", ext(16, 16, 16), wgpu::TextureDimension::D3, wgpu::TextureFormat::Rgba8Unorm, 1, tb);
        upload(q, &lut, 0, &pack.read("tex/lut.bin")?, 64, 16, ext(16, 16, 16));

        // stand-ins: lit shadow maps (depth 1), no AO / SSR (flags 0 in the frame), environment = sky colour of the template
        let depth1 = tex(d, "depth1", ext(1, 1, 1), wgpu::TextureDimension::D2, DEPTH, 1, wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::RENDER_ATTACHMENT);
        let depth1v = depth1.create_view(&Default::default());
        {
            let mut enc = d.create_command_encoder(&Default::default());
            enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("clear depth1"),
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &depth1v,
                    depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Store }),
                    stencil_ops: None,
                }),
                ..Default::default()
            });
            q.submit([enc.finish()]);
        }
        let white = tex(d, "white", ext(1, 1, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba8Unorm, 1, tb);
        upload(q, &white, 0, &[255, 255, 255, 0], 4, 1, ext(1, 1, 1));
        let whitev = white.create_view(&Default::default());
        let brdf = tex(d, "brdf", ext(1, 1, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba8Unorm, 1, tb);
        upload(q, &brdf, 0, &[128, 13, 0, 255], 4, 1, ext(1, 1, 1)); // split-sum A, B of a rough dielectric
        // environment: the linear sky light of the template (skyD) on every face, until ENV_SHADER runs natively
        let sky = &frame[72..75];
        let env_px: Vec<u8> = (0..6).flat_map(|_| [sky[0], sky[1], sky[2], 1.0]).flat_map(|v| f16_bits(v).to_le_bytes()).collect();
        let env = tex(d, "env", ext(1, 1, 6), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba16Float, 1, tb);
        upload(q, &env, 0, &env_px, 8, 1, ext(1, 1, 6));
        let envv = env.create_view(&wgpu::TextureViewDescriptor { dimension: Some(wgpu::TextureViewDimension::Cube), ..Default::default() });

        let ub = wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST;
        let sb = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST;
        let frame_buf = d.create_buffer(&wgpu::BufferDescriptor { label: Some("frame"), size: (pf.floats * 4) as u64, usage: ub, mapped_at_creation: false });
        let mats = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("mats"), contents: &pack.read("materials.bin")?, usage: ub });
        let (cx, cy, cz) = (c.WX / c.CS, c.WY / c.CS, c.WZ / c.CS);
        let mut org = Vec::with_capacity((cx * cy * cz * 4) as usize);
        for ci in 0..cx * cy * cz {
            let (x, z, y) = (ci % cx, (ci / cx) % cz, ci / (cx * cz));
            org.extend_from_slice(&[(x * c.CS) as f32, (y * c.CS) as f32, (z * c.CS) as f32, 0.0]);
        }
        let as_bytes = |v: &[f32]| v.iter().flat_map(|f| f.to_le_bytes()).collect::<Vec<u8>>();
        let chunk_org = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("chunkOrg"), contents: &as_bytes(&org), usage: sb });
        let dummy_sb = d.create_buffer(&wgpu::BufferDescriptor { label: Some("empty storage"), size: 4096, usage: sb, mapped_at_creation: false });

        // mesh of the bundled tiles
        let mut faces: Vec<u32> = Vec::new();
        let mut draws = Vec::new();
        for f in m.of_kind("mesh") {
            for mm in MacroMesh::parse_tile(&pack.read_data(&f.path)?)? {
                let base = (faces.len() / 3) as u32;
                let opaque = mm.c0[0] + mm.c0[1];
                let leaf_base = base + mm.c0[0] + mm.c0[1] + mm.c0[2];
                draws.push(Draw { base, opaque, leaves: mm.c0[3] + mm.c0[4], leaf_base });
                faces.extend_from_slice(&mm.faces);
            }
        }
        if faces.is_empty() {
            return Err("pack has no mesh".into());
        }
        let quads = (faces.len() / 3) as u32;
        let face_bytes: Vec<u8> = faces.iter().flat_map(|w| w.to_le_bytes()).collect();
        let faces_buf = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("faces"), contents: &face_bytes, usage: sb });
        let max_draw = draws.iter().map(|d| d.opaque.max(d.leaves)).max().unwrap_or(0).max(1);
        let idx: Vec<u8> = (0..max_draw).flat_map(|q| { let b = q * 4; [b, b + 1, b + 2, b, b + 2, b + 3] }).flat_map(|i| i.to_le_bytes()).collect();
        let idx = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("quad idx"), contents: &idx, usage: wgpu::BufferUsages::INDEX });

        // bind group layout 0 = renderer.js L0
        let vf = wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT;
        let e = |binding: u32, ty: wgpu::BindingType| wgpu::BindGroupLayoutEntry { binding, visibility: vf, ty, count: None };
        let uni = wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None };
        let sto = wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None };
        let t = |dim: wgpu::TextureViewDimension| wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: true }, view_dimension: dim, multisampled: false };
        let td = wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Depth, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false };
        use wgpu::TextureViewDimension as V;
        let l0 = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("L0"),
            entries: &[
                e(0, uni), e(1, td), e(2, wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Comparison)), e(3, uni),
                e(4, sto), e(5, sto), e(6, sto), e(7, sto), e(8, sto), e(9, sto), e(10, t(V::D2)), e(11, sto), e(12, t(V::D3)),
                e(13, wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering)), e(14, t(V::D3)), e(15, t(V::D2)),
                e(16, t(V::Cube)), e(17, t(V::Cube)), e(18, t(V::D2)), e(19, td), e(20, t(V::D2)), e(21, t(V::D2)),
            ],
        });
        let l1 = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor { label: Some("L1T"), entries: &[e(0, sto)] });
        let shadow_smp = d.create_sampler(&wgpu::SamplerDescriptor { compare: Some(wgpu::CompareFunction::Less), mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() });
        let rep = wgpu::AddressMode::Repeat;
        let rep_smp = d.create_sampler(&wgpu::SamplerDescriptor {
            address_mode_u: rep, address_mode_v: rep, address_mode_w: rep,
            mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, mipmap_filter: wgpu::MipmapFilterMode::Linear,
            ..Default::default()
        });
        let noisev = noise.create_view(&view3d);
        let lutv = lut.create_view(&view3d);
        let brdfv = brdf.create_view(&Default::default());
        fn buf(b: &wgpu::Buffer) -> wgpu::BindingResource<'_> {
            b.as_entire_binding()
        }
        fn tv(v: &wgpu::TextureView) -> wgpu::BindingResource<'_> {
            wgpu::BindingResource::TextureView(v)
        }
        fn be(binding: u32, resource: wgpu::BindingResource<'_>) -> wgpu::BindGroupEntry<'_> {
            wgpu::BindGroupEntry { binding, resource }
        }
        let bg0 = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_world"),
            layout: &l0,
            entries: &[
                be(0, buf(&frame_buf)), be(1, tv(&depth1v)), be(2, wgpu::BindingResource::Sampler(&shadow_smp)), be(3, buf(&mats)),
                be(4, buf(&chunk_org)), be(5, buf(&dummy_sb)), be(6, buf(&dummy_sb)), be(7, buf(&dummy_sb)), be(8, buf(&dummy_sb)),
                be(9, buf(&dummy_sb)), be(10, tv(&atlas[0])), be(11, buf(&dummy_sb)), be(12, tv(&noisev)),
                be(13, wgpu::BindingResource::Sampler(&rep_smp)), be(14, tv(&lutv)), be(15, tv(&atlas[1])),
                be(16, tv(&envv)), be(17, tv(&envv)), be(18, tv(&brdfv)), be(19, tv(&depth1v)), be(20, tv(&whitev)), be(21, tv(&whitev)),
            ],
        });
        let bg1 = d.create_bind_group(&wgpu::BindGroupDescriptor { label: Some("bg_faces"), layout: &l1, entries: &[be(0, buf(&faces_buf))] });

        let module = d.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("world.wgsl"), source: wgpu::ShaderSource::Wgsl(world_src.into()) });
        let layout = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("layT"), bind_group_layouts: &[Some(&l0), Some(&l1)], immediate_size: 0 });
        let consts: &[(&str, f64)] = &[("WMODE", 0.0)];
        let pipe = |label: &str, fs: &str, cull: Option<wgpu::Face>| {
            let opts = wgpu::PipelineCompilationOptions { constants: consts, ..Default::default() };
            d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(label),
                layout: Some(&layout),
                vertex: wgpu::VertexState { module: &module, entry_point: Some("vsTerrain"), compilation_options: opts.clone(), buffers: &[] },
                fragment: Some(wgpu::FragmentState {
                    module: &module,
                    entry_point: Some(fs),
                    compilation_options: opts,
                    targets: &[Some(HDR.into()), Some(GBUF.into())],
                }),
                primitive: wgpu::PrimitiveState { cull_mode: cull, ..Default::default() },
                depth_stencil: Some(wgpu::DepthStencilState {
                    format: DEPTH,
                    depth_write_enabled: Some(true),
                    depth_compare: Some(wgpu::CompareFunction::Less),
                    stencil: Default::default(),
                    bias: Default::default(),
                }),
                multisample: Default::default(),
                multiview_mask: None,
                cache: None,
            })
        };
        let p_terrain = pipe("terrain0", "fsTerrain", Some(wgpu::Face::Back));
        let p_leaf = pipe("leaf0", "fsLeaf", None);

        let pm = d.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("present"), source: wgpu::ShaderSource::Wgsl(PRESENT_WGSL.into()) });
        let present_layout = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("present"),
            entries: &[
                wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: false }, view_dimension: V::D2, multisampled: false }, count: None },
                wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::FRAGMENT, ty: uni, count: None },
                wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::FRAGMENT, ty: t(V::D3), count: None },
                wgpu::BindGroupLayoutEntry { binding: 3, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
            ],
        });
        let pl = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&present_layout)], immediate_size: 0 });
        let p_present = d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("present"),
            layout: Some(&pl),
            vertex: wgpu::VertexState { module: &pm, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[] },
            fragment: Some(wgpu::FragmentState { module: &pm, entry_point: Some("fs"), compilation_options: Default::default(), targets: &[Some(surface_format.into())] }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: Default::default(),
            multiview_mask: None,
            cache: None,
        });
        let exposure = frame[132] * frame[271];
        let present_u = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("present u"), contents: &as_bytes(&[exposure, 0.0, 0.0, 0.0]), usage: ub });
        log::info!("world: {} macro chunks, {} quads, exposure {:.2}", draws.len(), quads, exposure);
        let lin_smp = d.create_sampler(&wgpu::SamplerDescriptor { mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() });
        Ok(World { frame, pf, frame_buf, bg0, bg1, idx, p_terrain, p_leaf, p_present, present_layout, present_u, lut: lutv, lin_smp, targets: None, draws, quads, calls: 0, prev_vp: glam::Mat4::IDENTITY.to_cols_array() })
    }

    fn targets(&mut self, d: &wgpu::Device, w: u32, h: u32) {
        if self.targets.as_ref().is_some_and(|t| t.w == w && t.h == h) {
            return;
        }
        let u = wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING;
        let hdr = tex(d, "scene", ext(w, h, 1), wgpu::TextureDimension::D2, HDR, 1, u).create_view(&Default::default());
        let gbuf = tex(d, "gbuf", ext(w, h, 1), wgpu::TextureDimension::D2, GBUF, 1, u).create_view(&Default::default());
        let depth = tex(d, "depth", ext(w, h, 1), wgpu::TextureDimension::D2, DEPTH, 1, u).create_view(&Default::default());
        let present_bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("present"),
            layout: &self.present_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&hdr) },
                wgpu::BindGroupEntry { binding: 1, resource: self.present_u.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&self.lut) },
                wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::Sampler(&self.lin_smp) },
            ],
        });
        self.targets = Some(Targets { w, h, hdr, gbuf, depth, present_bg });
    }

    /// Writes the camera into the frame uniform and records the scene + present passes.
    #[allow(clippy::too_many_arguments)]
    pub fn render(&mut self, d: &wgpu::Device, q: &wgpu::Queue, enc: &mut wgpu::CommandEncoder, out: &wgpu::TextureView, w: u32, h: u32, cam: &Camera, time: f32) {
        self.targets(d, w, h);
        let aspect = w as f32 / h.max(1) as f32;
        let proj = perspective(cam.fov_y, aspect, 0.1, 400.0);
        let view = look_to(cam.pos, cam.forward(), glam::Vec3::Y);
        let vp = proj * view;
        let pf = self.pf;
        let f = &mut self.frame;
        f[pf.view_proj..pf.view_proj + 16].copy_from_slice(&vp.to_cols_array());
        f[pf.inv_view_proj..pf.inv_view_proj + 16].copy_from_slice(&vp.inverse().to_cols_array());
        f[pf.prev_vp..pf.prev_vp + 16].copy_from_slice(&self.prev_vp);
        self.prev_vp = vp.to_cols_array();
        let right = view.row(0);
        let up = view.row(1);
        f[pf.cam..pf.cam + 3].copy_from_slice(&cam.pos.to_array());
        f[pf.time] = time;
        f[pf.cam_right..pf.cam_right + 3].copy_from_slice(&[right.x, right.y, right.z]);
        f[pf.cam_up..pf.cam_up + 3].copy_from_slice(&[up.x, up.y, up.z]);
        f[pf.res..pf.res + 4].copy_from_slice(&[w as f32, h as f32, 1.0 / w as f32, 1.0 / h as f32]);
        f[pf.out_res..pf.out_res + 4].copy_from_slice(&[w as f32, h as f32, 1.0 / w as f32, 1.0 / h as f32]);
        f[pf.focal] = h as f32 * 0.5 * proj.y_axis.y;
        let bytes: &[u8] = unsafe { std::slice::from_raw_parts(f.as_ptr() as *const u8, f.len() * 4) };
        q.write_buffer(&self.frame_buf, 0, bytes);

        let t = self.targets.as_ref().expect("targets");
        let sky = [self.frame[276] as f64, self.frame[277] as f64, self.frame[278] as f64]; // skyPD[1]: horizon
        self.calls = 0;
        {
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("scene"),
                color_attachments: &[
                    Some(wgpu::RenderPassColorAttachment { view: &t.hdr, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r: sky[0], g: sky[1], b: sky[2], a: 1.0 }), store: wgpu::StoreOp::Store } }),
                    Some(wgpu::RenderPassColorAttachment { view: &t.gbuf, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT), store: wgpu::StoreOp::Discard } }),
                ],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &t.depth,
                    depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Discard }),
                    stencil_ops: None,
                }),
                ..Default::default()
            });
            p.set_bind_group(0, &self.bg0, &[]);
            p.set_bind_group(1, &self.bg1, &[]);
            p.set_index_buffer(self.idx.slice(..), wgpu::IndexFormat::Uint32);
            p.set_pipeline(&self.p_terrain);
            for dr in &self.draws {
                if dr.opaque > 0 {
                    p.draw_indexed(0..dr.opaque * 6, (dr.base * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
            p.set_pipeline(&self.p_leaf);
            for dr in &self.draws {
                if dr.leaves > 0 {
                    p.draw_indexed(0..dr.leaves * 6, (dr.leaf_base * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
        }
        let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("present"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: out, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } })],
            ..Default::default()
        });
        p.set_pipeline(&self.p_present);
        p.set_bind_group(0, &t.present_bg, &[]);
        p.draw(0..3, 0..1);
    }
}

/// f32 -> IEEE half (normal range, round to nearest is not needed for stand-in colours).
fn f16_bits(v: f32) -> u16 {
    let b = v.to_bits();
    let sign = ((b >> 16) & 0x8000) as u16;
    let e = ((b >> 23) & 0xff) as i32 - 127 + 15;
    if v == 0.0 || e <= 0 {
        return sign;
    }
    if e >= 31 {
        return sign | 0x7bff;
    }
    sign | ((e as u16) << 10) | ((b >> 13) & 0x3ff) as u16
}

/// Right-handed perspective with depth 0..1 (WebGPU), as engine/math.js `perspective`.
fn perspective(fov_y: f32, aspect: f32, near: f32, far: f32) -> glam::Mat4 {
    let f = 1.0 / (fov_y * 0.5).tan();
    glam::Mat4::from_cols(
        glam::Vec4::new(f / aspect, 0.0, 0.0, 0.0),
        glam::Vec4::new(0.0, f, 0.0, 0.0),
        glam::Vec4::new(0.0, 0.0, far / (near - far), -1.0),
        glam::Vec4::new(0.0, 0.0, near * far / (near - far), 0.0),
    )
}

fn look_to(eye: glam::Vec3, dir: glam::Vec3, up: glam::Vec3) -> glam::Mat4 {
    let f = dir.normalize();
    let s = f.cross(up).normalize();
    let u = s.cross(f);
    glam::Mat4::from_cols(
        glam::Vec4::new(s.x, u.x, -f.x, 0.0),
        glam::Vec4::new(s.y, u.y, -f.y, 0.0),
        glam::Vec4::new(s.z, u.z, -f.z, 0.0),
        glam::Vec4::new(-s.dot(eye), -u.dot(eye), f.dot(eye), 1.0),
    )
}

/// Free-flying camera: yaw/pitch in radians, position in metres.
#[derive(Clone, Copy, Debug)]
pub struct Camera {
    pub pos: glam::Vec3,
    pub yaw: f32,
    pub pitch: f32,
    pub fov_y: f32,
}

impl Camera {
    pub fn forward(&self) -> glam::Vec3 {
        glam::Vec3::new(self.yaw.sin() * self.pitch.cos(), self.pitch.sin(), -self.yaw.cos() * self.pitch.cos())
    }
    pub fn right(&self) -> glam::Vec3 {
        glam::Vec3::new(self.yaw.cos(), 0.0, self.yaw.sin())
    }
}
