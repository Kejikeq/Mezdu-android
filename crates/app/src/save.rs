//! Saves as in the web game (src/save.js): slots auto, 1, 2, 3. The autosave is written when the app goes to the
//! background, on pause, on the way to the menu and every AUTOSAVE seconds of play; slots 1-3 by the player from
//! the pause. A game the system closed in the background opens again, paused, where it was.

use std::path::{Path, PathBuf};

pub const AUTOSAVE: f32 = 20.0;
/// "auto" first, as SLOTS in save.js
pub const SLOTS: [&str; 4] = ["auto", "1", "2", "3"];

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Save {
    pub pos: [f32; 3],
    pub yaw: f32,
    pub cam_yaw: f32,
    pub cam_pitch: f32,
    /// the game was on screen (not the menu): the next start opens it paused
    pub playing: bool,
    pub chapter: u32,
    /// seconds of play
    pub playtime: f64,
    /// when it was written, seconds since 1970
    pub time: u64,
}

fn file(data: &Path, slot: &str) -> PathBuf {
    data.join("save").join(format!("{slot}.txt"))
}

pub fn read(data: &Path, slot: &str) -> Option<Save> {
    let t = std::fs::read_to_string(file(data, slot)).ok()?;
    let v: Vec<f64> = t.split_whitespace().filter_map(|w| w.parse().ok()).collect();
    if v.len() < 7 || v.iter().any(|x| !x.is_finite()) {
        return None;
    }
    let f = |i: usize| v[i] as f32;
    // chapter, playtime and time came later: older autosaves read as chapter 1
    let g = |i: usize, d: f64| v.get(i).copied().unwrap_or(d);
    Some(Save { pos: [f(0), f(1), f(2)], yaw: f(3), cam_yaw: f(4), cam_pitch: f(5), playing: v[6] > 0.5, chapter: g(7, 1.0) as u32, playtime: g(8, 0.0), time: g(9, 0.0) as u64 })
}

/// tmp + rename: a save cut off by the system never replaces a whole one
pub fn write(data: &Path, slot: &str, s: &Save) -> bool {
    let p = file(data, slot);
    let tmp = p.with_extension("tmp");
    let t = format!("{} {} {} {} {} {} {} {} {} {}\n", s.pos[0], s.pos[1], s.pos[2], s.yaw, s.cam_yaw, s.cam_pitch, s.playing as u8, s.chapter, s.playtime, s.time);
    let ok = std::fs::create_dir_all(p.parent().unwrap_or(data)).is_ok() && std::fs::write(&tmp, t).is_ok() && std::fs::rename(&tmp, &p).is_ok();
    if !ok {
        log::warn!("save {slot} failed: {}", p.display());
    }
    ok
}

pub fn delete(data: &Path, slot: &str) {
    let _ = std::fs::remove_file(file(data, slot));
}

/// the newest save of all slots (latestSave)
pub fn latest(data: &Path) -> Option<(&'static str, Save)> {
    SLOTS.iter().filter_map(|s| read(data, s).map(|d| (*s, d))).max_by_key(|(_, d)| d.time)
}

pub fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

/// fmtTime: "12 мин", "1 ч 5 мин"
pub fn fmt_playtime(sec: f64) -> String {
    let m = (sec / 60.0) as u64;
    if m >= 60 {
        format!("{} ч {} мин", m / 60, m % 60)
    } else {
        format!("{m} мин")
    }
}

/// fmtDate: "15 нояб., 13:20" in the phone's time zone
pub fn fmt_date(t: u64) -> String {
    const MONTHS: [&str; 12] = ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."];
    let tt = t as libc::time_t;
    // SAFETY: localtime_r fills the zeroed struct it is given and keeps no pointer to it
    let tm = unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&tt, &mut tm);
        tm
    };
    format!("{} {}, {:02}:{:02}", tm.tm_mday, MONTHS[tm.tm_mon.clamp(0, 11) as usize], tm.tm_hour, tm.tm_min)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slots_round_trip_latest_and_delete() {
        let d = std::env::temp_dir().join(format!("mezdu-save-{}", std::process::id()));
        let a = Save { pos: [1.5, 2.0, -3.25], yaw: 0.5, cam_yaw: 1.0, cam_pitch: -0.2, playing: true, chapter: 1, playtime: 90.5, time: 100 };
        let b = Save { time: 200, playing: false, ..a };
        assert!(write(&d, "auto", &a) && write(&d, "2", &b));
        assert_eq!(read(&d, "auto"), Some(a));
        assert_eq!(latest(&d), Some(("2", b)));
        delete(&d, "2");
        assert_eq!(latest(&d), Some(("auto", a)));
        assert_eq!(fmt_playtime(3900.0), "1 ч 5 мин");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn old_autosave_reads() {
        let d = std::env::temp_dir().join(format!("mezdu-old-{}", std::process::id()));
        std::fs::create_dir_all(d.join("save")).unwrap();
        std::fs::write(d.join("save/auto.txt"), "1 2 3 0.5 1 -0.2 1\n").unwrap();
        let s = read(&d, "auto").unwrap();
        assert_eq!((s.chapter, s.time, s.playing), (1, 0, true));
        let _ = std::fs::remove_dir_all(&d);
    }
}

/// The player's settings (a part of DEFAULT_SETTINGS of save.js): look sensitivity, inverted vertical look, the
/// frame counter on screen. Kept in settings.txt.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Settings {
    pub sens: f32,
    pub invert_y: bool,
    pub show_fps: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { sens: 1.0, invert_y: false, show_fps: false }
    }
}

pub fn read_settings(data: &Path) -> Settings {
    let t = std::fs::read_to_string(data.join("settings.txt")).unwrap_or_default();
    let v: Vec<f32> = t.split_whitespace().filter_map(|w| w.parse().ok()).collect();
    if v.len() < 3 || v.iter().any(|x| !x.is_finite()) {
        return Settings::default();
    }
    Settings { sens: v[0].clamp(0.3, 2.5), invert_y: v[1] > 0.5, show_fps: v[2] > 0.5 }
}

pub fn write_settings(data: &Path, s: &Settings) {
    let _ = std::fs::write(data.join("settings.txt"), format!("{} {} {}\n", s.sens, s.invert_y as u8, s.show_fps as u8));
}

/// The story's state of a slot (the scripts' chapter, flags, backpack, world edits) beside its save.
pub fn read_story(data: &Path, slot: &str) -> Option<String> {
    std::fs::read_to_string(data.join("save").join(format!("{slot}.story.json"))).ok()
}

pub fn write_story(data: &Path, slot: &str, json: &str) {
    let p = data.join("save").join(format!("{slot}.story.json"));
    let tmp = p.with_extension("tmp");
    if std::fs::write(&tmp, json).and_then(|_| std::fs::rename(&tmp, &p)).is_err() {
        log::warn!("story save {slot} failed");
    }
}

pub fn delete_story(data: &Path, slot: &str) {
    let _ = std::fs::remove_file(data.join("save").join(format!("{slot}.story.json")));
}
