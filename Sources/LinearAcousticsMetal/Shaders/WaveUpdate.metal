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
