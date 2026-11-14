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
        let mut out = Vec::new();
        ruzstd::decoding::StreamingDecoder::new(&raw[..])
            .map_err(|e| format!("{path}: {e}"))?
            .read_to_end(&mut out)
            .map_err(|e| format!("{path}: {e}"))?;
        Ok(out)
    }
    /// Files whose size or sha256 differ from the manifest.
    pub fn verify(&self) -> Vec<String> {
        let mut bad = Vec::new();
        for f in &self.manifest.files {
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
