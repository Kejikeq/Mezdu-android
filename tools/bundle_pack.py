"""Copies the part of a content pack the APK carries into its assets: shaders, materials, small textures, the atlas,
light templates, the models with their instances (when exported) and the meshes and voxels (collisions) of chapter 1 (world tiles x 0..2, z 8..9). The rest comes with the updater (stage 2).
    python3 tools/bundle_pack.py <full pack dir> [app/src/main/assets/pack]"""
import json, shutil, sys
from pathlib import Path

KINDS = {'shader', 'materials', 'tex', 'atlas', 'frame', 'models', 'grass'}
MESH_TILES = {(x, z) for x in range(0, 3) for z in range(8, 10)}  # chapter 1 village
src = Path(sys.argv[1])
dst = Path(sys.argv[2] if len(sys.argv) > 2 else 'app/src/main/assets/pack')
m = json.loads((src / 'manifest.json').read_text())
if not any(f.get('kind') == 'frame' for f in m['files']):
    # a pack from an export-native.mjs without meshes and light templates would leave the APK without a world
    print(f"{src}: old pack format (no frame/mesh), bundled pack kept")
    sys.exit(0)
m['files'] = [f for f in m['files'] if f.get('kind') in KINDS or (f.get('kind') in ('mesh', 'world') and (f['tx'], f['tz']) in MESH_TILES)]
m['bundled'] = True
# models and their instances come from a headless game run (`node tools/check.mjs instances` in Kejikeq/-), which
# CI cannot do: a pack without them keeps the bundled ones
kept = []
if not any(f.get('kind') == 'models' for f in m['files']) and (dst / 'manifest.json').exists():
    old = json.loads((dst / 'manifest.json').read_text())
    kept = [f for f in old['files'] if f.get('kind') == 'models']
    keep_tmp = dst.parent / (dst.name + '.models')
    shutil.rmtree(keep_tmp, ignore_errors=True)
    for f in kept:
        (keep_tmp / f['path']).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(dst / f['path'], keep_tmp / f['path'])
shutil.rmtree(dst, ignore_errors=True)
for f in m['files']:
    (dst / f['path']).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / f['path'], dst / f['path'])
for f in kept:
    (dst / f['path']).parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(dst.parent / (dst.name + '.models') / f['path']), dst / f['path'])
    m['files'].append(f)
if kept:
    shutil.rmtree(dst.parent / (dst.name + '.models'), ignore_errors=True)
(dst / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=1))
print(f"{dst}: {len(m['files'])} files, {sum(f['size'] for f in m['files']) // 1024} KB, commit {m['commit'][:7]}")
