//! The launcher: NativeActivity calls `ANativeActivity_onCreate` here; it loads the game library and forwards the
//! call to the game's own `ANativeActivity_onCreate` (android-activity inside libmezdu.so takes it from there).
//!
//! Which game library:
//! - `<data>/code/libmezdu.so` when the game downloaded a newer build (the game's updater writes it read-only and
//!   then `code/build.txt`; the launcher uses it only when both are there);
//! - otherwise `libmezdu.so` of the APK.
//!
//! Guard: before handing over to a downloaded library the launcher writes `code/booting`; the game deletes it once
//! its first frame is on screen. A `booting` left from the last start means that build did not come up: the launcher
//! deletes it and starts the APK's library, so a broken download can never lock the player out.
use std::path::{Path, PathBuf};

/// Bumped when the launcher changes in a way the game must know about (the game reads `code/launcher.txt`): a
/// newer game build that needs a newer launcher asks for the APK instead of being loaded.
pub const LAUNCHER: u32 = 1;

#[derive(Debug, PartialEq, Eq)]
pub enum Choice {
    /// the APK's library (by soname, found in the APK's lib directory)
    Bundled,
    Downloaded(PathBuf),
}

/// The decision, separated from Android so the desktop tests check it.
pub fn choose(data: &Path) -> Choice {
    let code = data.join("code");
    let (lib, build, booting) = (code.join("libmezdu.so"), code.join("build.txt"), code.join("booting"));
    let _ = std::fs::create_dir_all(&code);
    let _ = std::fs::write(code.join("launcher.txt"), LAUNCHER.to_string());
    if booting.exists() {
        // the downloaded build did not reach its first frame last time: back to the APK's library
        let _ = std::fs::remove_file(&build);
        let _ = std::fs::remove_file(&lib);
        let _ = std::fs::remove_file(&booting);
        return Choice::Bundled;
    }
    if lib.exists() && build.exists() {
        let _ = std::fs::write(&booting, b"");
        return Choice::Downloaded(lib);
    }
    Choice::Bundled
}

#[cfg(target_os = "android")]
mod android {
    use super::*;
    use std::ffi::{c_char, c_int, c_void, CStr, CString};

    const RTLD_NOW: c_int = 2;
    unsafe extern "C" {
        fn dlopen(path: *const c_char, flags: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
        fn dlerror() -> *const c_char;
        fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
    }

    fn log(msg: &str) {
        let (tag, text) = (c"mezdu", CString::new(msg).unwrap_or_default());
        // SAFETY: two valid C strings
        unsafe { __android_log_write(4, tag.as_ptr(), text.as_ptr()) };
    }

    fn open(path: &str) -> *mut c_void {
        let p = CString::new(path).unwrap_or_default();
        // SAFETY: a valid C string; dlerror returns a C string or null
        unsafe {
            let h = dlopen(p.as_ptr(), RTLD_NOW);
            if h.is_null() {
                let e = dlerror();
                let e = if e.is_null() { "?".into() } else { CStr::from_ptr(e).to_string_lossy() };
                log(&format!("launcher: dlopen {path}: {e}"));
            }
            h
        }
    }

    /// The first fields of NDK's ANativeActivity (android/native_activity.h): callbacks, vm, env, clazz,
    /// internalDataPath, ...
    #[repr(C)]
    struct NativeActivityHead {
        callbacks: *mut c_void,
        vm: *mut c_void,
        env: *mut c_void,
        clazz: *mut c_void,
        internal_data_path: *const c_char,
    }

    type OnCreate = unsafe extern "C" fn(*mut c_void, *mut c_void, usize);

    /// # Safety
    /// Called by Android's NativeActivity with its activity.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn ANativeActivity_onCreate(activity: *mut c_void, saved: *mut c_void, saved_size: usize) {
        unsafe {
            let head = &*(activity as *const NativeActivityHead);
            let data = if head.internal_data_path.is_null() { None } else { Some(PathBuf::from(CStr::from_ptr(head.internal_data_path).to_string_lossy().into_owned())) };
            let mut h = std::ptr::null_mut();
            if let Some(Choice::Downloaded(p)) = data.as_deref().map(choose) {
                log(&format!("launcher {LAUNCHER}: downloaded game library {}", p.display()));
                h = open(&p.to_string_lossy());
                if h.is_null() {
                    // unusable: drop it and its marks, start the APK's library
                    if let Some(d) = &data {
                        for f in ["libmezdu.so", "build.txt", "booting"] {
                            let _ = std::fs::remove_file(d.join("code").join(f));
                        }
                    }
                }
            }
            if h.is_null() {
                log(&format!("launcher {LAUNCHER}: game library of the APK"));
                h = open("libmezdu.so");
            }
            if h.is_null() {
                return;
            }
            let f = dlsym(h, c"ANativeActivity_onCreate".as_ptr());
            if f.is_null() {
                log("launcher: no ANativeActivity_onCreate in the game library");
                return;
            }
            let f: OnCreate = std::mem::transmute(f);
            f(activity, saved, saved_size);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("mezdu-launcher-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("code")).unwrap();
        d
    }

    #[test]
    fn bundled_without_download() {
        let d = dir("a");
        assert_eq!(choose(&d), Choice::Bundled);
        assert_eq!(std::fs::read_to_string(d.join("code/launcher.txt")).unwrap(), LAUNCHER.to_string());
    }

    #[test]
    fn downloaded_needs_build_mark() {
        let d = dir("b");
        std::fs::write(d.join("code/libmezdu.so"), b"x").unwrap();
        assert_eq!(choose(&d), Choice::Bundled, "a library without build.txt is half written");
        std::fs::write(d.join("code/build.txt"), b"abc1234").unwrap();
        assert_eq!(choose(&d), Choice::Downloaded(d.join("code/libmezdu.so")));
        assert!(d.join("code/booting").exists());
    }

    #[test]
    fn failed_boot_falls_back() {
        let d = dir("c");
        std::fs::write(d.join("code/libmezdu.so"), b"x").unwrap();
        std::fs::write(d.join("code/build.txt"), b"abc1234").unwrap();
        assert!(matches!(choose(&d), Choice::Downloaded(_)));
        // the game never reached its first frame: booting is still there
        assert_eq!(choose(&d), Choice::Bundled);
        assert!(!d.join("code/libmezdu.so").exists() && !d.join("code/build.txt").exists() && !d.join("code/booting").exists());
        assert_eq!(choose(&d), Choice::Bundled);
    }
}
