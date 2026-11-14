//! The village with the game's own shaders, pass by pass as renderer.js does it:
//! shadow cascades (WORLD_SHADER vsShadow / fsShadowLeaf) -> main pass (vsTerrain + fsTerrain / fsLeaf, dream world,
//! HDR + G-buffer) -> final pass (COMP_SHADER fsComp: sky, fog, exposure, AgX, LUT, vignette, grain).
//! The sky reflections are baked once with ENV_SHADER (fsEnv, fsLut). Bind group 0 mirrors renderer.js `L0`;
//! still missing (neutral stand-ins): AO, SSR, volumetric light, DOF, TAA history, props, grass, water, particles.
use crate::props::{frustum_planes, Props};
use mezdu_core::{f32s, MacroMesh, Pack, PerFrame};
use wgpu::util::DeviceExt;

const HDR: wgpu::TextureFormat = wgpu::TextureFormat::Rgba16Float;
const GBUF: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
const DEPTH: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;
/// QUALITY of src/main.js: shadow map size, near / far cascade extent (metres)
const SHADOW_SIZE: u32 = 1024;
const NEAR_EXT: f32 = 14.0;
const FAR_EXT: f32 = 40.0;
const ENV_SIZE: u32 = 32;
const ENV_MIPS: u32 = 5;

struct Draw {
    cx: f32,
    cz: f32,
    base: u32,
    opaque: u32,
    leaves: u32,
    leaf_base: u32,
}

#[derive(Default)]
struct Cascade {
    cx: f32,
    cz: f32,
    sun: [f32; 3],
    valid: bool,
    mat: [f32; 16],
    bias: f32,
}

pub struct World {
    frame: Vec<f32>,
    frame_c1: Vec<f32>,
    pf: PerFrame,
    frame_buf: wgpu::Buffer,
    frame_buf_c1: wgpu::Buffer,
    bg0: wgpu::BindGroup,
    bg0_shadow: [wgpu::BindGroup; 2],
    bg1: wgpu::BindGroup,
    idx: wgpu::Buffer,
    shadow: [wgpu::TextureView; 2],
    casc: [Cascade; 2],
    p_terrain: wgpu::RenderPipeline,
    p_leaf: wgpu::RenderPipeline,
    p_shadow: wgpu::RenderPipeline,
    p_shadow_leaf: wgpu::RenderPipeline,
    p_comp: wgpu::RenderPipeline,
    props: Option<Props>,
    bg_model: Option<wgpu::BindGroup>,
    p_prop: wgpu::RenderPipeline,
    p_tree: wgpu::RenderPipeline,
    p_prop_shadow: wgpu::RenderPipeline,
    pub instances: u32,
    comp_res: CompRes,
    targets: Option<Targets>,
    draws: Vec<Draw>,
    pub quads: u32,
    pub calls: u32,
    pub shadow_passes: u32,
    prev_vp: [f32; 16],
}

/// the inputs of fsComp that are not render targets of this frame
struct CompRes {
    vol: wgpu::TextureView,
    dof: wgpu::TextureView,
    lut: wgpu::TextureView,
    lin_smp: wgpu::Sampler,
}

struct Targets {
    w: u32,
    h: u32,
    hdr: wgpu::TextureView,
    gbuf: wgpu::TextureView,
    depth: wgpu::TextureView,
    hist: wgpu::TextureView,
    comp_bg: wgpu::BindGroup,
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

fn bytes(v: &[f32]) -> &[u8] {
    // SAFETY: f32 has no padding and any bit pattern is a valid u8 sequence
    unsafe { std::slice::from_raw_parts(v.as_ptr() as *const u8, std::mem::size_of_val(v)) }
}

fn buf(b: &wgpu::Buffer) -> wgpu::BindingResource<'_> {
    b.as_entire_binding()
}
fn tv(v: &wgpu::TextureView) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::TextureView(v)
}
fn be(binding: u32, resource: wgpu::BindingResource<'_>) -> wgpu::BindGroupEntry<'_> {
    wgpu::BindGroupEntry { binding, resource }
}

fn color_pass<'a>(enc: &'a mut wgpu::CommandEncoder, label: &str, view: &wgpu::TextureView) -> wgpu::RenderPass<'a> {
    enc.begin_render_pass(&wgpu::RenderPassDescriptor {
        label: Some(label),
        color_attachments: &[Some(wgpu::RenderPassColorAttachment { view, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } })],
        ..Default::default()
    })
}

fn module(d: &wgpu::Device, pack: &Pack, name: &str) -> Result<wgpu::ShaderModule, String> {
    let src = String::from_utf8(pack.read(&format!("shaders/{name}.wgsl"))?).map_err(|e| e.to_string())?;
    Ok(d.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some(name), source: wgpu::ShaderSource::Wgsl(src.into()) }))
}

impl World {
    pub fn new(d: &wgpu::Device, q: &wgpu::Queue, surface_format: wgpu::TextureFormat, pack: &Pack, chapter: u32) -> Result<Self, String> {
        let m = &pack.manifest;
        let c = &m.constants;
        let pf = m.per_frame.ok_or("pack has no perFrame (old export)")?;
        let mut frame = f32s(&pack.read(&format!("frame/ch{chapter}.bin"))?);
        frame[134] = 0.75 / SHADOW_SIZE as f32; // grade.z: shadow texel
        frame[143] = f32::from_bits(1); // counts.w (u32): shadows on
        let tb = wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST;
        let ra = wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::RENDER_ATTACHMENT;
        let ub = wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST;
        let sb = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST;
        let frame_buf = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("frame"), contents: bytes(&frame), usage: ub });
        let frame_buf_c1 = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("frame c1"), contents: bytes(&frame), usage: ub });

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
        let noisev = noise.create_view(&view3d);
        let lutv = lut.create_view(&view3d);

        // shadow cascades and the 1x1 depth that stands in for them while they are being drawn
        let shadow = [0, 1].map(|k| tex(d, if k == 0 { "shadow near" } else { "shadow far" }, ext(SHADOW_SIZE, SHADOW_SIZE, 1), wgpu::TextureDimension::D2, DEPTH, 1, ra).create_view(&Default::default()));
        let depth1v = tex(d, "depth1", ext(1, 1, 1), wgpu::TextureDimension::D2, DEPTH, 1, ra).create_view(&Default::default());
        // AO / SSR stand-in (flags fx.x = fx2.x = 0 say they are not valid)
        let white = tex(d, "white", ext(1, 1, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba8Unorm, 1, tb);
        upload(q, &white, 0, &[255, 255, 255, 0], 4, 1, ext(1, 1, 1));
        let whitev = white.create_view(&Default::default());

        // sky reflections and the split-sum BRDF table, baked with ENV_SHADER as renderer.js createEnvMaps / bakeEnv
        let envm = module(d, pack, "env")?;
        let lenv = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("L_env"),
            entries: &[
                wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None },
                wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: true, min_binding_size: wgpu::BufferSize::new(16) }, count: None },
            ],
        });
        let full = |label: &str, m: &wgpu::ShaderModule, fs: &str, layout: Option<&wgpu::PipelineLayout>, targets: &[Option<wgpu::ColorTargetState>]| {
            d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(label),
                layout,
                vertex: wgpu::VertexState { module: m, entry_point: Some("vsFull"), compilation_options: Default::default(), buffers: &[] },
                fragment: Some(wgpu::FragmentState { module: m, entry_point: Some(fs), compilation_options: Default::default(), targets }),
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                multiview_mask: None,
                cache: None,
            })
        };
        let lenv_pl = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&lenv)], immediate_size: 0 });
        let p_env = full("env", &envm, "fsEnv", Some(&lenv_pl), &[Some(HDR.into())]);
        let p_lut = full("brdfLut", &envm, "fsLut", None, &[Some(wgpu::TextureFormat::Rg16Float.into())]);
        let mut bake = vec![0u8; (2 * ENV_MIPS * 6 * 256) as usize];
        let mut env_views = Vec::new();
        let mut faces = Vec::new();
        for e in 0..2u32 {
            let t = tex(d, "env", ext(ENV_SIZE, ENV_SIZE, 6), wgpu::TextureDimension::D2, HDR, ENV_MIPS, ra);
            env_views.push(t.create_view(&wgpu::TextureViewDescriptor { dimension: Some(wgpu::TextureViewDimension::Cube), ..Default::default() }));
            for mip in 0..ENV_MIPS {
                for f in 0..6u32 {
                    let o = faces.len() * 256;
                    bake[o..o + 4].copy_from_slice(&f.to_le_bytes());
                    bake[o + 4..o + 8].copy_from_slice(&e.to_le_bytes());
                    bake[o + 8..o + 12].copy_from_slice(&(mip as f32 / (ENV_MIPS - 1) as f32).to_le_bytes());
                    bake[o + 12..o + 16].copy_from_slice(&((ENV_SIZE >> mip) as f32).to_le_bytes());
                    faces.push(t.create_view(&wgpu::TextureViewDescriptor { dimension: Some(wgpu::TextureViewDimension::D2), base_mip_level: mip, mip_level_count: Some(1), base_array_layer: f, array_layer_count: Some(1), ..Default::default() }));
                }
            }
        }
        let bake_buf = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("env bake"), contents: &bake, usage: ub });
        let bg_env = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_env"),
            layout: &lenv,
            entries: &[be(0, buf(&frame_buf)), be(1, wgpu::BindingResource::Buffer(wgpu::BufferBinding { buffer: &bake_buf, offset: 0, size: wgpu::BufferSize::new(16) }))],
        });
        let brdf = tex(d, "brdf", ext(64, 64, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rg16Float, 1, ra);
        let brdfv = brdf.create_view(&Default::default());
        {
            let mut enc = d.create_command_encoder(&Default::default());
            for (k, v) in faces.iter().enumerate() {
                let mut p = color_pass(&mut enc, "env", v);
                p.set_pipeline(&p_env);
                p.set_bind_group(0, &bg_env, &[(k * 256) as u32]);
                p.draw(0..3, 0..1);
            }
            let mut p = color_pass(&mut enc, "brdf", &brdfv);
            p.set_pipeline(&p_lut);
            p.draw(0..3, 0..1);
            drop(p);
            q.submit([enc.finish()]);
        }

        let mats = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("mats"), contents: &pack.read("materials.bin")?, usage: ub });
        let (cx, cy, cz) = (c.WX / c.CS, c.WY / c.CS, c.WZ / c.CS);
        let mut org = Vec::with_capacity((cx * cy * cz * 4) as usize);
        for ci in 0..cx * cy * cz {
            let (x, z, y) = (ci % cx, (ci / cx) % cz, ci / (cx * cz));
            org.extend_from_slice(&[(x * c.CS) as f32, (y * c.CS) as f32, (z * c.CS) as f32, 0.0]);
        }
        let chunk_org = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("chunkOrg"), contents: bytes(&org), usage: sb });
        let dummy_sb = d.create_buffer(&wgpu::BufferDescriptor { label: Some("empty storage"), size: 4096, usage: sb, mapped_at_creation: false });

        // meshes of the bundled tiles
        let mut fw: Vec<u32> = Vec::new();
        let mut draws = Vec::new();
        for f in m.of_kind("mesh") {
            for mm in MacroMesh::parse_tile(&pack.read_data(&f.path)?)? {
                let base = (fw.len() / 3) as u32;
                draws.push(Draw {
                    cx: (mm.mcx * 64 + 32) as f32 * c.VS,
                    cz: (mm.mcz * 64 + 32) as f32 * c.VS,
                    base,
                    opaque: mm.c0[0] + mm.c0[1],
                    leaves: mm.c0[3] + mm.c0[4],
                    leaf_base: base + mm.c0[0] + mm.c0[1] + mm.c0[2],
                });
                fw.extend_from_slice(&mm.faces);
            }
        }
        if fw.is_empty() {
            return Err("pack has no mesh".into());
        }
        let quads = (fw.len() / 3) as u32;
        let faces_buf = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("faces"), contents: &fw.iter().flat_map(|w| w.to_le_bytes()).collect::<Vec<u8>>(), usage: sb });
        let props = Props::new(d, pack)?;
        let max_draw = draws.iter().map(|d| d.opaque.max(d.leaves)).max().unwrap_or(0).max(props.as_ref().map_or(1, |p| p.max_quads)).max(1);
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
        // the main pass reads the cascades; the shadow passes get the 1x1 stand-in and their own frame (shadowMat)
        let pb = |f: fn(&Props) -> &wgpu::Buffer| props.as_ref().map_or(&dummy_sb, f);
        let (minfo, mfaces, insts, vis) = (pb(|p| &p.minfo), pb(|p| &p.mfaces), pb(|p| &p.insts), pb(|p| &p.vis));
        let vis_sh = [pb(|p| &p.vis_shadow[0]), pb(|p| &p.vis_shadow[1])];
        let world_bg = |label: &str, fb: &wgpu::Buffer, s0: &wgpu::TextureView, s1: &wgpu::TextureView, vis: &wgpu::Buffer| {
            d.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some(label),
                layout: &l0,
                entries: &[
                    be(0, buf(fb)), be(1, tv(s0)), be(2, wgpu::BindingResource::Sampler(&shadow_smp)), be(3, buf(&mats)),
                    be(4, buf(&chunk_org)), be(5, buf(minfo)), be(6, buf(mfaces)), be(7, buf(insts)), be(8, buf(vis)),
                    be(9, buf(&dummy_sb)), be(10, tv(&atlas[0])), be(11, buf(&dummy_sb)), be(12, tv(&noisev)),
                    be(13, wgpu::BindingResource::Sampler(&rep_smp)), be(14, tv(&lutv)), be(15, tv(&atlas[1])),
                    be(16, tv(&env_views[0])), be(17, tv(&env_views[1])), be(18, tv(&brdfv)), be(19, tv(s1)), be(20, tv(&whitev)), be(21, tv(&whitev)),
                ],
            })
        };
        let bg0 = world_bg("bg_world", &frame_buf, &shadow[0], &shadow[1], vis);
        let bg0_shadow = [world_bg("bg_world_shadow", &frame_buf, &depth1v, &depth1v, vis_sh[0]), world_bg("bg_world_shadow2", &frame_buf_c1, &depth1v, &depth1v, vis_sh[1])];
        let l1p = d.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("L1P"),
            entries: &[wgpu::BindGroupLayoutEntry { binding: 0, visibility: vf, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: true, min_binding_size: wgpu::BufferSize::new(16) }, count: None }],
        });
        let bg_model = props.as_ref().map(|p| {
            d.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("bg_model"),
                layout: &l1p,
                entries: &[be(0, wgpu::BindingResource::Buffer(wgpu::BufferBinding { buffer: &p.model_u, offset: 0, size: wgpu::BufferSize::new(16) }))],
            })
        });
        let bg1 = d.create_bind_group(&wgpu::BindGroupDescriptor { label: Some("bg_faces"), layout: &l1, entries: &[be(0, buf(&faces_buf))] });

        let world = module(d, pack, "world")?;
        let layout = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("layT"), bind_group_layouts: &[Some(&l0), Some(&l1)], immediate_size: 0 });
        let lay_p = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("layP"), bind_group_layouts: &[Some(&l0), Some(&l1p)], immediate_size: 0 });
        let consts: &[(&str, f64)] = &[("WMODE", 0.0)];
        let opts = || wgpu::PipelineCompilationOptions { constants: consts, ..Default::default() };
        let pipe_l = |layout: &wgpu::PipelineLayout, label: &str, vs: &str, fs: Option<&str>, cull: Option<wgpu::Face>, shadow: bool| {
            let targets = [Some(HDR.into()), Some(GBUF.into())];
            d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(label),
                layout: Some(layout),
                vertex: wgpu::VertexState { module: &world, entry_point: Some(vs), compilation_options: opts(), buffers: &[] },
                fragment: fs.map(|fs| wgpu::FragmentState { module: &world, entry_point: Some(fs), compilation_options: opts(), targets: if shadow { &[] } else { &targets } }),
                primitive: wgpu::PrimitiveState { cull_mode: cull, ..Default::default() },
                depth_stencil: Some(wgpu::DepthStencilState {
                    format: DEPTH,
                    depth_write_enabled: Some(true),
                    depth_compare: Some(wgpu::CompareFunction::Less),
                    stencil: Default::default(),
                    bias: if shadow { wgpu::DepthBiasState { constant: 3, slope_scale: 2.5, clamp: 0.0 } } else { Default::default() },
                }),
                multisample: Default::default(),
                multiview_mask: None,
                cache: None,
            })
        };
        let pipe = |label: &str, vs: &str, fs: Option<&str>, cull: Option<wgpu::Face>, shadow: bool| pipe_l(&layout, label, vs, fs, cull, shadow);
        let p_prop = pipe_l(&lay_p, "props0", "vsProp", Some("fsProp"), Some(wgpu::Face::Back), false);
        let p_tree = pipe_l(&lay_p, "tree0", "vsProp", Some("fsTree"), None, false);
        let p_prop_shadow = pipe_l(&lay_p, "propShadow", "vsPropShadow", Some("fsPropShadow"), None, true);
        let p_terrain = pipe("terrain0", "vsTerrain", Some("fsTerrain"), Some(wgpu::Face::Back), false);
        let p_leaf = pipe("leaf0", "vsTerrain", Some("fsLeaf"), None, false);
        let p_shadow = pipe("shadow", "vsShadow", None, Some(wgpu::Face::Back), true);
        let p_shadow_leaf = pipe("shadowL0", "vsShadow", Some("fsShadowLeaf"), None, true);

        let compm = module(d, pack, "comp")?;
        let p_comp = full("comp", &compm, "fsComp", None, &[Some(surface_format.into()), Some(HDR.into())]);
        // no volumetric light yet: transmittance 1, nothing scattered; no depth of field
        let black = |label: &str, px: [u8; 4]| {
            let t = tex(d, label, ext(1, 1, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba8Unorm, 1, tb);
            upload(q, &t, 0, &px, 4, 1, ext(1, 1, 1));
            t.create_view(&Default::default())
        };
        let comp_res = CompRes {
            vol: black("vol", [0, 0, 0, 255]),
            dof: black("dof", [0, 0, 0, 0]),
            lut: lutv.clone(),
            lin_smp: d.create_sampler(&wgpu::SamplerDescriptor { mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() }),
        };
        log::info!("world: {} macro chunks, {} quads, exposure {:.2}", draws.len(), quads, frame[132]);
        Ok(World {
            frame_c1: frame.clone(),
            frame,
            pf,
            frame_buf,
            frame_buf_c1,
            bg0,
            bg0_shadow,
            bg1,
            idx,
            shadow,
            casc: Default::default(),
            p_terrain,
            p_leaf,
            p_shadow,
            p_shadow_leaf,
            p_comp,
            instances: props.as_ref().map_or(0, |p| p.count.len() as u32),
            props,
            bg_model,
            p_prop,
            p_tree,
            p_prop_shadow,
            comp_res,
            targets: None,
            draws,
            quads,
            calls: 0,
            shadow_passes: 0,
            prev_vp: glam::Mat4::IDENTITY.to_cols_array(),
        })
    }

    fn targets(&mut self, d: &wgpu::Device, w: u32, h: u32) {
        if self.targets.as_ref().is_some_and(|t| t.w == w && t.h == h) {
            return;
        }
        let u = wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING;
        let mk = |label: &str, f: wgpu::TextureFormat| tex(d, label, ext(w, h, 1), wgpu::TextureDimension::D2, f, 1, u).create_view(&Default::default());
        let (hdr, gbuf, depth, hist) = (mk("scene", HDR), mk("gbuf", GBUF), mk("depth", DEPTH), mk("hist", HDR));
        let hist_in = mk("hist in", HDR); // TAA is off: last frame's history is never read (F.taa.w = 0)
        let r = &self.comp_res;
        let comp_bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_comp"),
            layout: &self.p_comp.get_bind_group_layout(0),
            entries: &[
                be(0, buf(&self.frame_buf)), be(1, tv(&hdr)), be(2, tv(&r.vol)), be(3, tv(&depth)), be(4, wgpu::BindingResource::Sampler(&r.lin_smp)),
                be(7, tv(&r.dof)), be(8, tv(&hist_in)), be(9, tv(&gbuf)), be(10, tv(&r.lut)),
            ],
        });
        self.targets = Some(Targets { w, h, hdr, gbuf, depth, hist, comp_bg });
    }

    /// renderer.js updateCascade: an orthographic box around `center`, snapped to a grid and to the texels;
    /// returns true when the cascade has to be drawn again.
    fn update_cascade(&mut self, k: usize, center: glam::Vec3, sun: [f32; 3], ext: f32) -> bool {
        let grid = if k == 1 { 8.0 } else { 4.0 };
        let (sx, sz) = ((center.x / grid).round() * grid, (center.z / grid).round() * grid);
        let cs = &mut self.casc[k];
        if cs.valid && cs.cx == sx && cs.cz == sz && cs.sun == sun {
            return false;
        }
        cs.cx = sx;
        cs.cz = sz;
        cs.sun = sun;
        cs.valid = true;
        let c = glam::Vec3::new(sx, 12.0, sz);
        let sd = glam::Vec3::from(sun);
        let eye = c + sd * 90.0;
        let fwd = (c - eye).normalize();
        let v = look_to(eye, fwd, glam::Vec3::Y);
        let r = (ext * 1.42 * sd.x.hypot(sd.z) + 14.0 * sd.y.abs() + 6.0).min(88.0);
        let p = ortho(-ext, ext, -ext, ext, 90.0 - r, 90.0 + r);
        let mut mat = (p * v).to_cols_array();
        let s = SHADOW_SIZE as f32;
        let (tx, ty) = (mat[12] * s / 2.0, mat[13] * s / 2.0);
        mat[12] += (tx.round() - tx) * 2.0 / s;
        mat[13] += (ty.round() - ty) * 2.0 / s;
        cs.mat = mat;
        cs.bias = (if k == 1 { 0.1 } else { 0.04 }) / (2.0 * r);
        true
    }

    /// Writes the frame uniforms and records shadow, main and final passes.
    #[allow(clippy::too_many_arguments)]
    pub fn render(&mut self, d: &wgpu::Device, q: &wgpu::Queue, enc: &mut wgpu::CommandEncoder, out: &wgpu::TextureView, w: u32, h: u32, cam: &Camera, time: f32) {
        self.targets(d, w, h);
        let aspect = w as f32 / h.max(1) as f32;
        let proj = perspective(cam.fov_y, aspect, 0.08, 400.0);
        let view = look_to(cam.pos, cam.forward(), glam::Vec3::Y);
        let vp = proj * view;

        // cascades follow a point a little ahead of the camera, as they follow the hero in the game
        let fwd = glam::Vec3::new(cam.yaw.sin(), 0.0, -cam.yaw.cos());
        let sun = [self.frame[60], self.frame[61], self.frame[62]];
        let redo = [self.update_cascade(0, cam.pos + fwd * (NEAR_EXT * 0.5), sun, NEAR_EXT), self.update_cascade(1, cam.pos + fwd * (FAR_EXT * 0.4), sun, FAR_EXT)];

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
        f[124..127].copy_from_slice(&cam.pos.to_array()); // player: the camera stands in for the hero
        f[32..48].copy_from_slice(&self.casc[0].mat);
        f[376..392].copy_from_slice(&self.casc[1].mat);
        f[394] = self.casc[0].bias;
        f[395] = self.casc[1].bias;
        q.write_buffer(&self.frame_buf, 0, bytes(f));
        if redo[1] {
            self.frame_c1.copy_from_slice(f);
            self.frame_c1[32..48].copy_from_slice(&self.casc[1].mat);
            q.write_buffer(&self.frame_buf_c1, 0, bytes(&self.frame_c1));
        }

        if let Some(pr) = &mut self.props {
            pr.cull(q, cam.pos.to_array(), &frustum_planes(&vp));
            for (k, &again) in redo.iter().enumerate() {
                if again {
                    let cs = &self.casc[k];
                    pr.cull_shadow(q, k, cs.cx, cs.cz, if k == 1 { FAR_EXT } else { NEAR_EXT });
                }
            }
            self.instances = pr.count.iter().sum();
        }
        self.calls = 0;
        self.shadow_passes = 0;
        for (k, &again) in redo.iter().enumerate() {
            if !again {
                continue;
            }
            let cs = &self.casc[k];
            let ext = if k == 1 { FAR_EXT } else { NEAR_EXT };
            let (far, leaf_r) = (ext + 14.0, if k == 1 { 24.0 } else { ext + 8.0 });
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("shadow"),
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &self.shadow[k],
                    depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Store }),
                    stencil_ops: None,
                }),
                ..Default::default()
            });
            self.shadow_passes += 1;
            p.set_bind_group(0, &self.bg0_shadow[k], &[]);
            p.set_bind_group(1, &self.bg1, &[]);
            p.set_index_buffer(self.idx.slice(..), wgpu::IndexFormat::Uint32);
            p.set_pipeline(&self.p_shadow);
            for dr in &self.draws {
                let dist = (dr.cx - cs.cx).abs().max((dr.cz - cs.cz).abs());
                if dist <= far && dr.opaque > 0 {
                    p.draw_indexed(0..dr.opaque * 6, (dr.base * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
            p.set_pipeline(&self.p_shadow_leaf);
            for dr in &self.draws {
                let dist = (dr.cx - cs.cx).abs().max((dr.cz - cs.cz).abs());
                if dist <= leaf_r && dr.leaves > 0 {
                    p.draw_indexed(0..dr.leaves * 6, (dr.leaf_base * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
            if let (Some(pr), Some(bgm)) = (&self.props, &self.bg_model) {
                p.set_pipeline(&self.p_prop_shadow);
                for &mi in &pr.casters {
                    let n = pr.count_shadow[k][mi];
                    if n > 0 {
                        p.set_bind_group(1, bgm, &[(mi * 256) as u32]);
                        p.draw_indexed(0..pr.meta[mi].face_count * 6, 0, 0..n);
                        self.calls += 1;
                    }
                }
            }
        }

        let t = self.targets.as_ref().expect("targets");
        {
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("scene"),
                color_attachments: &[
                    Some(wgpu::RenderPassColorAttachment { view: &t.hdr, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } }),
                    Some(wgpu::RenderPassColorAttachment { view: &t.gbuf, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT), store: wgpu::StoreOp::Store } }),
                ],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &t.depth,
                    depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Store }),
                    stencil_ops: None,
                }),
                ..Default::default()
            });
            p.set_bind_group(0, &self.bg0, &[]);
            p.set_index_buffer(self.idx.slice(..), wgpu::IndexFormat::Uint32);
            // models first (big occluders), as renderer.js mainPass
            if let (Some(pr), Some(bgm)) = (&self.props, &self.bg_model) {
                p.set_pipeline(&self.p_prop);
                for &mi in &pr.others {
                    if pr.count[mi] > 0 {
                        p.set_bind_group(1, bgm, &[(mi * 256) as u32]);
                        p.draw_indexed(0..pr.meta[mi].face_count * 6, 0, 0..pr.count[mi]);
                        self.calls += 1;
                    }
                }
            }
            p.set_bind_group(1, &self.bg1, &[]);
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
            if let (Some(pr), Some(bgm)) = (&self.props, &self.bg_model) {
                p.set_pipeline(&self.p_tree);
                for &mi in &pr.trees {
                    if pr.count[mi] > 0 {
                        p.set_bind_group(1, bgm, &[(mi * 256) as u32]);
                        p.draw_indexed(0..pr.meta[mi].face_count * 6, 0, 0..pr.count[mi]);
                        self.calls += 1;
                    }
                }
            }
        }
        let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("comp"),
            color_attachments: &[
                Some(wgpu::RenderPassColorAttachment { view: out, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } }),
                Some(wgpu::RenderPassColorAttachment { view: &t.hist, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Discard } }),
            ],
            ..Default::default()
        });
        p.set_pipeline(&self.p_comp);
        p.set_bind_group(0, &t.comp_bg, &[]);
        p.draw(0..3, 0..1);
    }
}

/// engine/math.js ortho: depth 0..1
fn ortho(l: f32, r: f32, b: f32, t: f32, n: f32, f: f32) -> glam::Mat4 {
    glam::Mat4::from_cols(
        glam::Vec4::new(2.0 / (r - l), 0.0, 0.0, 0.0),
        glam::Vec4::new(0.0, 2.0 / (t - b), 0.0, 0.0),
        glam::Vec4::new(0.0, 0.0, 1.0 / (n - f), 0.0),
        glam::Vec4::new(-(r + l) / (r - l), -(t + b) / (t - b), n / (n - f), 1.0),
    )
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
