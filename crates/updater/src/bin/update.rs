//! `cargo run -p mezdu-updater --bin update -- <data dir>`: the loading screen's update and integrity stages
//! without the game (the data dir holds `pack/`). SSL_CERT_FILE=<pem> behind a TLS proxy.
fn main() {
    let dir = std::path::PathBuf::from(std::env::args().nth(1).unwrap_or_else(|| ".".into()));
    let r = mezdu_updater::update_now(&dir, &|d, t| eprint!("\r{d}/{t}"));
    eprintln!();
    println!("update: {r:?}");
    match mezdu_core::Pack::open(dir.join("pack")) {
        Ok(p) => {
            let mut bad = p.verify();
            if !bad.is_empty() {
                println!("integrity: {} broken, repair: {:?}", bad.len(), mezdu_updater::repair(&dir, &bad));
                bad = p.verify();
            }
            println!("pack {} · {} files · integrity: {}", &p.manifest.commit[..7], p.manifest.files.len(), if bad.is_empty() { "OK".into() } else { bad.join(", ") });
        }
        Err(e) => println!("pack: {e}"),
    }
}
