//! The village with the game's own shaders, pass by pass as renderer.js does it:
//! shadow cascades (WORLD_SHADER vsShadow / fsShadowLeaf) -> main pass (vsTerrain + fsTerrain / fsLeaf, dream world,
//! HDR + G-buffer) -> final pass (COMP_SHADER fsComp: sky, fog, exposure, AgX, LUT, vignette, grain).
//! The sky reflections are baked once with ENV_SHADER (fsEnv, fsLut). Bind group 0 mirrors renderer.js `L0`;
//! still missing (neutral stand-ins): AO, SSR, volumetric light, DOF, TAA history, props, grass, water, particles.
use crate::props::{frustum_planes, Props};
use std::collections::HashMap;
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

/// The quality profile (QUALITY in src/main.js of the game): scene pixel ceiling in megapixels (the scene and the
/// final pass run at that size, a last pass stretches it to the screen) and the screen-space effects.
#[derive(Clone, Copy, Debug)]
pub struct Quality {
    pub px: f32,
    pub ao: bool,
    pub ssr: bool,
    pub vol: bool,
}

impl Quality {
    /// QUALITY of the game for the Redmi 10S: px 1.1, ao 6 / contact 6, ssr 8, vol 10
    pub const VULKAN: Quality = Quality { px: 1.1, ao: true, ssr: true, vol: true };
    /// the GLES fallback: fewer pixels, no screen-space passes (distance fog in the shaders instead of the volume)
    pub const GL: Quality = Quality { px: 0.6, ao: false, ssr: false, vol: false };
}

/// stretches the finished image (at the quality size) to the screen
const BLIT_WGSL: &str = r#"
@group(0) @binding(0) var img: texture_2d<f32>;
@group(0) @binding(1) var smp: sampler;
struct V { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) i: u32) -> V {
  let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
  return V(vec4f(p * 2.0 - 1.0, 0.0, 1.0), vec2f(p.x, 1.0 - p.y));
}
@fragment fn fs(v: V) -> @location(0) vec4f { return textureSampleLevel(img, smp, v.uv, 0.0); }
"#;

struct Draw {
    mcx: u32,
    mcz: u32,
    /// drawn: false for the opened state of a world edit while it is closed, and for what it replaces while open
    active: bool,
    cx: f32,
    cz: f32,
    base: u32,
    /// quads per group: dream-only, both, night-only, leaves x3 (dream, both, night) — the mesher's c0
    c0: [u32; 6],
    /// the solid quads (all worlds) and the leaves (all worlds): the most any world draws
    opaque: u32,
    leaves: u32,
    leaf_base: u32,
    /// first quad and quad count of the water of this macro-chunk (drawn non-indexed: 6 vertices per quad)
    water_base: u32,
    water: u32,
}

impl Draw {
    fn new(mm: &MacroMesh, base: u32, cx: f32, cz: f32, active: bool) -> Self {
        let c0 = mm.c0;
        Draw {
            mcx: mm.mcx,
            mcz: mm.mcz,
            active,
            cx,
            cz,
            base,
            c0,
            opaque: c0[0] + c0[1] + c0[2],
            leaves: c0[3] + c0[4] + c0[5],
            leaf_base: base + c0[0] + c0[1] + c0[2],
            water_base: base + (mm.faces.len() / 3) as u32,
            water: (mm.water.len() / 3) as u32,
        }
    }

    /// The solid quads the world `cull` shows (1 dream, 2 nightmare, 3 both): first quad offset and count from `base`.
    fn solid_range(&self, cull: u32) -> (u32, u32) {
        let [d, b, n, ..] = self.c0;
        match cull {
            1 => (0, d + b),
            2 => (d, b + n),
            _ => (0, d + b + n),
        }
    }

    /// The leaves the world shows: first offset from `leaf_base` and count.
    fn leaf_range(&self, cull: u32) -> (u32, u32) {
        let [_, _, _, ld, lb, ln] = self.c0;
        match cull {
            1 => (0, ld + lb),
            2 => (ld, lb + ln),
            _ => (0, ld + lb + ln),
        }
    }
}

/// What the scene needs of the world each frame (the story's Duality, see the script crate): the transition wave
/// (a sphere whose inside shows the target world, plus the outer front of a reversed one) and the worlds of the chunks.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct WorldFrame {
    /// 0 dream .. 1 nightmare, eased
    pub night_share: f32,
    pub wave_c: [f32; 3],
    pub wave_r: f32,
    /// world ids 0 dream, 1 nightmare
    pub wave_from: u8,
    pub wave_to: u8,
    pub wave_active: bool,
    pub base: u8,
    pub wave2_c: [f32; 3],
    pub wave2_r: f32,
    /// which worlds the chunks show: 1 dream, 2 nightmare, 3 both (per pixel)
    pub cull: u32,
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
    /// the worlds the chunks show now (1 dream, 2 nightmare, 3 both), see WorldFrame
    cull: u32,
    /// the same at the last frame: a change re-draws the shadows
    cull_last: u32,
    /// exposure of the dream and of the nightmare of this chapter (the scene blends them by the night share)
    exp_d: f32,
    exp_n: f32,
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
    p_water: wgpu::RenderPipeline,
    p_shadow: wgpu::RenderPipeline,
    p_shadow_leaf: wgpu::RenderPipeline,
    p_comp: wgpu::RenderPipeline,
    p_ao: wgpu::RenderPipeline,
    p_vol: wgpu::RenderPipeline,
    p_blit: wgpu::RenderPipeline,
    surface_format: wgpu::TextureFormat,
    pub quality: Quality,
    /// the volume texture holds this size's fog (renderer.js volFresh)
    vol_fresh: bool,
    p_ssr: wgpu::RenderPipeline,
    ao_u: wgpu::Buffer,
    ssr_u: wgpu::Buffer,
    res0: Bg0Res,
    /// last frame's AO / SSR textures hold something (F.fx.x, F.fx2.x)
    ss_valid: bool,
    frame_no: u32,
    p_grass: Option<wgpu::RenderPipeline>,
    grass_quads: u32,
    props: Option<Props>,
    bg_model: Option<wgpu::BindGroup>,
    p_prop: wgpu::RenderPipeline,
    p_tree: wgpu::RenderPipeline,
    p_prop_shadow: wgpu::RenderPipeline,
    pub instances: u32,
    comp_res: CompRes,
    targets: Option<Targets>,
    draws: Vec<Draw>,
    /// world edit → (the world's macro chunks it replaces, its opened ones), indices into `draws`
    edits: HashMap<String, (Vec<usize>, Vec<usize>)>,
    /// per draw: in view this frame (renderer.js visibleChunks: distance and frustum)
    draw_vis: Vec<bool>,
    pub quads: u32,
    pub calls: u32,
    pub shadow_passes: u32,
    prev_vp: [f32; 16],
    prev_cam: glam::Vec3,
    /// last frame's TAA history is usable (F.taa.w)
    hist_valid: bool,
}

/// everything bind group 0 (renderer.js L0) holds, so the main one can be rebuilt with screen-sized AO / SSR textures
struct Bg0Res {
    l0: wgpu::BindGroupLayout,
    mats: wgpu::Buffer,
    chunk_org: wgpu::Buffer,
    bufs: [wgpu::Buffer; 5], // minfo, mfaces, insts, vis (main), gcol
    dummy_sb: wgpu::Buffer,
    views: [wgpu::TextureView; 8], // atlas det, noise3, lut, atlas pbr, env dream, env nightmare, brdf, white
    shadow_smp: wgpu::Sampler,
    rep_smp: wgpu::Sampler,
}

impl Bg0Res {
    #[allow(clippy::too_many_arguments)]
    fn make(&self, d: &wgpu::Device, label: &str, fb: &wgpu::Buffer, s0: &wgpu::TextureView, s1: &wgpu::TextureView, vis: &wgpu::Buffer, ao: &wgpu::TextureView, ssr: &wgpu::TextureView) -> wgpu::BindGroup {
        let [minfo, mfaces, insts, _, gcol] = &self.bufs;
        let [atlas, noise, lut, pbr, env_d, env_n, brdf, _] = &self.views;
        d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(label),
            layout: &self.l0,
            entries: &[
                be(0, buf(fb)), be(1, tv(s0)), be(2, wgpu::BindingResource::Sampler(&self.shadow_smp)), be(3, buf(&self.mats)),
                be(4, buf(&self.chunk_org)), be(5, buf(minfo)), be(6, buf(mfaces)), be(7, buf(insts)), be(8, buf(vis)),
                be(9, buf(&self.dummy_sb)), be(10, tv(atlas)), be(11, buf(gcol)), be(12, tv(noise)),
                be(13, wgpu::BindingResource::Sampler(&self.rep_smp)), be(14, tv(lut)), be(15, tv(pbr)),
                be(16, tv(env_d)), be(17, tv(env_n)), be(18, tv(brdf)), be(19, tv(s1)), be(20, tv(ao)), be(21, tv(ssr)),
            ],
        })
    }
}

/// the inputs of fsComp that are not render targets of this frame
struct CompRes {
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
    /// TAA history, written and read alternately (renderer.js histViews / bgCompH)
    hist: [wgpu::TextureView; 2],
    comp_bg: [wgpu::BindGroup; 2],
    ao: wgpu::TextureView,
    ssr: wgpu::TextureView,
    ao_bg: wgpu::BindGroup,
    vol: wgpu::TextureView,
    vol_bg: wgpu::BindGroup,
    /// the finished image at the quality size, stretched to the screen by the blit pass
    out: wgpu::TextureView,
    blit_bg: wgpu::BindGroup,
    ssr_bg: wgpu::BindGroup,
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
    #[allow(clippy::too_many_arguments)]
    pub fn new(d: &wgpu::Device, q: &wgpu::Queue, surface_format: wgpu::TextureFormat, pack: &Pack, chapter: u32, quality: Quality, cache: Option<&wgpu::PipelineCache>) -> Result<Self, String> {
        let m = &pack.manifest;
        let c = &m.constants;
        let pf = m.per_frame.ok_or("pack has no perFrame (old export)")?;
        let mut frame = f32s(&pack.read(&format!("frame/ch{chapter}.bin"))?);
        frame[134] = 0.75 / SHADOW_SIZE as f32; // grade.z: shadow texel
        frame[142] = f32::from_bits(if quality.vol { 10 } else { 0 }); // counts.z (u32): volumetric fog steps (0 = plain distance fog in the shaders)
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
                cache,
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
                draws.push(Draw::new(&mm, base, (mm.mcx * 64 + 32) as f32 * c.VS, (mm.mcz * 64 + 32) as f32 * c.VS, true));
                fw.extend_from_slice(&mm.faces);
                fw.extend_from_slice(&mm.water);
            }
        }
        if fw.is_empty() {
            return Err("pack has no mesh".into());
        }
        // world edits: their opened macro chunks go in after the world's, inactive; the edit swaps them in
        let mut edits = HashMap::new();
        for f in m.of_kind("edit").filter(|f| f.path.ends_with(".mesh.zst")) {
            let name = f.path.trim_start_matches("edit/").trim_end_matches(".mesh.zst").to_string();
            let (mut closed, mut opened) = (Vec::new(), Vec::new());
            for mm in MacroMesh::parse_tile(&pack.read_data(&f.path)?)? {
                // only where the world itself has this macro chunk (the tiles of the pack)
                let Some(k) = draws.iter().position(|d: &Draw| d.mcx == mm.mcx && d.mcz == mm.mcz) else { continue };
                closed.push(k);
                let base = (fw.len() / 3) as u32;
                opened.push(draws.len());
                draws.push(Draw::new(&mm, base, draws[k].cx, draws[k].cz, false));
                fw.extend_from_slice(&mm.faces);
                fw.extend_from_slice(&mm.water);
            }
            edits.insert(name, (closed, opened));
        }
        let quads = (fw.len() / 3) as u32;
        let faces_buf = d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("faces"), contents: &fw.iter().flat_map(|w| w.to_le_bytes()).collect::<Vec<u8>>(), usage: sb });
        let props = Props::new(d, pack)?;
        // grass: one draw of N x N cells x B blades (frame.grass = N, B, R), the map as renderer.js gcol
        let gcol = if m.files.iter().any(|f| f.kind == "grass") {
            Some(d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("gcol"), contents: &pack.read_data("grass.bin.zst")?, usage: sb }))
        } else {
            None
        };
        let grass_quads = if gcol.is_some() { (frame[240] * frame[240] * frame[241]) as u32 } else { 0 };
        let max_draw = draws.iter().map(|d| d.opaque.max(d.leaves)).max().unwrap_or(0).max(props.as_ref().map_or(1, |p| p.max_quads)).max(grass_quads).max(1);
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
        // the main pass reads the cascades and last frame's AO / SSR (bound in targets()); the shadow passes get the
        // 1x1 stand-ins and their own frame (shadowMat)
        let pb = |f: fn(&Props) -> &wgpu::Buffer| props.as_ref().map_or(&dummy_sb, f).clone();
        let res0 = Bg0Res {
            l0,
            mats,
            chunk_org,
            bufs: [pb(|p| &p.minfo), pb(|p| &p.mfaces), pb(|p| &p.insts), pb(|p| &p.vis), gcol.clone().unwrap_or_else(|| dummy_sb.clone())],
            dummy_sb: dummy_sb.clone(),
            views: [atlas[0].clone(), noisev, lutv.clone(), atlas[1].clone(), env_views[0].clone(), env_views[1].clone(), brdfv, whitev.clone()],
            shadow_smp,
            rep_smp,
        };
        let vis_main = res0.bufs[3].clone();
        let bg0 = res0.make(d, "bg_world", &frame_buf, &shadow[0], &shadow[1], &vis_main, &whitev, &whitev);
        let bg0_shadow = [
            res0.make(d, "bg_world_shadow", &frame_buf, &depth1v, &depth1v, &pb(|p| &p.vis_shadow[0]), &whitev, &whitev),
            res0.make(d, "bg_world_shadow2", &frame_buf_c1, &depth1v, &depth1v, &pb(|p| &p.vis_shadow[1]), &whitev, &whitev),
        ];
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
        let l0 = &res0.l0;
        let layout = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("layT"), bind_group_layouts: &[Some(l0), Some(&l1)], immediate_size: 0 });
        let lay_p = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("layP"), bind_group_layouts: &[Some(l0), Some(&l1p)], immediate_size: 0 });
        // WMODE 2: the world of each pixel from the frame's transition wave (the dream when no wave runs)
        let consts: &[(&str, f64)] = &[("WMODE", 2.0)];
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
                cache,
            })
        };
        let pipe = |label: &str, vs: &str, fs: Option<&str>, cull: Option<wgpu::Face>, shadow: bool| pipe_l(&layout, label, vs, fs, cull, shadow);
        let lay_part = d.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("layPart"), bind_group_layouts: &[Some(l0)], immediate_size: 0 });
        let p_grass = (grass_quads > 0).then(|| pipe_l(&lay_part, "grass", "vsGrass", Some("fsGrass"), None, false));
        let p_prop = pipe_l(&lay_p, "props0", "vsProp", Some("fsProp"), Some(wgpu::Face::Back), false);
        let p_tree = pipe_l(&lay_p, "tree0", "vsProp", Some("fsTree"), None, false);
        let p_prop_shadow = pipe_l(&lay_p, "propShadow", "vsPropShadow", Some("fsPropShadow"), None, true);
        let p_terrain = pipe("terrain0", "vsTerrain", Some("fsTerrain"), Some(wgpu::Face::Back), false);
        let p_leaf = pipe("leaf0", "vsTerrain", Some("fsLeaf"), None, false);
        let p_shadow = pipe("shadow", "vsShadow", None, Some(wgpu::Face::Back), true);
        let p_shadow_leaf = pipe("shadowL0", "vsShadow", Some("fsShadowLeaf"), None, true);
        // water: premultiplied alpha over the scene (renderer.js 'water0'), depth written so reflections see it
        let p_water = d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("water0"),
            layout: Some(&layout),
            vertex: wgpu::VertexState { module: &world, entry_point: Some("vsWater"), compilation_options: opts(), buffers: &[] },
            fragment: Some(wgpu::FragmentState {
                module: &world,
                entry_point: Some("fsWater"),
                compilation_options: opts(),
                targets: &[
                    Some(wgpu::ColorTargetState {
                        format: HDR,
                        blend: Some(wgpu::BlendState {
                            color: wgpu::BlendComponent { src_factor: wgpu::BlendFactor::One, dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha, operation: wgpu::BlendOperation::Add },
                            alpha: wgpu::BlendComponent { src_factor: wgpu::BlendFactor::One, dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha, operation: wgpu::BlendOperation::Add },
                        }),
                        write_mask: wgpu::ColorWrites::ALL,
                    }),
                    Some(GBUF.into()),
                ],
            }),
            primitive: wgpu::PrimitiveState { cull_mode: None, ..Default::default() },
            depth_stencil: Some(wgpu::DepthStencilState { format: DEPTH, depth_write_enabled: Some(true), depth_compare: Some(wgpu::CompareFunction::Less), stencil: Default::default(), bias: Default::default() }),
            multisample: Default::default(),
            multiview_mask: None,
            cache,
        });

        // screen-space occlusion (half resolution) and reflections (quarter): renderer.js screenSpacePasses
        let aom = module(d, pack, "ao")?;
        let p_ao = full("ao", &aom, "fsAo", None, &[Some(wgpu::TextureFormat::Rgba8Unorm.into())]);
        let ssrm = module(d, pack, "ssr")?;
        let p_ssr = full("ssr", &ssrm, "fsSsr", None, &[Some(HDR.into())]);
        let ao_u = d.create_buffer(&wgpu::BufferDescriptor { label: Some("ao u"), size: 16, usage: ub, mapped_at_creation: false });
        let ssr_u = d.create_buffer(&wgpu::BufferDescriptor { label: Some("ssr u"), size: 16, usage: ub, mapped_at_creation: false });
        // volumetric fog and light shafts at half resolution, every second frame (QUALITY vol 10, volHalf)
        let volm = module(d, pack, "vol")?;
        let p_vol = full("vol", &volm, "fsVol", None, &[Some(HDR.into())]);
        let blitm = d.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("blit"), source: wgpu::ShaderSource::Wgsl(BLIT_WGSL.into()) });
        let p_blit = d.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("blit"),
            layout: None,
            vertex: wgpu::VertexState { module: &blitm, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[] },
            fragment: Some(wgpu::FragmentState { module: &blitm, entry_point: Some("fs"), compilation_options: Default::default(), targets: &[Some(surface_format.into())] }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: Default::default(),
            multiview_mask: None,
            cache,
        });
        let compm = module(d, pack, "comp")?;
        let p_comp = full("comp", &compm, "fsComp", None, &[Some(surface_format.into()), Some(HDR.into())]);
        // no depth of field yet
        let black = |label: &str, px: [u8; 4]| {
            let t = tex(d, label, ext(1, 1, 1), wgpu::TextureDimension::D2, wgpu::TextureFormat::Rgba8Unorm, 1, tb);
            upload(q, &t, 0, &px, 4, 1, ext(1, 1, 1));
            t.create_view(&Default::default())
        };
        let comp_res = CompRes {
            dof: black("dof", [0, 0, 0, 0]),
            lut: lutv.clone(),
            lin_smp: d.create_sampler(&wgpu::SamplerDescriptor { mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() }),
        };
        let water_quads: u32 = draws.iter().map(|d| d.water).sum();
        log::info!("world: {} macro chunks, {} quads, {} water quads, exposure {:.2}", draws.len(), quads, water_quads, frame[132]);
        let exp_d = frame[132];
        let exp_n = m.night_exposure.get(&chapter.to_string()).copied().unwrap_or(exp_d);
        Ok(World {
            cull: 1,
            cull_last: 1,
            exp_d,
            exp_n,
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
            p_water,
            p_shadow,
            p_shadow_leaf,
            p_comp,
            p_ao,
            p_ssr,
            p_vol,
            p_blit,
            surface_format,
            quality,
            vol_fresh: false,
            ao_u,
            ssr_u,
            res0,
            ss_valid: false,
            frame_no: 0,
            p_grass,
            grass_quads,
            instances: props.as_ref().map_or(0, |p| p.count.len() as u32),
            props,
            bg_model,
            p_prop,
            p_tree,
            p_prop_shadow,
            comp_res,
            targets: None,
            draw_vis: vec![false; draws.len()],
            draws,
            edits,
            quads,
            calls: 0,
            shadow_passes: 0,
            prev_vp: glam::Mat4::IDENTITY.to_cols_array(),
            prev_cam: glam::Vec3::ZERO,
            hist_valid: false,
        })
    }

    fn targets(&mut self, d: &wgpu::Device, w: u32, h: u32) {
        if self.targets.as_ref().is_some_and(|t| t.w == w && t.h == h) {
            return;
        }
        let u = wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING;
        let mk = |label: &str, f: wgpu::TextureFormat| tex(d, label, ext(w, h, 1), wgpu::TextureDimension::D2, f, 1, u).create_view(&Default::default());
        let (hdr, gbuf, depth) = (mk("scene", HDR), mk("gbuf", GBUF), mk("depth", DEPTH));
        let hist = [mk("hist 0", HDR), mk("hist 1", HDR)];
        let vol = tex(d, "vol", ext((w >> 1).max(1), (h >> 1).max(1), 1), wgpu::TextureDimension::D2, HDR, 1, u).create_view(&Default::default());
        let r = &self.comp_res;
        let vol_bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_vol"),
            layout: &self.p_vol.get_bind_group_layout(0),
            entries: &[
                be(0, buf(&self.frame_buf)), be(1, tv(&self.shadow[1])), be(2, wgpu::BindingResource::Sampler(&self.res0.shadow_smp)),
                be(3, tv(&depth)), be(4, tv(&self.res0.views[1])), be(5, wgpu::BindingResource::Sampler(&self.res0.rep_smp)),
            ],
        });
        self.vol_fresh = false;
        let out = tex(d, "out", ext(w, h, 1), wgpu::TextureDimension::D2, self.surface_format, 1, u).create_view(&Default::default());
        let blit_bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_blit"),
            layout: &self.p_blit.get_bind_group_layout(0),
            entries: &[be(0, tv(&out)), be(1, wgpu::BindingResource::Sampler(&self.comp_res.lin_smp))],
        });
        let comp_bg = [1, 0].map(|read: usize| {
            d.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("bg_comp"),
                layout: &self.p_comp.get_bind_group_layout(0),
                entries: &[
                    be(0, buf(&self.frame_buf)), be(1, tv(&hdr)), be(2, tv(&vol)), be(3, tv(&depth)), be(4, wgpu::BindingResource::Sampler(&r.lin_smp)),
                    be(7, tv(&r.dof)), be(8, tv(&hist[read])), be(9, tv(&gbuf)), be(10, tv(&r.lut)),
                ],
            })
        });
        self.hist_valid = false;
        let half = |label: &str, k: u32, f: wgpu::TextureFormat| tex(d, label, ext((w >> k).max(1), (h >> k).max(1), 1), wgpu::TextureDimension::D2, f, 1, u).create_view(&Default::default());
        let (ao, ssr) = (half("ao", 1, wgpu::TextureFormat::Rgba8Unorm), half("ssr", 2, HDR));
        let ao_bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_ao"),
            layout: &self.p_ao.get_bind_group_layout(0),
            entries: &[be(0, buf(&self.frame_buf)), be(1, tv(&depth)), be(2, tv(&gbuf)), be(3, buf(&self.ao_u))],
        });
        let ssr_bg = d.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("bg_ssr"),
            layout: &self.p_ssr.get_bind_group_layout(0),
            entries: &[
                be(0, buf(&self.frame_buf)), be(1, tv(&depth)), be(2, tv(&gbuf)), be(3, tv(&hdr)),
                be(4, wgpu::BindingResource::Sampler(&self.comp_res.lin_smp)), be(5, buf(&self.ssr_u)),
            ],
        });
        self.bg0 = self.res0.make(d, "bg_world", &self.frame_buf, &self.shadow[0], &self.shadow[1], &self.res0.bufs[3], &ao, &ssr);
        self.ss_valid = false;
        self.targets = Some(Targets { w, h, hdr, gbuf, depth, hist, comp_bg, ao, ssr, ao_bg, ssr_bg, vol, vol_bg, out, blit_bg });
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
    /// macro chunks with geometry
    pub fn chunks(&self) -> usize {
        self.draws.len()
    }

    /// names of the pack's models (index = model index of an instance)
    pub fn model_names(&self) -> Vec<&str> {
        self.props.as_ref().map_or_else(Vec::new, |p| p.meta.iter().map(|m| m.name.as_str()).collect())
    }

    /// instances the game moves every frame (the hero's rig), see Props::set_dynamic
    /// A world edit of the story opened or closed: its macro chunks swap meshes (the voxels are the caller's).
    pub fn set_edit(&mut self, name: &str, on: bool) -> bool {
        let Some((closed, opened)) = self.edits.get(name) else { return false };
        for &k in closed {
            self.draws[k].active = !on;
        }
        for &k in opened {
            self.draws[k].active = on;
        }
        // the shadows see it at once
        self.casc.iter_mut().for_each(|c| c.valid = false);
        true
    }

    /// The worlds of this frame (the story's Duality): the wave, the night share, which world the chunks show. The
    /// scene's blends follow: the sky and the light by the night share, the exposure and the grain likewise, the
    /// shaders pick each pixel's world from the wave.
    pub fn set_world(&mut self, w: &WorldFrame) {
        let ns = w.night_share.clamp(0.0, 1.0);
        let f = &mut self.frame;
        f[63] = ns; // nightGlobal
        f[100..104].copy_from_slice(&[w.wave_c[0], w.wave_c[1], w.wave_c[2], w.wave_r]);
        f[104..108].copy_from_slice(&[w.wave_from as f32, w.wave_to as f32, if w.wave_active { 1.0 } else { 0.0 }, w.base as f32]);
        // the outer front of a reversed wave (radius 0 = none), as renderer.js: wave2.w is 0 when no wave runs
        f[264..268].copy_from_slice(&[w.wave2_c[0], w.wave2_c[1], w.wave2_c[2], if w.wave_active { w.wave2_r } else { 0.0 }]);
        f[132] = self.exp_d + (self.exp_n - self.exp_d) * ns; // exposure (main.js)
        f[133] = 0.2 + ns * 0.25; // vignette
        f[135] = 0.03 + ns * 0.01; // grain
        self.cull = w.cull.clamp(1, 3);
    }

    /// a story prop moved (see Props::move_to)
    pub fn move_prop(&mut self, q: &wgpu::Queue, model: &str, home: [f32; 3], to: [f32; 3], yaw: f32) -> usize {
        self.props.as_mut().map_or(0, |p| p.move_to(q, model, home, to, yaw))
    }

    /// a story prop shown or hidden (see Props::set_visible)
    pub fn set_prop_visible(&mut self, q: &wgpu::Queue, model: &str, pos: [f32; 3], on: bool) -> usize {
        self.props.as_mut().map_or(0, |p| p.set_visible(q, model, pos, on))
    }

    pub fn set_dynamic(&mut self, q: &wgpu::Queue, words: &[u32]) {
        if let Some(p) = &mut self.props {
            p.set_dynamic(q, words);
        }
    }

    /// `focus`: the hero (shadow cascades, grass bending, F.player)
    #[allow(clippy::too_many_arguments)]
    pub fn render(&mut self, d: &wgpu::Device, q: &wgpu::Queue, enc: &mut wgpu::CommandEncoder, screen: &wgpu::TextureView, sw: u32, sh: u32, cam: &Camera, focus: glam::Vec3, time: f32) {
        // the scene and the final pass at no more than quality.px megapixels (QUALITY.px with outPx in the game)
        let k = (self.quality.px * 1e6 / (sw.max(1) * sh.max(1)) as f32).sqrt().min(1.0);
        let (w, h) = (((sw as f32 * k) as u32).max(1), ((sh as f32 * k) as u32).max(1));
        self.targets(d, w, h);
        let aspect = w as f32 / h.max(1) as f32;
        let proj = perspective(cam.fov_y, aspect, 0.08, 400.0);
        let view = look_to(cam.pos, cam.forward(), glam::Vec3::Y);
        let vp_nj = proj * view;
        // TAA (renderer.js setupCamera): a camera cut leaves nothing worth keeping; otherwise the projection is
        // shifted by a Halton offset and fsComp un-jitters with fx2.zw
        if cam.pos.distance(self.prev_cam) > 3.0 {
            self.hist_valid = false;
            self.ss_valid = false;
        }
        self.prev_cam = cam.pos;
        let (mut jx, mut jy) = (0.0, 0.0);
        let mut pj = proj;
        if self.hist_valid {
            let k = (self.frame_no & 7) as usize + 1;
            (jx, jy) = (halton(k, 2) - 0.5, halton(k, 3) - 0.5);
            pj.z_axis.x += jx * 2.0 / w as f32;
            pj.z_axis.y += jy * 2.0 / h as f32;
        }
        let vp = pj * view;

        // cascades follow the hero, a little ahead in the view direction
        let fwd = glam::Vec3::new(cam.yaw.sin(), 0.0, -cam.yaw.cos());
        let sun = [self.frame[60], self.frame[61], self.frame[62]];
        // shadows: from the moved hero as before, and afresh while a wave runs or the worlds changed (their casters differ)
        let force = self.cull == 3 || self.cull != self.cull_last;
        self.cull_last = self.cull;
        let redo = [self.update_cascade(0, focus + fwd * (NEAR_EXT * 0.3), sun, NEAR_EXT) || force, self.update_cascade(1, focus + fwd * (FAR_EXT * 0.3), sun, FAR_EXT) || force];

        let pf = self.pf;
        let f = &mut self.frame;
        f[pf.view_proj..pf.view_proj + 16].copy_from_slice(&vp.to_cols_array());
        // invViewProj stays in the unjittered space of prevVP: reprojection without oscillation
        f[pf.inv_view_proj..pf.inv_view_proj + 16].copy_from_slice(&vp_nj.inverse().to_cols_array());
        f[pf.prev_vp..pf.prev_vp + 16].copy_from_slice(&self.prev_vp);
        self.prev_vp = vp_nj.to_cols_array();
        f[263] = if self.hist_valid { 1.0 } else { 0.0 }; // taa.w
        f[398] = jx / w as f32; // fx2.zw: un-jitter (sign as renderer.js)
        f[399] = -jy / h as f32;
        f[411] = (self.frame_no & 15) as f32; // opt.w: temporal noise phase
        let right = view.row(0);
        let up = view.row(1);
        f[pf.cam..pf.cam + 3].copy_from_slice(&cam.pos.to_array());
        f[pf.time] = time;
        f[pf.cam_right..pf.cam_right + 3].copy_from_slice(&[right.x, right.y, right.z]);
        f[pf.cam_up..pf.cam_up + 3].copy_from_slice(&[up.x, up.y, up.z]);
        f[pf.res..pf.res + 4].copy_from_slice(&[w as f32, h as f32, 1.0 / w as f32, 1.0 / h as f32]);
        f[pf.out_res..pf.out_res + 4].copy_from_slice(&[w as f32, h as f32, 1.0 / w as f32, 1.0 / h as f32]);
        f[pf.focal] = h as f32 * 0.5 * proj.y_axis.y;
        f[124..127].copy_from_slice(&focus.to_array()); // player (grass bends away from it)
        f[32..48].copy_from_slice(&self.casc[0].mat);
        f[376..392].copy_from_slice(&self.casc[1].mat);
        let ssv = |on: bool| if on && self.ss_valid { 1.0 } else { 0.0 };
        f[392] = ssv(self.quality.ao); // fx.x: AO texture valid
        f[396] = ssv(self.quality.ssr); // fx2.x: SSR texture valid
        f[394] = self.casc[0].bias;
        f[395] = self.casc[1].bias;
        q.write_buffer(&self.frame_buf, 0, bytes(f));
        if redo[1] {
            self.frame_c1.copy_from_slice(f);
            self.frame_c1[32..48].copy_from_slice(&self.casc[1].mat);
            q.write_buffer(&self.frame_buf_c1, 0, bytes(&self.frame_c1));
        }

        // macro-chunks within S.far (180 m) and the frustum (boxes of 8 x 16 x 8 m plus margin), as visibleChunks
        let planes = frustum_planes(&vp_nj);
        let (hxz, hy) = (4.0 + 0.8, 8.0 + 0.8);
        for (v, dr) in self.draw_vis.iter_mut().zip(&self.draws) {
            let dx = ((dr.cx - cam.pos.x).abs() - hxz).max(0.0);
            let dz = ((dr.cz - cam.pos.z).abs() - hxz).max(0.0);
            let dist = dx.hypot(dz);
            let inside = planes.iter().all(|pl| pl[0] * dr.cx + pl[1] * 8.0 + pl[2] * dr.cz + pl[3] + pl[0].abs() * hxz + pl[1].abs() * hy + pl[2].abs() * hxz >= 0.0);
            *v = dr.active && dist <= 180.0 && (dist <= 10.0 || inside);
        }
        if let Some(pr) = &mut self.props {
            pr.cull(q, cam.pos.to_array(), &planes, self.cull);
            for (k, &again) in redo.iter().enumerate() {
                if again {
                    let cs = &self.casc[k];
                    pr.cull_shadow(q, k, cs.cx, cs.cz, if k == 1 { FAR_EXT } else { NEAR_EXT }, self.cull);
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
                let (start, n) = dr.solid_range(self.cull);
                if dr.active && dist <= far && n > 0 {
                    p.draw_indexed(0..n * 6, ((dr.base + start) * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
            p.set_pipeline(&self.p_shadow_leaf);
            for dr in &self.draws {
                let dist = (dr.cx - cs.cx).abs().max((dr.cz - cs.cz).abs());
                let (start, n) = dr.leaf_range(self.cull);
                if dr.active && dist <= leaf_r && n > 0 {
                    p.draw_indexed(0..n * 6, ((dr.leaf_base + start) * 4) as i32, 0..1);
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
            for (dr, _) in self.draws.iter().zip(&self.draw_vis).filter(|(_, v)| **v) {
                let (start, n) = dr.solid_range(self.cull);
                if n > 0 {
                    p.draw_indexed(0..n * 6, ((dr.base + start) * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
            // grass and particles are single draws of N quads, as renderer.js mainPass
            if let Some(pg) = &self.p_grass {
                p.set_pipeline(pg);
                p.draw_indexed(0..self.grass_quads * 6, 0, 0..1);
                self.calls += 1;
            }
            p.set_pipeline(&self.p_leaf);
            for (dr, _) in self.draws.iter().zip(&self.draw_vis).filter(|(_, v)| **v) {
                let (start, n) = dr.leaf_range(self.cull);
                if n > 0 {
                    p.draw_indexed(0..n * 6, ((dr.leaf_base + start) * 4) as i32, 0..1);
                    self.calls += 1;
                }
            }
            p.set_pipeline(&self.p_water);
            for (dr, _) in self.draws.iter().zip(&self.draw_vis).filter(|(_, v)| **v) {
                if dr.water > 0 {
                    let (a, b) = (dr.water_base * 6, (dr.water_base + dr.water) * 6);
                    p.draw(a..b, 0..1);
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
        // QUALITY: ao 6 samples, contact shadow 6 steps, ssr 8 steps
        let tph = (self.frame_no & 7) as f32;
        self.frame_no = self.frame_no.wrapping_add(1);
        q.write_buffer(&self.ao_u, 0, bytes(&[6.0, 6.0, tph, if self.frame[61] > 0.02 { 1.0 } else { 0.0 }]));
        q.write_buffer(&self.ssr_u, 0, bytes(&[8.0, tph, 1.36, 0.0]));
        if self.quality.ao {
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("ao"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &t.ao, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::WHITE), store: wgpu::StoreOp::Store } })],
                ..Default::default()
            });
            p.set_pipeline(&self.p_ao);
            p.set_bind_group(0, &t.ao_bg, &[]);
            p.draw(0..3, 0..1);
        }
        if self.quality.ssr {
            let mut p = color_pass(enc, "ssr", &t.ssr);
            p.set_pipeline(&self.p_ssr);
            p.set_bind_group(0, &t.ssr_bg, &[]);
            p.draw(0..3, 0..1);
        }
        self.ss_valid = true;
        if self.quality.vol && (!self.vol_fresh || self.frame_no & 1 == 0) {
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("vol"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &t.vol, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }), store: wgpu::StoreOp::Store } })],
                ..Default::default()
            });
            p.set_pipeline(&self.p_vol);
            p.set_bind_group(0, &t.vol_bg, &[]);
            p.draw(0..3, 0..1);
            self.vol_fresh = true;
        }
        let hk = (self.frame_no & 1) as usize;
        self.hist_valid = true;
        let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("comp"),
            color_attachments: &[
                Some(wgpu::RenderPassColorAttachment { view: &t.out, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } }),
                Some(wgpu::RenderPassColorAttachment { view: &t.hist[hk], resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } }),
            ],
            ..Default::default()
        });
        p.set_pipeline(&self.p_comp);
        p.set_bind_group(0, &t.comp_bg[hk], &[]);
        p.draw(0..3, 0..1);
        drop(p);
        let mut p = color_pass(enc, "blit", screen);
        p.set_pipeline(&self.p_blit);
        p.set_bind_group(0, &t.blit_bg, &[]);
        p.draw(0..3, 0..1);
    }
}

fn halton(mut i: usize, b: usize) -> f32 {
    let (mut f, mut r) = (1.0, 0.0);
    while i > 0 {
        f /= b as f32;
        r += f * (i % b) as f32;
        i /= b;
    }
    r
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
