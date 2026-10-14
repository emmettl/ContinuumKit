// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
//
// Contact search functions, for applications to compile into their own kernels
// (`MetalContactSearch.functionSource()`) as well as this package's. Adapted from BombCAD's
// structure contact (Structure.metal at 659091b; see docs/extraction/CONTACT_SEARCH.md):
// the same cell, entry and slot arithmetic, with the application's uniforms made arguments.
#include <metal_stdlib>
using namespace metal;

constant uint cksSlotCount = 8;
constant uint cksEmptySlot = 0xFFFFFFFFu;

// The cell holding `position`: cubes of side `cellSize`, offset by `origin`.
static inline int3 cksCell(float3 position, float3 origin, float cellSize) {
    return int3(floor((position - origin) / cellSize));
}

// The table entry of `cell`, in a table that wraps with `period` (powers of two) cells per axis.
static inline uint cksEntry(int3 cell, uint3 period) {
    uint3 wrapped = uint3(cell) & (period - 1u);
    return wrapped.x + period.x * (wrapped.y + period.y * wrapped.z);
}

// First pass: an active point marks its entry as current and empties it. Several points may
// write the same values; that is harmless.
static inline void cksClearEntry(uint entry, uint stamp, device uint *heads, device uint *slots) {
    heads[entry] = stamp;
    for (uint slot = 0; slot < cksSlotCount; ++slot) {
        slots[entry * cksSlotCount + slot] = cksEmptySlot;
    }
}

// Second pass: an active point offers its index to its entry, which keeps the lowest
// `cksSlotCount` in ascending order: each slot keeps the smaller of what it holds and what
// arrives, and passes the larger on. A crowded entry therefore always drops the same points.
static inline void cksInsert(uint entry, uint index, device atomic_uint *slots) {
    uint carried = index;
    for (uint slot = 0; slot < cksSlotCount && carried != cksEmptySlot; ++slot) {
        uint held = atomic_fetch_min_explicit(&slots[entry * cksSlotCount + slot], carried, memory_order_relaxed);
        carried = max(held, carried);
    }
}

// Whether `index` is among the points its own entry kept. One that was dropped must neither see
// nor be seen, so that every pair is seen from both sides or neither.
static inline bool cksListed(uint entry, uint index, const device uint *slots) {
    bool listed = false;
    for (uint slot = 0; slot < cksSlotCount; ++slot) {
        listed = listed || slots[entry * cksSlotCount + slot] == index;
    }
    return listed;
}

// Whether a search visits `entry` this substep: it must be current, and a still point looks only
// in entries marked moved (pairs of still points being out of reach; see the extraction notes).
static inline bool cksSearches(uint entry, uint stamp, bool still, const device uint *heads,
                               const device uint *moved) {
    return heads[entry] == stamp && (!still || moved[entry] == stamp);
}
