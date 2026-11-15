//! Models (trees, houses' furniture, fences, flowers...) with their static instances from the pack, culled on the CPU
//! with the same tests as CULL_SHADER (distance, detail level switches, frustum) and drawn with vsProp / fsProp /
//! fsTree; the shadow casters with vsPropShadow / fsPropShadow. Buffers are laid out as renderer.js setModels /
//! setInstances, so bind group 0 sees them exactly as in the game.
use mezdu_core::{parse_models, u32s, ModelMeta, Pack};
use wgpu::util::DeviceExt;

pub struct Props {
    pub meta: Vec<ModelMeta>,
    radius: Vec<f32>,
    inst: Vec<u32>,
    n: usize,
    n_dyn: usize,
    vis_base: Vec<u32>,
    /// each static instance's world mask as packed (a prop hidden at export: both worlds)
    mask0: Vec<u32>,
    /// each static instance's place as packed: the story finds its props by it, also after moving them
    home: Vec<[f32; 3]>,
    pub minfo: wgpu::Buffer,
    pub mfaces: wgpu::Buffer,
    pub insts: wgpu::Buffer,
    pub vis: wgpu::Buffer,
    pub vis_shadow: [wgpu::Buffer; 2],
    pub model_u: wgpu::Buffer,
    /// per model: visible instances this frame (main / shadow)
    pub count: Vec<u32>,
    pub count_shadow: [Vec<u32>; 2],
    vis_cpu: Vec<u32>,
    vis_shadow_cpu: Vec<u32>,
    pub max_quads: u32,
    pub trees: Vec<usize>,
    pub others: Vec<usize>,
    pub casters: Vec<usize>,
}

const W: usize = 16; // words per instance
/// instances the game writes every frame (the hero's rig parts...), after the static ones
pub const DYN: usize = 16;

impl Props {
    pub fn new(d: &wgpu::Device, pack: &Pack) -> Result<Option<Self>, String> {
        if pack.manifest.of_kind("models").count() < 3 {
            return Ok(None);
        }
        let meta = parse_models(&pack.read("models/models.json")?)?;
        let faces = pack.read_data("models/faces.bin.zst")?;
        let mut inst = u32s(&pack.read_data("models/instances.bin.zst")?);
        let n = inst.len() / W;
        // every model may also be used twice by the dynamic slots (the rig draws the leg twice)
        let mut cap = vec![2u32; meta.len()];
        for i in 0..n {
            cap[inst[i * W + 12] as usize] += 1;
        }
        inst.resize((n + DYN) * W, 0);
        let mut vis_base = Vec::with_capacity(meta.len());
        let mut info: Vec<u8> = Vec::with_capacity(meta.len() * 48);
        let mut acc = 0u32;
        let radius: Vec<f32> = meta.iter().map(|m| m.radius()).collect();
        for (i, m) in meta.iter().enumerate() {
            vis_base.push(acc);
            for w in [m.face_start, m.face_count, acc, m.flags] {
                info.extend_from_slice(&w.to_le_bytes());
            }
            for f in [m.pivot[0], m.pivot[1], m.pivot[2], m.vs, radius[i] + 0.1, m.max_dist, m.min_dist, cap[i] as f32] {
                info.extend_from_slice(&f.to_le_bytes());
            }
            acc += cap[i];
        }
        let sb = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST;
        let init = |label: &str, contents: &[u8], usage| d.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some(label), contents, usage });
        let inst_bytes: Vec<u8> = inst.iter().flat_map(|w| w.to_le_bytes()).collect();
        let vis_size = (acc.max(4) as u64) * 4;
        let mut mu = vec![0u8; meta.len() * 256];
        for i in 0..meta.len() {
            mu[i * 256..i * 256 + 4].copy_from_slice(&(i as u32).to_le_bytes());
        }
        let is_tree = |m: &ModelMeta| m.flags & 4 != 0;
        // trees by detail tier (near, _l, _f) as renderer.js setUsedModels
        let tier = |m: &ModelMeta| if m.name.ends_with("_f") { 2 } else if m.name.ends_with("_l") { 1 } else { 0 };
        let mut trees: Vec<usize> = (0..meta.len()).filter(|&i| is_tree(&meta[i])).collect();
        trees.sort_by_key(|&i| tier(&meta[i]));
        let others = (0..meta.len()).filter(|&i| !is_tree(&meta[i])).collect();
        let casters = (0..meta.len()).filter(|&i| meta[i].flags & 1 != 0).collect();
        log::info!("props: {} models, {} instances", meta.len(), n);
        let home = (0..n).map(|i| [3, 7, 11].map(|k| f32::from_bits(inst[i * W + k]))).collect();
        let mask0 = (0..n).map(|i| if inst[i * W + 13] & 3 == 0 { inst[i * W + 13] | 3 } else { inst[i * W + 13] }).collect();
        Ok(Some(Props {
            mask0,
            home,
            max_quads: meta.iter().map(|m| m.face_count).max().unwrap_or(1),
            radius,
            n,
            n_dyn: 0,
            minfo: init("minfo", &info, sb),
            mfaces: init("mfaces", &faces, sb),
            insts: init("insts", &inst_bytes, sb),
            vis: d.create_buffer(&wgpu::BufferDescriptor { label: Some("vis"), size: vis_size, usage: sb, mapped_at_creation: false }),
            vis_shadow: [0, 1].map(|_| d.create_buffer(&wgpu::BufferDescriptor { label: Some("vis shadow"), size: vis_size, usage: sb, mapped_at_creation: false })),
            model_u: init("model u", &mu, wgpu::BufferUsages::UNIFORM),
            count: vec![0; meta.len()],
            count_shadow: [vec![0; meta.len()], vec![0; meta.len()]],
            vis_cpu: vec![0; acc as usize],
            vis_shadow_cpu: vec![0; acc as usize],
            vis_base,
            inst,
            meta,
            trees,
            others,
            casters,
        }))
    }

    /// Writes the dynamic instances (16 words each, at most DYN) after the static ones.
    pub fn set_dynamic(&mut self, q: &wgpu::Queue, words: &[u32]) {
        let k = (words.len() / W).min(DYN);
        self.inst[self.n * W..(self.n + k) * W].copy_from_slice(&words[..k * W]);
        self.n_dyn = k;
        q.write_buffer(&self.insts, (self.n * W * 4) as u64, bytemuck_u32(&self.inst[self.n * W..(self.n + k) * W]));
    }

    /// A story prop shown or hidden (G.place(...).show in the scripts): the static instances of `model` and its
    /// far versions (`_l`, `_f`) within 0.3 m of `pos`. Returns how many changed.
    /// the static instances of `model` (and its `_l`, `_f`) packed within 0.3 m of `home`
    fn story_prop(&self, model: &str, home: [f32; 3]) -> impl Iterator<Item = usize> + '_ {
        let model = model.to_string();
        (0..self.n).filter(move |&i| {
            let name = &self.meta[self.inst[i * W + 12] as usize].name;
            let p = self.home[i];
            (name == &model || name.strip_suffix("_l").or(name.strip_suffix("_f")) == Some(model.as_str())) && (p[0] - home[0]).abs() <= 0.3 && (p[1] - home[1]).abs() <= 0.3 && (p[2] - home[2]).abs() <= 0.3
        })
    }

    /// A story prop moved and turned about its vertical axis (a door on its hinge: StaticProp.move), scale kept.
    pub fn move_to(&mut self, q: &wgpu::Queue, model: &str, home: [f32; 3], to: [f32; 3], yaw: f32) -> usize {
        let found: Vec<usize> = self.story_prop(model, home).collect();
        for &i in &found {
            let (_, s) = self.pos(i);
            let (c, sn) = (yaw.cos() * s, yaw.sin() * s);
            // m34TRS (engine/math.js) with pitch = roll = 0
            let m = [c, 0.0, sn, to[0], 0.0, s, 0.0, to[1], -sn, 0.0, c, to[2]];
            for (k, v) in m.iter().enumerate() {
                self.inst[i * W + k] = v.to_bits();
            }
            q.write_buffer(&self.insts, (i * W * 4) as u64, bytemuck_u32(&self.inst[i * W..i * W + 12]));
        }
        found.len()
    }

    pub fn set_visible(&mut self, q: &wgpu::Queue, model: &str, pos: [f32; 3], on: bool) -> usize {
        let mut n = 0;
        let found: Vec<usize> = self.story_prop(model, pos).collect();
        for i in found {
            let want = if on { self.mask0[i] } else { 0 };
            if self.inst[i * W + 13] != want {
                self.inst[i * W + 13] = want;
                q.write_buffer(&self.insts, ((i * W + 13) * 4) as u64, &want.to_le_bytes());
                n += 1;
            }
        }
        n
    }

    fn pos(&self, i: usize) -> ([f32; 3], f32) {
        let f = |k: usize| f32::from_bits(self.inst[i * W + k]);
        let scale = (f(0) * f(0) + f(1) * f(1) + f(2) * f(2)).sqrt();
        ([f(3), f(7), f(11)], scale)
    }

    /// CULL_SHADER cullMain for the dream world (no transition wave), draw-distance and switch multipliers 1.
    /// `world`: the worlds the chunks show (1 dream, 2 nightmare, 3 both: then the shader's per-pixel world decides)
    pub fn cull(&mut self, q: &wgpu::Queue, cam: [f32; 3], planes: &[[f32; 4]; 6], world: u32) {
        self.count.iter_mut().for_each(|c| *c = 0);
        for i in 0..self.n + self.n_dyn {
            let (mask, mi) = (self.inst[i * W + 13], self.inst[i * W + 12] as usize);
            if mask & world == 0 {
                continue;
            }
            let m = &self.meta[mi];
            let (p, s) = self.pos(i);
            let r = (self.radius[mi] + 0.1) * s;
            let d = ((p[0] - cam[0]).powi(2) + (p[1] - cam[1]).powi(2) + (p[2] - cam[2]).powi(2)).sqrt();
            if d - r > m.max_dist.max(55.0) {
                continue;
            }
            let lod = m.flags & 2 != 0;
            let dl = (d - r * 0.8).max(0.0);
            if !lod && d > m.max_dist.max(32.0) {
                continue;
            }
            if (if lod { dl } else { d - r }) > m.max_dist || (lod && dl < m.min_dist) {
                continue;
            }
            if planes.iter().any(|pl| pl[0] * p[0] + pl[1] * p[1] + pl[2] * p[2] + pl[3] < -r) {
                continue;
            }
            let slot = self.count[mi];
            self.vis_cpu[(self.vis_base[mi] + slot) as usize] = i as u32;
            self.count[mi] += 1;
        }
        q.write_buffer(&self.vis, 0, bytemuck_u32(&self.vis_cpu));
    }

    /// CULL_SHADER cullShadow for cascade `k`: casters (flag 1) within `ext` of the cascade centre.
    pub fn cull_shadow(&mut self, q: &wgpu::Queue, k: usize, cx: f32, cz: f32, ext: f32, world: u32) {
        self.count_shadow[k].iter_mut().for_each(|c| *c = 0);
        for i in 0..self.n + self.n_dyn {
            let (mask, mi) = (self.inst[i * W + 13], self.inst[i * W + 12] as usize);
            if mask & world == 0 || mask & 16 != 0 || self.meta[mi].flags & 1 == 0 {
                continue;
            }
            let (p, s) = self.pos(i);
            let r = (self.radius[mi] + 0.1) * s;
            if (p[0] - cx).abs() > ext + r || (p[2] - cz).abs() > ext + r {
                continue;
            }
            let slot = self.count_shadow[k][mi];
            self.vis_shadow_cpu[(self.vis_base[mi] + slot) as usize] = i as u32;
            self.count_shadow[k][mi] += 1;
        }
        q.write_buffer(&self.vis_shadow[k], 0, bytemuck_u32(&self.vis_shadow_cpu));
    }
}

fn bytemuck_u32(v: &[u32]) -> &[u8] {
    // SAFETY: u32 has no padding; the slice covers exactly the vector's elements
    unsafe { std::slice::from_raw_parts(v.as_ptr() as *const u8, std::mem::size_of_val(v)) }
}

/// Frustum planes (inward normals) of a WebGPU view-projection (depth 0..1), as engine/math.js frustumPlanes.
pub fn frustum_planes(vp: &glam::Mat4) -> [[f32; 4]; 6] {
    let r = [vp.row(0), vp.row(1), vp.row(2), vp.row(3)];
    let ps = [r[3] + r[0], r[3] - r[0], r[3] + r[1], r[3] - r[1], r[2], r[3] - r[2]];
    ps.map(|p| {
        let l = p.truncate().length().max(1e-6);
        [p.x / l, p.y / l, p.z / l, p.w / l]
    })
}
