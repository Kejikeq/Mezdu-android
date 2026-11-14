"""Copies the part of a content pack the APK carries into its assets: shaders, materials, small textures, the atlas,
light templates and the meshes of chapter 1 (world tiles x 0..2, z 8..9). The rest comes with the updater (stage 2).
    python3 tools/bundle_pack.py <full pack dir> [app/src/main/assets/pack]"""
import json, shutil, sys
from pathlib import Path

KINDS = {'shader', 'materials', 'tex', 'atlas', 'frame'}
MESH_TILES = {(x, z) for x in range(0, 3) for z in range(8, 10)}  # chapter 1 village
src = Path(sys.argv[1])
dst = Path(sys.argv[2] if len(sys.argv) > 2 else 'app/src/main/assets/pack')
m = json.loads((src / 'manifest.json').read_text())
if not any(f.get('kind') == 'frame' for f in m['files']):
    # a pack from an export-native.mjs without meshes and light templates would leave the APK without a world
    print(f"{src}: old pack format (no frame/mesh), bundled pack kept")
    sys.exit(0)
m['files'] = [f for f in m['files'] if f.get('kind') in KINDS or (f.get('kind') == 'mesh' and (f['tx'], f['tz']) in MESH_TILES)]
m['bundled'] = True
shutil.rmtree(dst, ignore_errors=True)
for f in m['files']:
    (dst / f['path']).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / f['path'], dst / f['path'])
(dst / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=1))
print(f"{dst}: {len(m['files'])} files, {sum(f['size'] for f in m['files']) // 1024} KB, commit {m['commit'][:7]}")
