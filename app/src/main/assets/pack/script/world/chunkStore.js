// ============================================================================
// CHUNKED VOXEL WORLD STORAGE (32³ + Empty / Solid / Palette / Dense)
// Drop-in replacement for flat worldData array, optimized for ARM L1/L2 caches.
// ============================================================================
import { WX, WY, WZ, CS, CX, CY, CZ, NCH } from './layout.js';
import { matFlags, F_SOLID } from './materials.js';

export const CHUNK_MODE = {
  EMPTY: 0,      // 0 bytes payload (all air in both Dream & Nightmare)
  SOLID: 1,      // 0 bytes payload (single uniform uint16 material pair)
  PALETTE_2B: 2, // 2 bits per voxel (<= 4 unique material pairs)   -> 8 KB + palette
  PALETTE_4B: 3, // 4 bits per voxel (<= 16 unique material pairs)  -> 16 KB + palette
  PALETTE_8B: 4, // 8 bits per voxel (<= 256 unique material pairs) -> 32 KB + palette
  DENSE_U16: 5,  // 16 bits per voxel (raw Uint16Array(32768))      -> 64 KB
};

export const MCX = CX >> 1;
export const MCZ = CZ >> 1;
export const NMCH = MCX * MCZ;

export const CHUNK_STATE = Object.freeze({
  UNLOADED: 0,
  TERRAIN_GENERATING: 1,
  TERRAIN_READY: 2,
  FLORA_GENERATING: 3,
  FLORA_READY: 4,
  ACTIVE: 5,
});

const VOXELS_PER_CHUNK = CS * CS * CS; // 32,768

// shared memory pool: workers read the voxels without copies
// Managed as a large SharedArrayBuffer to eliminate serialization overhead on ARM.
export class SharedVoxelPool {
  static isUsable() {
    if (typeof SharedArrayBuffer === 'undefined') return false;
    try {
      new SharedArrayBuffer(1);
      return true;
    } catch (e) {
      return false;
    }
  }

  constructor(nChunks, hasSAB = false, existingBuffer = null) {
    this.nChunks = nChunks;
    this.hasSAB = hasSAB;
    const BufferType = hasSAB ? SharedArrayBuffer : ArrayBuffer;
    
    // Each chunk stores 1024 occY (u32) = 4KB
    this.occSize = CS * CS * 4;
    this.stride = this.occSize;
    
    this.buffer = existingBuffer || new BufferType(nChunks * this.stride);
    this.occY = new Uint32Array(this.buffer);
  }

  getChunkViews(ci) {
    const oOff = (ci * this.stride) / 4;
    return {
      occY: this.occY.subarray(oOff, oOff + CS * CS)
    };
  }
}

export class ChunkSlot {
  constructor(ci, pool) {
    this.ci = ci;
    this.cx = ci % CX;
    this.cz = Math.floor(ci / CX) % CZ;
    this.cy = Math.floor(ci / (CX * CZ));
    this.mode = CHUNK_MODE.EMPTY;
    this.uniformVal = 0;
    this.palette = null; 
    
    // Direct views into the shared pool for occupancy bitmasks
    if (pool) {
      const { occY } = pool.getChunkViews(ci);
      this.data = null;
      this.occY = occY;
    } else {
      this.data = null;
      this.occY = null;
    }
    
    this.dirty = false;
    this.version = 0;
  }

  byteSize() {
    let bytes = 24; // header overhead
    if (this.palette) bytes += this.palette.byteLength;
    if (this.data) bytes += this.data.byteLength;
    if (this.occY) bytes += this.occY.byteLength;
    return bytes;
  }

  clear() {
    this.mode = CHUNK_MODE.EMPTY;
    this.uniformVal = 0;
    this.palette = null;
    this.data = null;
    if (this.occY) this.occY.fill(0);
    this.dirty = false;
  }

  // Read local voxel (lx, ly, lz in 0..31)
  getLocal(lx, ly, lz) {
    const m = this.mode;
    if (m === CHUNK_MODE.EMPTY) return 0;
    if (m === CHUNK_MODE.SOLID) return this.uniformVal;
    const idx = lx | (lz << 5) | (ly << 10);
    if (m === CHUNK_MODE.DENSE_U16) return this.data[idx];
    if (m === CHUNK_MODE.PALETTE_8B) return this.palette[this.data[idx]];
    if (m === CHUNK_MODE.PALETTE_4B) {
      const word = this.data[idx >> 3];
      const shift = (idx & 7) << 2;
      return this.palette[(word >>> shift) & 0x0f];
    }
    if (m === CHUNK_MODE.PALETTE_2B) {
      const word = this.data[idx >> 4];
      const shift = (idx & 15) << 1;
      return this.palette[(word >>> shift) & 0x03];
    }
    return 0;
  }

  // Promote chunk to DENSE_U16 for fast random writes during explosions or edits
  promoteToDense() {
    if (this.mode === CHUNK_MODE.DENSE_U16) return;
    const dense = new Uint16Array(VOXELS_PER_CHUNK);
    if (this.mode === CHUNK_MODE.SOLID && this.uniformVal !== 0) {
      dense.fill(this.uniformVal);
    } else if (this.mode !== CHUNK_MODE.EMPTY) {
      for (let y = 0; y < CS; y++) {
        for (let z = 0; z < CS; z++) {
          for (let x = 0; x < CS; x++) {
            const idx = x | (z << 5) | (y << 10);
            dense[idx] = this.getLocal(x, y, z);
          }
        }
      }
    }
    this.mode = CHUNK_MODE.DENSE_U16;
    this.data = dense;
    this.palette = null;
    if (!this.occY) {
      this.occY = new Uint32Array(CS * CS);
      this.rebuildOccupancy();
    }
  }

  setLocal(lx, ly, lz, val) {
    const cur = this.getLocal(lx, ly, lz);
    if (cur === val) return false;
    // Fast path if chunk is PALETTE and val already exists in palette
    if (this.mode === CHUNK_MODE.PALETTE_8B || this.mode === CHUNK_MODE.PALETTE_4B || this.mode === CHUNK_MODE.PALETTE_2B) {
      let pIdx = -1;
      const pal = this.palette;
      for (let i = 0; i < pal.length; i++) {
        if (pal[i] === val) { pIdx = i; break; }
      }
      if (pIdx >= 0) {
        const idx = lx | (lz << 5) | (ly << 10);
        if (this.mode === CHUNK_MODE.PALETTE_8B) {
          this.data[idx] = pIdx;
        } else if (this.mode === CHUNK_MODE.PALETTE_4B) {
          const wIdx = idx >> 3, shift = (idx & 7) << 2;
          this.data[wIdx] = (this.data[wIdx] & ~(0x0f << shift)) | ((pIdx & 0x0f) << shift);
        } else {
          const wIdx = idx >> 4, shift = (idx & 15) << 1;
          this.data[wIdx] = (this.data[wIdx] & ~(0x03 << shift)) | ((pIdx & 0x03) << shift);
        }
        this.updateVoxelOccupancy(lx, ly, lz, val);
        this.dirty = true;
        this.version++;
        return true;
      }
    }
    this.promoteToDense();
    const idx = lx | (lz << 5) | (ly << 10);
    this.data[idx] = val;
    this.updateVoxelOccupancy(lx, ly, lz, val);
    this.dirty = true;
    this.version++;
    return true;
  }

  updateVoxelOccupancy(lx, ly, lz, val) {
    if (!this.occY) this.occY = new Uint32Array(CS * CS);
    const d = val & 255, n = val >>> 8;
    const isSolid = ((matFlags[d] | matFlags[n]) & F_SOLID) !== 0;
    const colIdx = lx | (lz << 5);
    if (isSolid) this.occY[colIdx] |= (1 << ly);
    else this.occY[colIdx] &= ~(1 << ly);
  }

  rebuildOccupancy() {
    if (!this.occY) this.occY = new Uint32Array(CS * CS);
    this.occY.fill(0);
    if (this.mode === CHUNK_MODE.EMPTY) return;
    if (this.mode === CHUNK_MODE.SOLID) {
      const d = this.uniformVal & 255, n = this.uniformVal >>> 8;
      if ((matFlags[d] | matFlags[n]) & F_SOLID) this.occY.fill(0xffffffff);
      return;
    }
    for (let y = 0; y < CS; y++) {
      const bit = 1 << y;
      for (let z = 0; z < CS; z++) {
        const zOff = z << 5;
        for (let x = 0; x < CS; x++) {
          const v = this.getLocal(x, y, z);
          if (v !== 0) {
            const d = v & 255, n = v >>> 8;
            if ((matFlags[d] | matFlags[n]) & F_SOLID) {
              this.occY[x | zOff] |= bit;
            }
          }
        }
      }
    }
  }

  getPayload() {
    return {
      mode: this.mode,
      uniformVal: this.uniformVal,
      palette: this.palette,
      data: this.data,
      occY: this.occY,
    };
  }

  setPayload(p) {
    this.mode = p.mode;
    this.uniformVal = p.uniformVal || 0;
    this.palette = p.palette || null;
    this.data = p.data || null;

    if (p.occY) {
      if (this.occY && this.occY.buffer !== p.occY.buffer && this.occY.length === p.occY.length) {
        this.occY.set(p.occY);
      } else {
        this.occY = p.occY;
      }
    }

    this.version = p.version || (this.version + 1);
    this.dirty = false;
  }

  // Compress a DENSE_U16 chunk into EMPTY, SOLID, PALETTE_2B, PALETTE_4B, PALETTE_8B, or keep DENSE_U16
  compress(scratchDense) {
    const src = scratchDense || (this.mode === CHUNK_MODE.DENSE_U16 ? this.data : null);
    if (!src) return;

    const first = src[0];
    let allSame = true;
    for (let i = 1; i < VOXELS_PER_CHUNK; i++) {
      if (src[i] !== first) {
        allSame = false;
        break;
      }
    }
    if (allSame) {
      this.uniformVal = first;
      this.palette = null;
      this.data = null;
      if (first === 0) {
        this.mode = CHUNK_MODE.EMPTY;
        this.occY = null;
      } else {
        this.mode = CHUNK_MODE.SOLID;
        this.rebuildOccupancy();
      }
      return;
    }

    // Build palette of unique (dream | night<<8) values up to 256
    const map = _compressMap;
    const palList = [];
    let overflow = false;
    for (let i = 0; i < VOXELS_PER_CHUNK; i++) {
      const v = src[i];
      if (map[v] === -1) {
        if (palList.length >= 256) {
          overflow = true;
          break;
        }
        map[v] = palList.length;
        palList.push(v);
      }
    }

    if (overflow) {
      for (let i = 0; i < palList.length; i++) map[palList[i]] = -1;
      this.mode = CHUNK_MODE.DENSE_U16;
      this.palette = null;
      this.data = scratchDense ? new Uint16Array(scratchDense) : src;
      this.rebuildOccupancy();
      return;
    }

    const uCount = palList.length;
    this.palette = new Uint16Array(palList);

    if (uCount <= 4) {
      // 2 bits per voxel -> 16 voxels per u32 -> 2048 u32s (8 KB)
      this.mode = CHUNK_MODE.PALETTE_2B;
      const packed = new Uint32Array(VOXELS_PER_CHUNK >> 4);
      for (let i = 0; i < VOXELS_PER_CHUNK; i += 16) {
        let w = 0;
        for (let k = 0; k < 16; k++) {
          w |= (map[src[i + k]] & 0x03) << (k << 1);
        }
        packed[i >> 4] = w >>> 0;
      }
      this.data = packed;
    } else if (uCount <= 16) {
      // 4 bits per voxel -> 8 voxels per u32 -> 4096 u32s (16 KB)
      this.mode = CHUNK_MODE.PALETTE_4B;
      const packed = new Uint32Array(VOXELS_PER_CHUNK >> 3);
      for (let i = 0; i < VOXELS_PER_CHUNK; i += 8) {
        let w = 0;
        for (let k = 0; k < 8; k++) {
          w |= (map[src[i + k]] & 0x0f) << (k << 2);
        }
        packed[i >> 3] = w >>> 0;
      }
      this.data = packed;
    } else {
      // 8 bits per voxel -> 1 byte per voxel -> 32768 bytes (32 KB)
      this.mode = CHUNK_MODE.PALETTE_8B;
      const packed = new Uint8Array(VOXELS_PER_CHUNK);
      for (let i = 0; i < VOXELS_PER_CHUNK; i++) {
        packed[i] = map[src[i]] & 0xff;
      }
      this.data = packed;
    }
    for (let i = 0; i < palList.length; i++) map[palList[i]] = -1;
    this.rebuildOccupancy();
  }
}

const _compressMap = new Int16Array(65536).fill(-1);

export class ChunkedVoxelStorage {
  constructor(rawFlatData, hasSAB = false, existingBuffer = null) {
    this.hasSAB = hasSAB;
    this.pool = new SharedVoxelPool(NCH, hasSAB, existingBuffer);
    this.chunks = new Array(NCH);
    this.slots = this.chunks;
    for (let ci = 0; ci < NCH; ci++) {
      this.chunks[ci] = new ChunkSlot(ci, this.pool);
    }
    // Store chunks in a compressed format (Empty/Solid/Palette/Dense).
    this.raw = null;
    this.stats = {
      empty: NCH,
      solid: 0,
      palette2b: 0,
      palette4b: 0,
      palette8b: 0,
      dense: 0,
      compressedBytes: 0,
      rawBytes: WX * WY * WZ * 2,
      savedMB: 0,
      ratio: 1,
    };
    if (rawFlatData) {
      this.buildFromFlat(rawFlatData);
    }

    // Strict Data-Oriented Macro-Chunk State Machine (O(1) transitions & dense active lists)
    this.macroCount = NMCH;
    this.macroStates = new Uint8Array(NMCH);
    this.macroEmpty = new Uint8Array(NMCH);
    this.macroEpoch = new Uint32Array(NMCH);
    this.activeMask = new Uint8Array(NMCH);
    this.activeChunkBits = new Uint32Array(Math.max(32, Math.ceil(NMCH / 32)));

    this.activeChunks = new Uint16Array(NMCH);
    this.activeCount = 0;
    this.activePos = new Int32Array(NMCH).fill(-1);

    this.activeRenderChunks = new Uint16Array(NMCH);
    this.activeRenderCount = 0;
    this.activeRenderPos = new Int32Array(NMCH).fill(-1);
    this.activeVersion = 0;
  }

  getMacroState(mi) {
    return (mi >= 0 && mi < NMCH) ? this.macroStates[mi] : CHUNK_STATE.UNLOADED;
  }

  isMacroActive(mi) {
    return mi >= 0 && mi < NMCH && this.macroStates[mi] === CHUNK_STATE.ACTIVE;
  }

  canBeginFlora(mi) {
    return mi >= 0 && mi < NMCH && this.macroStates[mi] === CHUNK_STATE.TERRAIN_READY;
  }

  beginTerrain(mi) {
    if (mi < 0 || mi >= NMCH) throw new RangeError(`Invalid macro chunk index: ${mi}`);
    const cur = this.macroStates[mi];
    if (cur !== CHUNK_STATE.UNLOADED) {
      throw new Error(`Chunk ${mi} cannot enter TERRAIN_GENERATING from state ${cur}`);
    }
    this.macroStates[mi] = CHUNK_STATE.TERRAIN_GENERATING;
    this.macroEmpty[mi] = 0;
    const epoch = ++this.macroEpoch[mi];
    return epoch;
  }

  completeTerrain(mi, isEmpty = false, expectedEpoch = this.macroEpoch[mi]) {
    if (mi < 0 || mi >= NMCH) throw new RangeError(`Invalid macro chunk index: ${mi}`);
    if (this.macroEpoch[mi] !== expectedEpoch) return false;
    const cur = this.macroStates[mi];
    if (cur !== CHUNK_STATE.TERRAIN_GENERATING) {
      throw new Error(`Chunk ${mi} cannot enter TERRAIN_READY from state ${cur}`);
    }
    this.macroEmpty[mi] = isEmpty ? 1 : 0;
    this.macroStates[mi] = CHUNK_STATE.TERRAIN_READY;
    return true;
  }

  beginFlora(mi, expectedEpoch = this.macroEpoch[mi]) {
    if (mi < 0 || mi >= NMCH) throw new RangeError(`Invalid macro chunk index: ${mi}`);
    if (this.macroEpoch[mi] !== expectedEpoch) return false;
    const cur = this.macroStates[mi];
    if (cur !== CHUNK_STATE.TERRAIN_READY) {
      throw new Error(`Chunk ${mi} cannot enter FLORA_GENERATING before TERRAIN_READY (state=${cur})`);
    }
    this.macroStates[mi] = CHUNK_STATE.FLORA_GENERATING;
    return true;
  }

  completeFlora(mi, expectedEpoch = this.macroEpoch[mi]) {
    if (mi < 0 || mi >= NMCH) throw new RangeError(`Invalid macro chunk index: ${mi}`);
    if (this.macroEpoch[mi] !== expectedEpoch) return false;
    const cur = this.macroStates[mi];
    if (cur !== CHUNK_STATE.FLORA_GENERATING) {
      throw new Error(`Chunk ${mi} cannot enter FLORA_READY from state ${cur}`);
    }
    this.macroStates[mi] = CHUNK_STATE.FLORA_READY;
    return true;
  }

  _addActiveRender(mi) {
    if (this.activeRenderPos[mi] !== -1) return;
    const idx = this.activeRenderCount++;
    this.activeRenderChunks[idx] = mi;
    this.activeRenderPos[mi] = idx;
  }

  _removeActiveRender(mi) {
    const pos = this.activeRenderPos[mi];
    if (pos === -1) return;
    const lastIdx = --this.activeRenderCount;
    if (pos !== lastIdx) {
      const moved = this.activeRenderChunks[lastIdx];
      this.activeRenderChunks[pos] = moved;
      this.activeRenderPos[moved] = pos;
    }
    this.activeRenderPos[mi] = -1;
  }

  activateChunk(mi, hasRenderGeo = !this.macroEmpty[mi], expectedEpoch = this.macroEpoch[mi]) {
    if (mi < 0 || mi >= NMCH) throw new RangeError(`Invalid macro chunk index: ${mi}`);
    if (this.macroEpoch[mi] !== expectedEpoch) return false;
    const cur = this.macroStates[mi];
    if (cur !== CHUNK_STATE.FLORA_READY) {
      throw new Error(`Chunk ${mi} cannot become ACTIVE from state ${cur} (must be FLORA_READY)`);
    }
    this.macroStates[mi] = CHUNK_STATE.ACTIVE;
    this.macroEmpty[mi] = hasRenderGeo ? 0 : 1;
    this.activeMask[mi] = 1;
    this.activeChunkBits[mi >>> 5] |= (1 << (mi & 31));

    if (this.activePos[mi] === -1) {
      const idx = this.activeCount++;
      this.activeChunks[idx] = mi;
      this.activePos[mi] = idx;
    }
    if (hasRenderGeo) {
      this._addActiveRender(mi);
    } else {
      this._removeActiveRender(mi);
    }
    this.activeVersion++;
    return true;
  }

  updateActiveRenderState(mi, hasRenderGeo) {
    if (mi < 0 || mi >= NMCH || this.macroStates[mi] !== CHUNK_STATE.ACTIVE) return false;
    this.macroEmpty[mi] = hasRenderGeo ? 0 : 1;
    if (hasRenderGeo) this._addActiveRender(mi);
    else this._removeActiveRender(mi);
    this.activeVersion++;
    return true;
  }

  unloadMacro(mi, clearSlots = true) {
    if (mi < 0 || mi >= NMCH) return false;
    const pos = this.activePos[mi];
    if (pos !== -1) {
      const lastIdx = --this.activeCount;
      if (pos !== lastIdx) {
        const moved = this.activeChunks[lastIdx];
        this.activeChunks[pos] = moved;
        this.activePos[moved] = pos;
      }
      this.activePos[mi] = -1;
    }
    this._removeActiveRender(mi);
    this.activeMask[mi] = 0;
    this.activeChunkBits[mi >>> 5] &= ~(1 << (mi & 31));
    this.macroStates[mi] = CHUNK_STATE.UNLOADED;
    this.macroEmpty[mi] = 0;
    this.macroEpoch[mi]++;
    this.activeVersion++;

    if (clearSlots && this.chunks) {
      const mcx = mi % MCX;
      const mcz = (mi / MCX) | 0;
      const cx0 = mcx * 2, cz0 = mcz * 2;
      for (let dy = 0; dy < CY; dy++) {
        for (let sz = 0; sz < 2; sz++) {
          for (let sx = 0; sx < 2; sx++) {
            const ci = (cx0 + sx) + CX * ((cz0 + sz) + CZ * dy);
            const slot = this.chunks[ci];
            if (slot && !slot.dirty && typeof slot.clear === 'function') slot.clear();
          }
        }
      }
    }
    return true;
  }

  resetAllMacroStates(clearSlots = false) {
    this.macroStates.fill(CHUNK_STATE.UNLOADED);
    this.macroEmpty.fill(0);
    for (let i = 0; i < NMCH; i++) this.macroEpoch[i]++;
    this.activeMask.fill(0);
    this.activeChunkBits.fill(0);
    this.activePos.fill(-1);
    this.activeRenderPos.fill(-1);
    this.activeCount = 0;
    this.activeRenderCount = 0;
    this.activeVersion++;
    if (clearSlots && this.chunks) {
      for (let ci = 0; ci < NCH; ci++) {
        const slot = this.chunks[ci];
        if (slot && !slot.dirty && typeof slot.clear === 'function') slot.clear();
      }
    }
  }

  getActiveChunks() {
    return this.activeChunks.subarray(0, this.activeCount);
  }

  getActiveRenderChunks() {
    return this.activeRenderChunks.subarray(0, this.activeRenderCount);
  }

  // Compress all 640 32³ chunks from the generated world array
  buildFromFlat(flat) {
    this.raw = flat;
    const scratch = new Uint16Array(VOXELS_PER_CHUNK);
    for (let ci = 0; ci < NCH; ci++) {
      const slot = this.chunks[ci];
      const ox = slot.cx * CS, oy = slot.cy * CS, oz = slot.cz * CS;
      for (let y = 0; y < CS; y++) {
        const wy = oy + y;
        for (let z = 0; z < CS; z++) {
          const wz = oz + z;
          const wo = ox + WX * (wz + WZ * wy);
          const dstOff = (z << 5) | (y << 10);
          for (let x = 0; x < CS; x++) {
            scratch[dstOff | x] = flat[wo + x];
          }
        }
      }
      slot.compress(scratch);
    }
    this.recalcStats();
  }

  recalcStats() {
    let empty = 0, solid = 0, p2 = 0, p4 = 0, p8 = 0, dense = 0, bytes = 0;
    for (let ci = 0; ci < NCH; ci++) {
      const c = this.chunks[ci];
      bytes += c.byteSize();
      switch (c.mode) {
        case CHUNK_MODE.EMPTY: empty++; break;
        case CHUNK_MODE.SOLID: solid++; break;
        case CHUNK_MODE.PALETTE_2B: p2++; break;
        case CHUNK_MODE.PALETTE_4B: p4++; break;
        case CHUNK_MODE.PALETTE_8B: p8++; break;
        case CHUNK_MODE.DENSE_U16: dense++; break;
      }
    }
    const rawBytes = WX * WY * WZ * 2;
    this.stats.empty = empty;
    this.stats.solid = solid;
    this.stats.palette2b = p2;
    this.stats.palette4b = p4;
    this.stats.palette8b = p8;
    this.stats.dense = dense;
    this.stats.compressedBytes = bytes;
    this.stats.rawBytes = rawBytes;
    this.stats.savedMB = Math.max(0, (rawBytes - bytes) / (1024 * 1024));
    this.stats.ratio = rawBytes / Math.max(1, bytes);
    return this.stats;
  }

  getChunk(cx, cy, cz) {
    if (cx < 0 || cx >= CX || cy < 0 || cy >= CY || cz < 0 || cz >= CZ) return null;
    return this.chunks[cx + CX * (cz + CZ * cy)];
  }

  getVoxel(x, y, z) {
    if (x < 0 || x >= WX || y < 0 || y >= WY || z < 0 || z >= WZ) return 0;
    const cx = x >> 5, cy = y >> 5, cz = z >> 5;
    const slot = this.chunks[cx + CX * (cz + CZ * cy)];
    return slot.getLocal(x & 31, y & 31, z & 31);
  }

  setVoxel(x, y, z, val) {
    if (x < 0 || x >= WX || y < 0 || y >= WY || z < 0 || z >= WZ) return false;
    const cx = x >> 5, cy = y >> 5, cz = z >> 5;
    const ci = cx + CX * (cz + CZ * cy);
    const slot = this.chunks[ci];
    return slot.setLocal(x & 31, y & 31, z & 31, val);
  }

  // Populate a vertical slab (x0..x1, all Y, all Z) directly into chunks
  setVoxelFromSlab(x0, x1, slabData) {
    const sw = x1 - x0;
    const affectedChunks = new Set();
    for (let y = 0; y < WY; y++) {
      const cy = y >> 5;
      const ly = y & 31;
      for (let z = 0; z < WZ; z++) {
        const cz = z >> 5;
        const lz = z & 31;
        const baseIdx = sw * (z + WZ * y);
        for (let x = x0; x < x1; x++) {
          const cx = x >> 5;
          const lx = x & 31;
          const val = slabData[baseIdx + (x - x0)];
          if (val === 0) continue;
          const ci = cx + CX * (cz + CZ * cy);
          const slot = this.chunks[ci];
          slot.setLocal(lx, ly, lz, val);
          affectedChunks.add(ci);
        }
      }
    }
    this.optimizeDirtyChunks(Array.from(affectedChunks));
  }

  // Re-compress dirty chunks that were promoted to dense during an explosion burst
  optimizeDirtyChunks(chunkIndices) {
    if (chunkIndices) {
      for (const ci of chunkIndices) {
        const slot = this.chunks[ci];
        if (slot && slot.mode === CHUNK_MODE.DENSE_U16) {
          slot.compress(slot.data);
        }
      }
    } else {
      for (let ci = 0; ci < NCH; ci++) {
        const slot = this.chunks[ci];
        if (slot && slot.dirty && slot.mode === CHUNK_MODE.DENSE_U16) {
          slot.compress(slot.data);
          slot.dirty = false;
        }
      }
    }
    this.recalcStats();
  }
}

let _slabScratch = null;
let _slabSlot = null;

// Utility for workers to split a slab/column into compressed chunk payloads
export function slabToPayloads(x0, x1, slabData, z0 = 0, z1 = WZ) {
  const sw = x1 - x0;
  const sz = z1 - z0;
  const payloads = {};
  if (!_slabScratch) _slabScratch = new Uint16Array(VOXELS_PER_CHUNK);
  if (!_slabSlot) _slabSlot = new ChunkSlot(0);
  const scratch = _slabScratch;
  const slot = _slabSlot;

  const cx0 = x0 >> 5, cx1 = x1 >> 5;
  const cz0 = z0 >> 5, cz1 = z1 >> 5;
  for (let cy = 0; cy < CY; cy++) {
    const oy = cy * CS;
    for (let cz = cz0; cz < cz1; cz++) {
      const oz = (cz - cz0) * CS;
      for (let cx = cx0; cx < cx1; cx++) {
        const ox = (cx - cx0) * CS;
        let any = false;

        // Single-pass copy into scratch while checking whether chunk is all-empty
        for (let y = 0; y < CS; y++) {
          const soY = sw * sz * (oy + y);
          const dstY = y << 10;
          for (let z = 0; z < CS; z++) {
            const soZ = soY + sw * (oz + z) + ox;
            const dstZ = dstY | (z << 5);
            for (let x = 0; x < CS; x++) {
              const v = slabData[soZ + x];
              scratch[dstZ | x] = v;
              if (v !== 0) any = true;
            }
          }
        }

        if (!any) continue;

        const ci = cx + CX * (cz + CZ * cy);
        slot.occY = null;
        slot.palette = null;
        slot.data = null;
        slot.compress(scratch);
        payloads[ci] = slot.getPayload();
      }
    }
  }
  return payloads;
}

