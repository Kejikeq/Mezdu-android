//! Autosave: where the hero stands and whether a game was running. Written when the app goes to the background,
//! every AUTOSAVE seconds of play and on pause; read at start, so a game the system closed in the background
//! continues where it was. (Slots and deletion: stage 7.3.)

use std::path::Path;

pub const AUTOSAVE: f32 = 20.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Save {
    pub pos: [f32; 3],
    pub yaw: f32,
    pub cam_yaw: f32,
    pub cam_pitch: f32,
    /// the game was on screen (not the menu): the next start opens it paused
    pub playing: bool,
}

const FILE: &str = "save/auto.txt";

pub fn load(data: &Path) -> Option<Save> {
    let t = std::fs::read_to_string(data.join(FILE)).ok()?;
    let v: Vec<f32> = t.split_whitespace().filter_map(|w| w.parse().ok()).collect();
    if v.len() < 7 || v.iter().any(|x| !x.is_finite()) {
        return None;
    }
    Some(Save { pos: [v[0], v[1], v[2]], yaw: v[3], cam_yaw: v[4], cam_pitch: v[5], playing: v[6] > 0.5 })
}

/// tmp + rename: a save cut off by the system never replaces a whole one
pub fn store(data: &Path, s: &Save) {
    let p = data.join(FILE);
    let tmp = p.with_extension("tmp");
    let t = format!("{} {} {} {} {} {} {}\n", s.pos[0], s.pos[1], s.pos[2], s.yaw, s.cam_yaw, s.cam_pitch, s.playing as u8);
    let ok = std::fs::create_dir_all(p.parent().unwrap_or(data)).is_ok() && std::fs::write(&tmp, t).is_ok() && std::fs::rename(&tmp, &p).is_ok();
    if !ok {
        log::warn!("autosave failed: {}", p.display());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let d = std::env::temp_dir().join(format!("mezdu-save-{}", std::process::id()));
        let s = Save { pos: [1.5, 2.0, -3.25], yaw: 0.5, cam_yaw: 1.0, cam_pitch: -0.2, playing: true };
        store(&d, &s);
        assert_eq!(load(&d), Some(s));
        let _ = std::fs::remove_dir_all(&d);
    }
}
