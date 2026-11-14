//! `cargo run -p mezdu-core --bin packcheck -- <pack dir>`: hashes, decompression and naga validation of every shader.
use mezdu_core::{validate_wgsl, Pack};

fn main() {
    let dir = std::env::args().nth(1).unwrap_or_else(|| "pack".into());
    let pack = Pack::open(&dir).unwrap_or_else(|e| {
        eprintln!("{e}");
        std::process::exit(2)
    });
    let m = &pack.manifest;
    println!("pack {} commit {} · {} files", m.version, &m.commit[..m.commit.len().min(7)], m.files.len());
    let mut fails = pack.verify();
    for f in m.files.iter().filter(|f| f.path.ends_with(".zst")).take(2) {
        if let Err(e) = pack.read_data(&f.path) {
            fails.push(e);
        }
    }
    for (name, src) in pack.shaders() {
        match validate_wgsl(&name, &src) {
            Ok(()) => println!("OK    {name}"),
            Err(e) => {
                println!("FAIL  {name}\n{e}");
                fails.push(name);
            }
        }
    }
    if fails.is_empty() {
        println!("pack OK");
    } else {
        println!("{} problem(s): {}", fails.len(), fails.join(", "));
        std::process::exit(1);
    }
}
