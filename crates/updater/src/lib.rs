//! Content-pack updates from the public release "pack" of this repository (built by .github/workflows/pack.yml from
//! the game repo). Runs in a background thread at start-up: the new pack is assembled next to the current one
//! (`pack.tmp`, renamed to `pack.next` when complete) and swapped in when the game builds its world again (start
//! or return from the background), so the game never reads a half-downloaded pack.
//! Kinds the remote pack lacks (models: only a headless game run can export the instances) are kept from the
//! current pack; a remote pack that lacks any other kind the current one has (an older export format) is skipped.
use mezdu_core::{asset_name, sha256_hex, Manifest, Pack};
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
    Staged { commit: String, downloaded: usize },
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
    check_pack_with(data_dir, &|_, _| {})
}

/// The loading screen's update stage: a newer pack is downloaded (`progress`: files done, files to fetch) and
/// installed right away, before anything reads the pack.
pub fn update_now(data_dir: &Path, progress: &dyn Fn(usize, usize)) -> Result<Outcome, String> {
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

fn check_pack_with(data_dir: &Path, progress: &dyn Fn(usize, usize)) -> Result<Outcome, String> {
    let cur = Pack::open(data_dir.join("pack"))?;
    let remote_json = get(&format!("{PACK_URL}manifest.json"), 1 << 20)?;
    let mut remote = Manifest::parse(&remote_json)?;
    let staged = Pack::open(data_dir.join("pack.next")).map(|p| p.manifest.commit).unwrap_or_default();
    if remote.commit == cur.manifest.commit || remote.commit == staged {
        return Ok(Outcome::UpToDate);
    }
    let kinds = |m: &Manifest| m.files.iter().map(|f| f.kind.clone()).collect::<HashSet<_>>();
    let (have, got) = (kinds(&cur.manifest), kinds(&remote));
    let missing: Vec<_> = have.iter().filter(|k| !got.contains(*k) && !LOCAL_KINDS.contains(&k.as_str())).cloned().collect();
    if !missing.is_empty() {
        return Ok(Outcome::Skipped(format!("release pack {} has no {}", &remote.commit[..7.min(remote.commit.len())], missing.join(", "))));
    }
    // kinds only the installed pack has (models) stay
    let kept: Vec<_> = cur.manifest.files.iter().filter(|f| LOCAL_KINDS.contains(&f.kind.as_str()) && !got.contains(&f.kind)).cloned().collect();
    // assembled in pack.tmp and renamed to pack.next only when complete: install_staged never sees half a pack
    let next = data_dir.join("pack.tmp");
    let _ = std::fs::remove_dir_all(&next);
    let write = |rel: &str, data: &[u8]| -> Result<(), String> {
        let p = next.join(rel);
        std::fs::create_dir_all(p.parent().unwrap_or(&next)).map_err(|e| e.to_string())?;
        std::fs::write(&p, data).map_err(|e| format!("{rel}: {e}"))
    };
    let mut downloaded = 0;
    let to_fetch = remote.files.iter().filter(|f| cur.manifest.files.iter().all(|c| c.path != f.path || c.sha256 != f.sha256)).count();
    for f in remote.files.iter().chain(kept.iter()) {
        let local = cur.read(&f.path).ok().filter(|d| d.len() as u64 == f.size && sha256_hex(d) == f.sha256);
        let data = match local {
            Some(d) => d,
            None => {
                let d = get(&format!("{PACK_URL}{}", asset_name(&f.path)), f.size + 1)?;
                if sha256_hex(&d) != f.sha256 {
                    return Err(format!("{}: hash mismatch", f.path));
                }
                downloaded += 1;
                progress(downloaded, to_fetch);
                d
            }
        };
        write(&f.path, &data)?;
    }
    remote.files.extend(kept);
    write("manifest.json", &manifest_json(&remote_json, &remote)?)?;
    let staged = data_dir.join("pack.next");
    let _ = std::fs::remove_dir_all(&staged);
    std::fs::rename(&next, &staged).map_err(|e| format!("stage: {e}"))?;
    Ok(Outcome::Staged { commit: remote.commit.clone(), downloaded })
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
pub fn watch(data_dir: PathBuf, build: &'static str, on_apk: impl Fn(String)) {
    let mut told = false;
    loop {
        // the loading screen does the first check itself (update_now); this one starts a period later
        std::thread::sleep(PERIOD);
        if let Some(c) = run(data_dir.clone(), build) {
            if !told {
                on_apk(c);
                told = true;
            }
        }
    }
}

/// One check: pack first, then the APK.
pub fn run(data_dir: PathBuf, build: &'static str) -> Option<String> {
    match check_pack(&data_dir) {
        Ok(Outcome::UpToDate) => log::info!("updater: pack is up to date"),
        Ok(Outcome::Staged { commit, downloaded }) => log::info!("updater: pack {commit} staged ({downloaded} files downloaded), installed at the next start"),
        Ok(Outcome::Skipped(why)) => log::info!("updater: skipped: {why}"),
        Err(e) => log::warn!("updater: pack: {e}"),
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
