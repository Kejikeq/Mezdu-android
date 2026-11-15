//! Content pack produced by `node tools/export-native.mjs <out>` in the game repo (Kejikeq/-).
//! The pack is the only contract with the web build: never hand-edit its files.
#![allow(non_snake_case)]
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::{Path, PathBuf};

pub const PACK_FORMAT: u32 = 1;

#[derive(Deserialize, Debug, Clone)]
pub struct Constants {
    pub VS: f32,
    pub WX: u32,
    pub WY: u32,
    pub WZ: u32,
    pub CS: u32,
    pub SEED: u32,
    pub TILE: u32,
    pub ATLAS_W: u32,
    pub ATLAS_H: u32,
    pub ATLAS_MIPS: u32,
    pub MAX_MAT: u32,
    pub WORLD_TILE: u32,
}

#[derive(Deserialize, Debug, Clone)]
pub struct FileEntry {
    pub path: String,
    pub sha256: String,
    pub size: u64,
    #[serde(default)]
    pub kind: String,
    pub name: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub mip: Option<u32>,
    pub tx: Option<u32>,
    pub tz: Option<u32>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Manifest {
    pub format: u32,
    pub version: String,
    pub commit: String,
    pub constants: Constants,
    #[serde(rename = "perFrame")]
    pub per_frame: Option<PerFrame>,
    pub files: Vec<FileEntry>,
}

impl Manifest {
    pub fn parse(json: &[u8]) -> Result<Self, String> {
        let m: Manifest = serde_json::from_slice(json).map_err(|e| format!("manifest.json: {e}"))?;
        if m.format != PACK_FORMAT {
            return Err(format!("pack format {} != supported {}", m.format, PACK_FORMAT));
        }
        Ok(m)
    }
    pub fn of_kind<'a>(&'a self, kind: &'a str) -> impl Iterator<Item = &'a FileEntry> + 'a {
        self.files.iter().filter(move |f| f.kind == kind)
    }
}

/// Release assets cannot contain '/', so the published pack flattens paths: `a/b.c` -> `a__b.c`.
pub fn asset_name(path: &str) -> String {
    path.replace('/', "__")
}

/// zstd-compressed bytes (pack files, the downloadable game library)
pub fn unzstd(raw: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    ruzstd::decoding::StreamingDecoder::new(raw).map_err(|e| e.to_string())?.read_to_end(&mut out).map_err(|e| e.to_string())?;
    Ok(out)
}

pub fn sha256_hex(data: &[u8]) -> String {
    Sha256::digest(data).iter().map(|b| format!("{b:02x}")).collect()
}

pub struct Pack {
    pub root: PathBuf,
    pub manifest: Manifest,
}

impl Pack {
    pub fn open(root: impl AsRef<Path>) -> Result<Self, String> {
        let root = root.as_ref().to_path_buf();
        let json = std::fs::read(root.join("manifest.json")).map_err(|e| format!("{}: {e}", root.display()))?;
        Ok(Pack { manifest: Manifest::parse(&json)?, root })
    }
    pub fn read(&self, path: &str) -> Result<Vec<u8>, String> {
        std::fs::read(self.root.join(path)).map_err(|e| format!("{path}: {e}"))
    }
    /// Reads a file and unpacks it when its name ends in `.zst`.
    pub fn read_data(&self, path: &str) -> Result<Vec<u8>, String> {
        let raw = self.read(path)?;
        if !path.ends_with(".zst") {
            return Ok(raw);
        }
        unzstd(&raw).map_err(|e| format!("{path}: {e}"))
    }
    /// Files whose size or sha256 differ from the manifest.
    pub fn verify(&self) -> Vec<String> {
        self.verify_with(&|_| {})
    }

    /// `verify` reporting the share of bytes checked (0..1); the bad entries are the paths, then ": why".
    pub fn verify_with(&self, progress: &dyn Fn(f32)) -> Vec<String> {
        let total: u64 = self.manifest.files.iter().map(|f| f.size).sum::<u64>().max(1);
        let mut done = 0u64;
        let mut bad = Vec::new();
        for f in &self.manifest.files {
            progress(done as f32 / total as f32);
            done += f.size;
            match self.read(&f.path) {
                Ok(d) if d.len() as u64 == f.size && sha256_hex(&d) == f.sha256 => {}
                Ok(_) => bad.push(format!("{}: hash mismatch", f.path)),
                Err(e) => bad.push(e),
            }
        }
        bad
    }
    pub fn shaders(&self) -> Vec<(String, String)> {
        self.manifest
            .of_kind("shader")
            .filter_map(|f| {
                let src = String::from_utf8(self.read(&f.path).ok()?).ok()?;
                Some((f.path.clone(), src))
            })
            .collect()
    }
}

/// Parses and validates WGSL with naga (the same front end wgpu uses). Err holds a readable report.
pub fn validate_wgsl(name: &str, src: &str) -> Result<(), String> {
    let module = naga::front::wgsl::parse_str(src).map_err(|e| e.emit_to_string_with_path(src, name))?;
    naga::valid::Validator::new(naga::valid::ValidationFlags::all(), naga::valid::Capabilities::all())
        .validate(&module)
        .map_err(|e| e.emit_to_string_with_path(src, name))?;
    Ok(())
}

/// Quads of one macro chunk (64 x 128 x 64 voxels) as the web mesher builds them (`mesh/<tx>_<tz>.bin.zst`).
pub struct MacroMesh {
    pub mcx: u32,
    pub mcz: u32,
    /// quads per group: dream-only, both worlds, nightmare-only, then the same three for leaves
    pub c0: [u32; 6],
    /// 3 u32 per quad, groups in the order of `c0`
    pub faces: Vec<u32>,
    /// water quads of the macro-chunk (3 u32 per quad, drawn by vsWater)
    pub water: Vec<u32>,
}

impl MacroMesh {
    pub fn parse_tile(bytes: &[u8]) -> Result<Vec<MacroMesh>, String> {
        let w: Vec<u32> = bytes.as_chunks::<4>().0.iter().map(|b| u32::from_le_bytes(*b)).collect();
        let mut out = Vec::new();
        let mut i = 0;
        while i < w.len() {
            if i + 9 > w.len() {
                return Err("mesh: truncated header".into());
            }
            let c0 = [w[i + 2], w[i + 3], w[i + 4], w[i + 5], w[i + 6], w[i + 7]];
            let nq: usize = c0.iter().map(|&c| c as usize).sum();
            let nw = w[i + 8] as usize;
            let f0 = i + 9;
            let end = f0 + (nq + nw) * 3;
            if end > w.len() {
                return Err("mesh: truncated faces".into());
            }
            let water = w[f0 + nq * 3..end].to_vec();
            out.push(MacroMesh { mcx: w[i], mcz: w[i + 1], c0, faces: w[f0..f0 + nq * 3].to_vec(), water });
            i = end;
        }
        Ok(out)
    }
}

pub fn f32s(bytes: &[u8]) -> Vec<f32> {
    bytes.as_chunks::<4>().0.iter().map(|b| f32::from_le_bytes(*b)).collect()
}

#[derive(Deserialize, Debug, Clone, Copy)]
pub struct PerFrame {
    #[serde(rename = "viewProj")]
    pub view_proj: usize,
    #[serde(rename = "invViewProj")]
    pub inv_view_proj: usize,
    pub cam: usize,
    pub time: usize,
    #[serde(rename = "camRight")]
    pub cam_right: usize,
    #[serde(rename = "camUp")]
    pub cam_up: usize,
    pub res: usize,
    #[serde(rename = "outRes")]
    pub out_res: usize,
    #[serde(rename = "prevVP")]
    pub prev_vp: usize,
    pub focal: usize,
    pub floats: usize,
}

/// One model of `models/models.json` (meshed as the game's worker does in 'modelsBatch').
#[derive(Deserialize, Debug, Clone)]
pub struct ModelMeta {
    pub name: String,
    #[serde(rename = "faceStart")]
    pub face_start: u32,
    #[serde(rename = "faceCount")]
    pub face_count: u32,
    pub flags: u32,
    pub pivot: [f32; 3],
    pub vs: f32,
    pub bounds: [f32; 6],
    #[serde(rename = "maxDist")]
    pub max_dist: f32,
    #[serde(rename = "minDist", default)]
    pub min_dist: f32,
}

impl ModelMeta {
    /// bounding radius in metres around the pivot, as renderer.js setModels
    pub fn radius(&self) -> f32 {
        let [x0, y0, z0, x1, y1, z1] = self.bounds;
        let p = self.pivot;
        let mut r: f32 = 0.0;
        for x in [x0, x1] {
            for y in [y0, y1] {
                for z in [z0, z1] {
                    r = r.max(((x - p[0]).powi(2) + (y - p[1]).powi(2) + (z - p[2]).powi(2)).sqrt());
                }
            }
        }
        r * self.vs
    }
}

pub fn u32s(bytes: &[u8]) -> Vec<u32> {
    bytes.as_chunks::<4>().0.iter().map(|b| u32::from_le_bytes(*b)).collect()
}

pub fn parse_models(json: &[u8]) -> Result<Vec<ModelMeta>, String> {
    serde_json::from_slice(json).map_err(|e| format!("models.json: {e}"))
}
