constant uint contactSlots = 8;
constant uint emptySlot = 0xFFFFFFFFu;
// Contact treats every node as a sphere one element across. Each substep the nodes are dropped
// into a grid of element-sized cells, then each node pushes away from strangers in the 27 cells
// around it. A cell's header packs the substep's stamp with a count of the slots in use, so
// stale cells read as empty and the grid never needs clearing.
// Contact cells are element-sized cubes over all of space, offset by half an element so that every
// undeformed node sits in the middle of its own cell. They map into a table that wraps space
// periodically, sized to the structure, so memory does not depend on how far debris travels;
// neighbouring cells stay neighbours in memory, and only cells a whole period apart share an
// entry and its slots.
static inline int3 contactCell(float3 position, constant StructureUniforms &u) {
    return int3(floor((position - float3(u.gridOriginX, u.gridOriginY, u.gridOriginZ)) / u.h));
}

static inline uint contactBucket(int3 cell, constant StructureUniforms &u) {
    uint3 wrapped = uint3(cell) & (uint3(u.contactNx, u.contactNy, u.contactNz) - 1u);
    return wrapped.x + u.contactNx * (wrapped.y + u.contactNy * wrapped.z);
}

// The contact grid is filled in two passes, so that what a cell holds does not depend on the
// order in which threads arrive. First every node marks its cell as current and empties it...
kernel void contactClear(const device uint *nodeList [[buffer(0)]],
                         const device StructureNode *nodes [[buffer(1)]],
                         device uint *heads [[buffer(2)]],
                         const device uint *failureGate [[buffer(3)]],
                         const device StepControl &control [[buffer(4)]],
                         constant StructureUniforms &u [[buffer(5)]],
                         device uint *slots [[buffer(6)]],
                         uint threadIndex [[thread_position_in_grid]]) {
    bool active;
    structureStep(u, control, active);
    if (!active || !contactEnabled(u, failureGate)) {
        return;
    }
    if ((nodes[threadIndex].flags & nodeBuried) != 0 || (rubbleParticles && nodes[threadIndex].mass <= 0.0f)) {
        return;
    }
    float3 position = nodePosition(threadIndex, nodeList, nodes, u);
    int3 cell = contactCell(position, u);
    // Several nodes may write the same values here; that is harmless.
    uint target = contactBucket(cell, u);
    heads[target] = u.stamp;
    for (uint slot = 0; slot < contactSlots; ++slot) {
        slots[target * contactSlots + slot] = emptySlot;
    }
}

// Nodes that are not lattice neighbours begin at least two elements apart, so two that have each
// moved less than `contactStill` of an element from where they began are still more than an
// element apart, and cannot touch. The table marks each cell holding a node that has moved
// further, with the substep's stamp, and a node that has not skips the cells left unmarked: the
// pairs skipped are exactly those whose force would be zero. The margin below half an element
// covers round-off in the positions.
constant float contactStill = 0.45f;

static inline bool contactMoved(float3 displacement, constant StructureUniforms &u) {
    return length_squared(displacement) >= (contactStill * u.h) * (contactStill * u.h);
}

// ...then every node offers its index to its cell, which keeps the `contactSlots` smallest in
// ascending order: each slot keeps the smaller of what it holds and what arrives, and passes
// the larger on to the next. A crowded cell therefore always drops the same nodes.
kernel void contactHash(const device uint *nodeList [[buffer(0)]],
                        const device StructureNode *nodes [[buffer(1)]],
                        const device uint *heads [[buffer(2)]],
                        const device uint *failureGate [[buffer(3)]],
                        const device StepControl &control [[buffer(4)]],
                        constant StructureUniforms &u [[buffer(5)]],
                        device atomic_uint *slots [[buffer(6)]],
                        device uint *moved [[buffer(13)]],
                        uint threadIndex [[thread_position_in_grid]]) {
    bool active;
    structureStep(u, control, active);
    if (!active || !contactEnabled(u, failureGate)) {
        return;
    }
    if ((nodes[threadIndex].flags & nodeBuried) != 0 || (rubbleParticles && nodes[threadIndex].mass <= 0.0f)) {
        return;
    }
    float3 position = nodePosition(threadIndex, nodeList, nodes, u);
    int3 cell = contactCell(position, u);
    uint target = contactBucket(cell, u);
    if (contactMoved(float3(nodes[threadIndex].displacement), u)) {
        moved[target] = u.stamp;
    }
    // Compact indices follow lattice order, so the smallest are the same nodes either way.
    uint carried = threadIndex;
    for (uint slot = 0; slot < contactSlots && carried != emptySlot; ++slot) {
        uint held = atomic_fetch_min_explicit(&slots[target * contactSlots + slot], carried, memory_order_relaxed);
        carried = max(held, carried);
    }
}

kernel void contactForces(const device uint *nodeList [[buffer(0)]],
                          const device StructureNode *nodes [[buffer(1)]],
                          const device uint *heads [[buffer(2)]],
                          const device uint *failureGate [[buffer(3)]],
                          const device StepControl &control [[buffer(4)]],
                          constant StructureUniforms &u [[buffer(5)]],
                          device packed_float3 *contact [[buffer(7)]],
                          const device uint *slots [[buffer(8)]],
                          const device RubbleParticle *particles [[buffer(9)]],
                          const device uint *rubbleHeads [[buffer(10)]],
                          const device uint *rubbleSlots [[buffer(11)]],
                          const device uint *rubbleState [[buffer(12)]],
                          const device uint *moved [[buffer(13)]],
                          uint threadIndex [[thread_position_in_grid]]) {
    bool active;
    float dt = structureStep(u, control, active);
    if (!active || !contactEnabled(u, failureGate)) {
        return;
    }
    StructureNode node = nodes[threadIndex];
    if ((node.flags & nodeBuried) != 0) {
        contact[threadIndex] = float3(0.0f);
        return;
    }
    float3 position = nodePosition(threadIndex, nodeList, nodes, u);
    int3 lattice = int3(latticeNode(nodeList[threadIndex], u));

    int3 cell = contactCell(position, u);
    float3 force = float3(0.0f);
    // A node that its own crowded entry dropped is invisible to the others this step, so it does
    // not push them either: every pair then sees each other or neither does, and the forces
    // between them are equal and opposite.
    uint own = contactBucket(cell, u);
    bool listed = false;
    for (uint slot = 0; slot < contactSlots; ++slot) {
        listed = listed || slots[own * contactSlots + slot] == threadIndex;
    }
    if (!listed) {
        contact[threadIndex] = float3(0.0f);
        return;
    }
    bool still = !contactMoved(float3(node.displacement), u);
    for (int dz = -1; dz <= 1; ++dz) {
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                int3 c = cell + int3(dx, dy, dz);
                uint target = contactBucket(c, u);
                if (heads[target] != u.stamp) {
                    continue;  // not touched this substep: whatever it holds is stale
                }
                if (still && moved[target] != u.stamp) {
                    continue;  // nothing in it has moved far enough to touch a node that has not
                }
                // The slots hold the cell's nodes in ascending order, so the forces are summed in
                // the same order whatever the timing of the threads that filled them.
                for (uint slot = 0; slot < contactSlots; ++slot) {
                    uint otherIndex = slots[target * contactSlots + slot];
                    if (otherIndex == emptySlot) {
                        break;
                    }
                    if (otherIndex == threadIndex) {
                        continue;
                    }
                    // Nodes that began as neighbours never repel each other. While joined they are
                    // held apart by their element; once it has failed they may already be closer
                    // than a sphere's width, and a spring switched on there would create energy.
                    // Separated pieces therefore overlap by up to one element before they touch.
                    // Tested first, from the lattice alone: in a structure in one piece nearly
                    // every node near another is its neighbour, and its position need not be read.
                    int3 difference = int3(latticeNode(nodeList[otherIndex], u)) - lattice;
                    if (all(abs(difference) <= 1)) {
                        continue;
                    }
                    float3 otherPosition = nodePosition(otherIndex, nodeList, nodes, u);
                    // An entry can hold nodes of other cells that hash to it; count each node only
                    // when visiting its own cell.
                    if (any(contactCell(otherPosition, u) != c)) {
                        continue;
                    }
                    float3 offset = position - otherPosition;
                    float distance = length(offset);
                    if (distance >= u.h || distance < 1e-9f) {
                        continue;
                    }

                    StructureNode partner = nodes[otherIndex];
                    float3 normal = offset / distance;
                    float mass = min(node.mass, partner.mass);
                    float stiffness = u.contactStiffness * mass;
                    float damping = 2.0f * u.contactDamping * sqrt(stiffness * mass);
                    float3 relative = float3(node.velocity) - float3(partner.velocity);
                    float approach = dot(relative, normal);
                    float push = approach > separationLimit ? 0.0f : max(stiffness * (u.h - distance) - damping * approach, 0.0f);
                    force += push * normal;

                    // Coulomb friction, regularised as a damper at low sliding speed.
                    float3 sliding = relative - approach * normal;
                    float speed = length(sliding);
                    if (speed > 1e-6f) {
                        force -= min(u.contactFriction * push, damping * speed) * (sliding / speed);
                    }
                }
            }
        }
    }
    if (rubbleParticles && rubbleState[0] != 0) {
        force += rubbleOnNode(position, float3(node.velocity), node.mass, particles, rubbleHeads, rubbleSlots, u);
    }
    float largest = node.mass * contactKick / max(dt, 1e-12f);
    float size = length(force);
    if (size > largest) {
        force *= largest / size;
    }
    contact[threadIndex] = force;
}

