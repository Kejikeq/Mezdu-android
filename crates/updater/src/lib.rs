//! Content-pack updates from the public release "pack" of this repository (built by .github/workflows/pack.yml from
//! the game repo). Runs in a background thread at start-up: the new pack is assembled next to the current one
//! (`pack.tmp`, renamed to `pack.next` when complete) and swapped in when the game builds its world again (start
//! or return from the background), so the game never reads a half-downloaded pack.
//! Kinds the remote pack lacks (models: only a headless game run can export the instances) are kept from the
//! current pack; a remote pack that lacks any other kind the current one has (an older export format) is skipped.
use mezdu_core::{asset_name, sha256_hex, unzstd, Manifest, Pack};
use std::collections::HashSet;
use std::io::Read;
use std::path::{Path, PathBuf};

pub const PACK_URL: &str = "https://github.com/Kejikeq/Mezdu-android/releases/download/pack/";
pub const APK_VERSION_URL: &str = "https://github.com/Kejikeq/Mezdu-android/releases/download/app/apk-version.txt";
pub const APK_URL: &str = "https://github.com/Kejikeq/Mezdu-android/releases/download/app/mezhdu.apk";
/// kinds the CI pack cannot contain: always kept from the installed pack
const LOCAL_KINDS: [&str; 1] = ["models"];

#[derive(Debug, PartialEq)]
pub enum Outcome {
    UpToDate,
    /// a new pack waits in `pack.next` and is installed at the next start
    Staged { commit: String, downloaded: usize, dropped: usize },
    /// the remote pack is of an older export format than the installed one
    Skipped(String),
}

/// Mozilla's roots (the same on every phone); SSL_CERT_FILE=<pem bundle> replaces them (a desktop behind a TLS proxy)
fn agent() -> ureq::Agent {
    use ureq::tls::{parse_pem, PemItem, RootCerts, TlsConfig};
    let roots = std::env::var("SSL_CERT_FILE").ok().and_then(|f| std::fs::read(f).ok()).map(|pem| {
        let certs: Vec<_> = parse_pem(&pem).filter_map(|i| match i {
            Ok(PemItem::Certificate(c)) => Some(c.to_owned()),
            _ => None,
        }).collect();
        RootCerts::new_with_certs(&certs)
    });
    let tls = TlsConfig::builder().root_certs(roots.unwrap_or(RootCerts::WebPki)).build();
    ureq::Agent::new_with_config(ureq::Agent::config_builder().tls_config(tls).build())
}

fn get(url: &str, limit: u64) -> Result<Vec<u8>, String> {
    let mut resp = agent().get(url).call().map_err(|e| format!("{url}: {e}"))?;
    let mut out = Vec::new();
    resp.body_mut().as_reader().take(limit).read_to_end(&mut out).map_err(|e| format!("{url}: {e}"))?;
    Ok(out)
}

/// At start-up, before the pack is opened: replaces `pack` with a staged `pack.next` (rename, then delete).
pub fn install_staged(data_dir: &Path) {
    let (cur, next, old) = (data_dir.join("pack"), data_dir.join("pack.next"), data_dir.join("pack.old"));
    if !next.join("manifest.json").exists() {
        return;
    }
    let _ = std::fs::remove_dir_all(&old);
    if cur.exists() && std::fs::rename(&cur, &old).is_err() {
        return;
    }
    match std::fs::rename(&next, &cur) {
        Ok(()) => log::info!("updater: new pack installed"),
        Err(e) => {
            log::error!("updater: install: {e}");
            let _ = std::fs::rename(&old, &cur);
        }
    }
    let _ = std::fs::remove_dir_all(&old);
}

/// Compares the release with the installed pack and stages the new one when it is newer and complete.
pub fn check_pack(data_dir: &Path) -> Result<Outcome, String> {
    // (a start-up check: the loading screen uses update_now)
    check_pack_with(data_dir, &|_, _| {})
}

/// The loading screen's update stage: a newer pack is downloaded (`progress`: files done, files to fetch) and
/// installed right away, before anything reads the pack.
/// `progress` gets the bytes downloaded so far and the bytes to download in all (known before the first file).
pub fn update_now(data_dir: &Path, progress: &dyn Fn(u64, u64)) -> Result<Outcome, String> {
    let r = check_pack_with(data_dir, progress)?;
    if matches!(r, Outcome::Staged { .. }) {
        install_staged(data_dir);
    }
    Ok(r)
}

/// Downloads again the files of the installed pack that failed the integrity check, when the release still has
/// the same commit; returns how many were repaired.
pub fn repair(data_dir: &Path, bad: &[String]) -> Result<usize, String> {
    let dir = data_dir.join("pack");
    let cur = Pack::open(&dir)?;
    let remote = Manifest::parse(&get(&format!("{PACK_URL}manifest.json"), 1 << 20)?)?;
    let mut n = 0;
    for b in bad {
        let path = b.split(':').next().unwrap_or(b);
        let Some(f) = cur.manifest.files.iter().find(|f| f.path == path) else { continue };
        if !remote.files.iter().any(|r| r.path == f.path && r.sha256 == f.sha256) {
            return Err(format!("{path}: нет в релизе"));
        }
        let d = get(&format!("{PACK_URL}{}", asset_name(&f.path)), f.size + 1)?;
        if sha256_hex(&d) != f.sha256 {
            return Err(format!("{path}: hash mismatch"));
        }
        let p = dir.join(&f.path);
        std::fs::create_dir_all(p.parent().unwrap_or(&dir)).map_err(|e| e.to_string())?;
        std::fs::write(&p, &d).map_err(|e| format!("{path}: {e}"))?;
        n += 1;
    }
    Ok(n)
}

/// File by file against the release: a file missing here or with another sha256 is downloaded, a file the release
/// no longer has is dropped (except the kinds only this device has, `LOCAL_KINDS`), unchanged ones are linked from
/// the installed pack. The result is staged in pack.next (complete or not at all).
fn check_pack_with(data_dir: &Path, progress: &dyn Fn(u64, u64)) -> Result<Outcome, String> {
    let cur = Pack::open(data_dir.join("pack")).ok();
    let remote_json = get(&format!("{PACK_URL}manifest.json"), 1 << 20)?;
    let mut remote = Manifest::parse(&remote_json)?;
    let empty = Vec::new();
    let local = cur.as_ref().map_or(&empty, |p| &p.manifest.files);
    let kinds = |files: &[mezdu_core::FileEntry]| files.iter().map(|f| f.kind.clone()).collect::<HashSet<_>>();
    let (have, got) = (kinds(local), kinds(&remote.files));
    let missing: Vec<_> = have.iter().filter(|k| !got.contains(*k) && !LOCAL_KINDS.contains(&k.as_str())).cloned().collect();
    if !missing.is_empty() {
        return Ok(Outcome::Skipped(format!("release pack {} has no {}", &remote.commit[..7.min(remote.commit.len())], missing.join(", "))));
    }
    // kinds only the installed pack has (models) stay
    let kept: Vec<_> = local.iter().filter(|f| LOCAL_KINDS.contains(&f.kind.as_str()) && !got.contains(&f.kind)).cloned().collect();
    let target: Vec<_> = remote.files.iter().chain(kept.iter()).cloned().collect();
    let same = |a: &[mezdu_core::FileEntry], f: &mezdu_core::FileEntry| a.iter().any(|c| c.path == f.path && c.sha256 == f.sha256);
    let fetch: Vec<_> = target.iter().filter(|f| !same(local, f)).collect();
    let dropped = local.iter().filter(|f| !target.iter().any(|t| t.path == f.path)).count();
    let commit_same = cur.as_ref().is_some_and(|p| p.manifest.commit == remote.commit);
    if fetch.is_empty() && dropped == 0 && commit_same {
        return Ok(Outcome::UpToDate);
    }
    // already staged by an earlier check: nothing to do until it is installed
    if let Ok(st) = Pack::open(data_dir.join("pack.next")) {
        if st.manifest.files.len() == target.len() && target.iter().all(|f| same(&st.manifest.files, f)) {
            return Ok(Outcome::UpToDate);
        }
    }
    // assembled in pack.tmp and renamed to pack.next only when complete: install_staged never sees half a pack
    let next = data_dir.join("pack.tmp");
    let _ = std::fs::remove_dir_all(&next);
    let dest = |rel: &str| -> Result<PathBuf, String> {
        let p = next.join(rel);
        std::fs::create_dir_all(p.parent().unwrap_or(&next)).map_err(|e| e.to_string())?;
        Ok(p)
    };
    let mut downloaded = 0;
    let total: u64 = fetch.iter().map(|f| f.size).sum();
    let mut done: u64 = 0;
    progress(0, total);
    for f in &target {
        let p = dest(&f.path)?;
        if same(local, f) {
            // unchanged: a hard link to the installed file (a copy where links are not possible)
            let src = data_dir.join("pack").join(&f.path);
            if std::fs::hard_link(&src, &p).is_err() {
                std::fs::copy(&src, &p).map_err(|e| format!("{}: {e}", f.path))?;
            }
            continue;
        }
        let d = get(&format!("{PACK_URL}{}", asset_name(&f.path)), f.size + 1)?;
        if sha256_hex(&d) != f.sha256 {
            return Err(format!("{}: hash mismatch", f.path));
        }
        std::fs::write(&p, &d).map_err(|e| format!("{}: {e}", f.path))?;
        downloaded += 1;
        done += f.size;
        progress(done, total);
    }
    remote.files.extend(kept);
    std::fs::write(dest("manifest.json")?, manifest_json(&remote_json, &remote)?).map_err(|e| e.to_string())?;
    let staged = data_dir.join("pack.next");
    let _ = std::fs::remove_dir_all(&staged);
    std::fs::rename(&next, &staged).map_err(|e| format!("stage: {e}"))?;
    Ok(Outcome::Staged { commit: remote.commit.clone(), downloaded, dropped })
}

/// the remote manifest with the kept local files appended to its file list
fn manifest_json(remote_json: &[u8], m: &Manifest) -> Result<Vec<u8>, String> {
    let mut v: serde_json::Value = serde_json::from_slice(remote_json).map_err(|e| e.to_string())?;
    let files: Vec<serde_json::Value> = m
        .files
        .iter()
        .map(|f| {
            let mut o = serde_json::json!({ "path": f.path, "sha256": f.sha256, "size": f.size, "kind": f.kind });
            for (k, val) in [("tx", f.tx), ("tz", f.tz), ("width", f.width), ("height", f.height), ("mip", f.mip)] {
                if let Some(x) = val {
                    o[k] = x.into();
                }
            }
            if let Some(n) = &f.name {
                o["name"] = n.clone().into();
            }
            o
        })
        .collect();
    v["files"] = files.into();
    serde_json::to_vec(&v).map_err(|e| e.to_string())
}

/// The commit of the newest APK (`apk-version.txt`: "<sha7> <date>"); `build` is this binary's commit.
pub fn newer_apk(build: &str) -> Result<Option<String>, String> {
    let txt = String::from_utf8_lossy(&get(APK_VERSION_URL, 4096)?).to_string();
    let remote = txt.split_whitespace().next().unwrap_or("").to_string();
    Ok((!remote.is_empty() && !build.is_empty() && remote != build).then_some(remote))
}

/// How often a running game looks for a new pack (the CI looks at the game repo every 5 minutes too).
pub const PERIOD: std::time::Duration = std::time::Duration::from_secs(300);

/// For a background thread: checks now and then every PERIOD for as long as the game runs; `on_apk` gets the
/// commit of a newer APK once.
pub fn watch(data_dir: PathBuf, build: &'static str, abi: Option<&'static str>, on_apk: impl Fn(String)) {
    let mut told = false;
    loop {
        // the loading screen does the first check itself (update_now); this one starts a period later
        std::thread::sleep(PERIOD);
        if let Some(c) = run(data_dir.clone(), build, abi) {
            if !told {
                on_apk(c);
                told = true;
            }
        }
    }
}

/// One check: pack first, then the code: with an ABI the game library (a new APK only when its launcher is too
/// old), without one the APK.
pub fn run(data_dir: PathBuf, build: &'static str, abi: Option<&str>) -> Option<String> {
    match check_pack(&data_dir) {
        Ok(Outcome::UpToDate) => log::info!("updater: pack is up to date"),
        Ok(Outcome::Staged { commit, downloaded, dropped }) => log::info!("updater: pack {commit} staged ({downloaded} files downloaded, {dropped} dropped), installed at the next loading"),
        Ok(Outcome::Skipped(why)) => log::info!("updater: skipped: {why}"),
        Err(e) => log::warn!("updater: pack: {e}"),
    }
    if let Some(abi) = abi {
        if build.is_empty() {
            return None;
        }
        return match check_code(&data_dir, abi, build, &|_, _| {}) {
            Ok(CodeOutcome::NeedApk { build }) => Some(build),
            Ok(o) => {
                log::info!("updater: code {o:?}");
                None
            }
            Err(e) => {
                log::warn!("updater: code: {e}");
                None
            }
        };
    }
    match newer_apk(build) {
        Ok(Some(c)) => {
            log::info!("updater: a newer APK ({c}) is available: {APK_URL}");
            Some(c)
        }
        Ok(None) => None,
        Err(e) => {
            log::warn!("updater: apk: {e}");
            None
        }
    }
}

/// Base of the release "app": the APK and the game library for each ABI.
pub const APP_URL: &str = "https://github.com/Kejikeq/Mezdu-android/releases/download/app/";

#[derive(Debug, PartialEq)]
pub enum CodeOutcome {
    UpToDate,
    /// a newer game library waits in code/ and starts with the next launch
    Staged { build: String, bytes: u64 },
    /// the newer build needs a newer launcher (or this APK has none): the APK itself must be installed
    NeedApk { build: String },
}

/// The game library of this device's ABI against `code-<abi>.json` of the release
/// ({ build, sha256, size, launcher }): a newer one is downloaded (`libmezdu-<abi>.so.zst`), checked, written
/// read-only to code/libmezdu.so and marked by code/build.txt for the launcher (crates/launcher).
pub fn check_code(data_dir: &Path, abi: &str, running: &str, progress: &dyn Fn(u64, u64)) -> Result<CodeOutcome, String> {
    let j: serde_json::Value = serde_json::from_slice(&get(&format!("{APP_URL}code-{abi}.json"), 4096)?).map_err(|e| e.to_string())?;
    let build = j["build"].as_str().unwrap_or("").to_string();
    let (sha, size, need) = (j["sha256"].as_str().unwrap_or(""), j["size"].as_u64().unwrap_or(0), j["launcher"].as_u64().unwrap_or(1));
    let code = data_dir.join("code");
    if build.is_empty() || build == running {
        return Ok(CodeOutcome::UpToDate);
    }
    let installed: u64 = std::fs::read_to_string(code.join("launcher.txt")).ok().and_then(|t| t.trim().parse().ok()).unwrap_or(0);
    if installed < need {
        return Ok(CodeOutcome::NeedApk { build });
    }
    if std::fs::read_to_string(code.join("build.txt")).map(|b| b.trim() == build).unwrap_or(false) && code.join("libmezdu.so").exists() {
        return Ok(CodeOutcome::Staged { build, bytes: 0 });
    }
    progress(0, size);
    let packed = get(&format!("{APP_URL}libmezdu-{abi}.so.zst"), 64 << 20)?;
    progress(packed.len() as u64, packed.len() as u64);
    let lib = unzstd(&packed)?;
    if sha256_hex(&lib) != sha || lib.len() as u64 != size {
        return Err("game library: hash mismatch".into());
    }
    std::fs::create_dir_all(&code).map_err(|e| e.to_string())?;
    // the launcher takes the library only with build.txt: away while the library is replaced
    let _ = std::fs::remove_file(code.join("build.txt"));
    let tmp = code.join("libmezdu.so.tmp");
    let _ = std::fs::remove_file(&tmp);
    std::fs::write(&tmp, &lib).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // Android 14+ loads dynamically delivered code only from read-only files
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o444)).map_err(|e| e.to_string())?;
    }
    std::fs::rename(&tmp, code.join("libmezdu.so")).map_err(|e| e.to_string())?;
    std::fs::write(code.join("build.txt"), &build).map_err(|e| e.to_string())?;
    Ok(CodeOutcome::Staged { build, bytes: packed.len() as u64 })
}
