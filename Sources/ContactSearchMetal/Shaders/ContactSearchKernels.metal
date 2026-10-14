// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
//
// Builds a contact table from points and lists each point's candidates within reach, with the
// functions of ContactSearchFunctions.metal (compiled ahead of this file).

struct CKSUniforms {
    float originX, originY, originZ, cellSize;
    uint periodX, periodY, periodZ, stamp;
    uint count;
    float reach;
    uint maxCandidates;
    uint skipStill;
};

constant uint cksActive = 1u;
constant uint cksMoved = 2u;

kernel void cksClear(const device float4 *points [[buffer(0)]],
                     const device uint *flags [[buffer(1)]],
                     constant CKSUniforms &u [[buffer(2)]],
                     device uint *heads [[buffer(3)]],
                     device uint *slots [[buffer(4)]],
                     uint index [[thread_position_in_grid]]) {
    if (index >= u.count || (flags[index] & cksActive) == 0) {
        return;
    }
    int3 cell = cksCell(points[index].xyz, float3(u.originX, u.originY, u.originZ), u.cellSize);
    cksClearEntry(cksEntry(cell, uint3(u.periodX, u.periodY, u.periodZ)), u.stamp, heads, slots);
}

kernel void cksInsertPoints(const device float4 *points [[buffer(0)]],
                            const device uint *flags [[buffer(1)]],
                            constant CKSUniforms &u [[buffer(2)]],
                            device atomic_uint *slots [[buffer(4)]],
                            device uint *moved [[buffer(5)]],
                            uint index [[thread_position_in_grid]]) {
    if (index >= u.count || (flags[index] & cksActive) == 0) {
        return;
    }
    int3 cell = cksCell(points[index].xyz, float3(u.originX, u.originY, u.originZ), u.cellSize);
    uint entry = cksEntry(cell, uint3(u.periodX, u.periodY, u.periodZ));
    if ((flags[index] & cksMoved) != 0) {
        moved[entry] = u.stamp;
    }
    cksInsert(entry, index, slots);
}

// Each point's candidates within reach, in search order, up to `maxCandidates`; `counts` holds
// how many there were (more than were written when it exceeds `maxCandidates`).
kernel void cksCandidates(const device float4 *points [[buffer(0)]],
                          const device uint *flags [[buffer(1)]],
                          constant CKSUniforms &u [[buffer(2)]],
                          const device uint *heads [[buffer(3)]],
                          const device uint *slots [[buffer(4)]],
                          const device uint *moved [[buffer(5)]],
                          device uint *candidates [[buffer(6)]],
                          device uint *counts [[buffer(7)]],
                          uint index [[thread_position_in_grid]]) {
    if (index >= u.count) {
        return;
    }
    uint found = 0;
    float3 origin = float3(u.originX, u.originY, u.originZ);
    uint3 period = uint3(u.periodX, u.periodY, u.periodZ);
    float3 position = points[index].xyz;
    int3 cell = cksCell(position, origin, u.cellSize);
    if ((flags[index] & cksActive) != 0 && heads[cksEntry(cell, period)] == u.stamp
        && cksListed(cksEntry(cell, period), index, slots)) {
        bool still = u.skipStill != 0 && (flags[index] & cksMoved) == 0;
        for (int dz = -1; dz <= 1; ++dz) {
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    int3 visited = cell + int3(dx, dy, dz);
                    uint entry = cksEntry(visited, period);
                    if (!cksSearches(entry, u.stamp, still, heads, moved)) {
                        continue;
                    }
                    for (uint slot = 0; slot < cksSlotCount; ++slot) {
                        uint other = slots[entry * cksSlotCount + slot];
                        if (other == cksEmptySlot) {
                            break;
                        }
                        if (other == index) {
                            continue;
                        }
                        float3 otherPosition = points[other].xyz;
                        if (any(cksCell(otherPosition, origin, u.cellSize) != visited)) {
                            continue;
                        }
                        if (length(position - otherPosition) >= u.reach) {
                            continue;
                        }
                        if (found < u.maxCandidates) {
                            candidates[index * u.maxCandidates + found] = other;
                        }
                        ++found;
                    }
                }
            }
        }
    }
    counts[index] = found;
}
