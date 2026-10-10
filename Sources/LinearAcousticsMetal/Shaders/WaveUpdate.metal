// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
// Exact pinned RoomCAD Grid and two source-free kernels; see extraction provenance.
#include <metal_stdlib>
using namespace metal;

        struct Grid { uint nx, ny, nz; float kx, ky, kz; float bx, by, bz; };


        kernel void waveVelocity(device const float* p [[buffer(0)]], device float* ux [[buffer(1)]],
                                 device float* uy [[buffer(2)]], device float* uz [[buffer(3)]],
                                 device const uchar* inside [[buffer(4)]], constant Grid& g [[buffer(5)]],
                                 uint3 id [[thread_position_in_grid]]) {
            if (id.x >= g.nx || id.y >= g.ny || id.z >= g.nz) return;
            uint plane = g.nx * g.ny;
            uint at = id.x + g.nx * id.y + plane * id.z;
            if (!inside[at]) return;
            float here = p[at];
            if (id.x + 1 < g.nx && inside[at + 1]) ux[at] -= g.kx * (p[at + 1] - here);
            if (id.y + 1 < g.ny && inside[at + g.nx]) uy[at] -= g.ky * (p[at + g.nx] - here);
            if (id.z + 1 < g.nz && inside[at + plane]) uz[at] -= g.kz * (p[at + plane] - here);
        }


        kernel void wavePressure(device float* p [[buffer(0)]], device const float* ux [[buffer(1)]],
                                 device const float* uy [[buffer(2)]], device const float* uz [[buffer(3)]],
                                 device const uchar* inside [[buffer(4)]], device const float* faces [[buffer(5)]],
                                 constant Grid& g [[buffer(6)]], uint3 id [[thread_position_in_grid]]) {
            if (id.x >= g.nx || id.y >= g.ny || id.z >= g.nz) return;
            uint plane = g.nx * g.ny;
            uint count = plane * g.nz;
            uint at = id.x + g.nx * id.y + plane * id.z;
            if (!inside[at]) return;
            float divergence = 0;
            float wall = 0;
            float f;
            f = faces[at];             if (f < 0) divergence -= g.bx * ux[at - 1];     else wall += f;
            f = faces[count + at];     if (f < 0) divergence += g.bx * ux[at];         else wall += f;
            f = faces[2 * count + at]; if (f < 0) divergence -= g.by * uy[at - g.nx];  else wall += f;
            f = faces[3 * count + at]; if (f < 0) divergence += g.by * uy[at];         else wall += f;
            f = faces[4 * count + at]; if (f < 0) divergence -= g.bz * uz[at - plane]; else wall += f;
            f = faces[5 * count + at]; if (f < 0) divergence += g.bz * uz[at];         else wall += f;
            p[at] = ((1 - wall) * p[at] - divergence) / (1 + wall);
        }

// End of exact pinned source-free kernel blocks.

// Exact pinned masked injection kernel; destinations are checked unique by source preparation.
        kernel void waveInject(device float* p [[buffer(0)]], device const float* q [[buffer(1)]],
                               device const uint* cells [[buffer(2)]], device const float* weights [[buffer(3)]],
                               constant uint& step [[buffer(4)]], constant uint& count [[buffer(5)]],
                               uint i [[thread_position_in_grid]]) {
            if (i >= count) return;
            p[cells[i]] += q[step] * weights[i];
        }

// End of exact pinned masked injection block.

// Exact pinned full receiver kernel.
        kernel void waveSample(device const float* p [[buffer(0)]], device const float* ux [[buffer(1)]],
                               device const float* uy [[buffer(2)]], device const float* uz [[buffer(3)]],
                               device const uint* cells [[buffer(4)]], device const float* weights [[buffer(5)]],
                               device const uint* velocityCells [[buffer(6)]], device const float* axes [[buffer(7)]],
                               device float* output [[buffer(8)]], device float* velocityOutput [[buffer(9)]],
                               constant Grid& g [[buffer(10)]], constant uint& step [[buffer(11)]],
                               constant uint& steps [[buffer(12)]], constant uint& receivers [[buffer(13)]],
                               uint r [[thread_position_in_grid]]) {
            if (r >= receivers) return;
            float value = 0;
            for (uint k = 0; k < 8; k++) value += p[cells[8 * r + k]] * weights[8 * r + k];
            output[r * steps + step] = value;
            uint at = velocityCells[r];
            uint plane = g.nx * g.ny;
            float3 u = float3((ux[at - 1] + ux[at]) / 2, (uy[at - g.nx] + uy[at]) / 2, (uz[at - plane] + uz[at]) / 2);
            velocityOutput[r * (steps + 1) + step + 1] = dot(u, float3(axes[3 * r], axes[3 * r + 1], axes[3 * r + 2]));
        }
// Pressure-only port of the exact pinned pressure statements; no dummy velocity addresses.
kernel void waveSamplePressure(device const float* p [[buffer(0)]],
 device const uint* cells [[buffer(4)]], device const float* weights [[buffer(5)]],
 device float* output [[buffer(8)]], constant uint& step [[buffer(11)]],
 constant uint& steps [[buffer(12)]], constant uint& receivers [[buffer(13)]],
 uint r [[thread_position_in_grid]]) {
 if (r >= receivers) return;
            float value = 0;
            for (uint k = 0; k < 8; k++) value += p[cells[8 * r + k]] * weights[8 * r + k];
            output[r * steps + step] = value;
}
