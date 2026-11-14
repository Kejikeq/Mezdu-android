//! The voxel world of the pack (`world/<tx>_<tz>.bin.zst`) for collisions: duality.js `solid` / `mat`.
use mezdu_core::Pack;

pub const F_SOLID: u8 = 1;
pub const F_LEAF: u8 = 4;

pub struct Voxels {
    pub vs: f32,
    pub wx: i32,
    pub wy: i32,
    pub wz: i32,
    tile: i32,
    tiles_x: i32,
    /// per tile (x + tiles_x * z): voxels x + T * (z + T * y), u16 (dream | nightmare << 8)
    tiles: Vec<Option<Vec<u16>>>,
    flags: [u8; 256],
}

impl Voxels {
    pub fn load(pack: &Pack) -> Result<Self, String> {
        let c = &pack.manifest.constants;
        let tile = c.WORLD_TILE as i32;
        let (tiles_x, tiles_z) = (c.WX as i32 / tile, c.WZ as i32 / tile);
        let mut tiles = vec![None; (tiles_x * tiles_z) as usize];
        let mut n = 0;
        for f in pack.manifest.of_kind("world") {
            let (Some(tx), Some(tz)) = (f.tx, f.tz) else { continue };
            let raw = pack.read_data(&f.path)?;
            tiles[(tx as i32 + tiles_x * tz as i32) as usize] = Some(raw.as_chunks::<2>().0.iter().map(|b| u16::from_le_bytes(*b)).collect());
            n += 1;
        }
        let mut flags = [0u8; 256];
        let mats: serde_json::Value = serde_json::from_slice(&pack.read("materials.json")?).map_err(|e| e.to_string())?;
        for m in mats.as_array().into_iter().flatten() {
            if let (Some(id), Some(fl)) = (m["id"].as_u64(), m["flags"].as_u64()) {
                flags[id as usize & 255] = fl as u8;
            }
        }
        if n == 0 {
            return Err("pack has no world tiles".into());
        }
        Ok(Voxels { vs: c.VS, wx: c.WX as i32, wy: c.WY as i32, wz: c.WZ as i32, tile, tiles_x, tiles, flags })
    }

    /// raw voxel; 0 (air) outside the loaded tiles above ground level, see `solid`
    pub fn vox(&self, x: i32, y: i32, z: i32) -> Option<u16> {
        if x < 0 || z < 0 || y < 0 || x >= self.wx || z >= self.wz || y >= self.wy {
            return None;
        }
        let t = self.tiles[((x / self.tile) + self.tiles_x * (z / self.tile)) as usize].as_ref()?;
        let (lx, lz) = (x % self.tile, z % self.tile);
        Some(t[(lx + self.tile * (lz + self.tile * y)) as usize])
    }

    pub fn mat(&self, x: i32, y: i32, z: i32) -> u8 {
        self.vox(x, y, z).map_or(0, |v| (v & 255) as u8) // the dream world
    }

    pub fn flags(&self, m: u8) -> u8 {
        self.flags[m as usize]
    }

    /// duality.js solid: below the world, outside it and in tiles that are not loaded count as solid
    pub fn solid(&self, x: i32, y: i32, z: i32) -> bool {
        if y < 0 {
            return true;
        }
        if y >= self.wy {
            return false;
        }
        match self.vox(x, y, z) {
            Some(v) => self.flags[(v & 255) as usize] & F_SOLID != 0,
            None => true,
        }
    }

    pub fn solid_m(&self, x: f32, y: f32, z: f32) -> bool {
        self.solid((x / self.vs).floor() as i32, (y / self.vs).floor() as i32, (z / self.vs).floor() as i32)
    }
}
