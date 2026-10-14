from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'docs/extraction/contact-search-source.json').read_text())
frozen=(root/m['fixture']).read_bytes()
assert hashlib.sha256(frozen).hexdigest()==m['fixtureSHA256'],'frozen BombCAD contact source changed'
lines=frozen.decode().splitlines(keepends=True)
sizes=[b-a+1 for a,b in m['lineRanges']]
assert sum(sizes)==len(lines)
start=0
for size,digest in zip(sizes,m['blockSHA256']):
    assert hashlib.sha256(''.join(lines[start:start+size]).encode()).hexdigest()==digest,'block hash'
    start+=size
functions=(root/'Sources/ContactSearchMetal/Shaders/ContactSearchFunctions.metal').read_text()
kernels=(root/'Sources/ContactSearchMetal/Shaders/ContactSearchKernels.metal').read_text()
# Each arithmetic statement of the original, with its uniforms made arguments, in the package.
adapted=[
 ('return int3(floor((position - float3(u.gridOriginX, u.gridOriginY, u.gridOriginZ)) / u.h));','return int3(floor((position - origin) / cellSize));',functions),
 ('uint3 wrapped = uint3(cell) & (uint3(u.contactNx, u.contactNy, u.contactNz) - 1u);','uint3 wrapped = uint3(cell) & (period - 1u);',functions),
 ('return wrapped.x + u.contactNx * (wrapped.y + u.contactNy * wrapped.z);','return wrapped.x + period.x * (wrapped.y + period.y * wrapped.z);',functions),
 ('heads[target] = u.stamp;','heads[entry] = stamp;',functions),
 ('slots[target * contactSlots + slot] = emptySlot;','slots[entry * cksSlotCount + slot] = cksEmptySlot;',functions),
 ('for (uint slot = 0; slot < contactSlots && carried != emptySlot; ++slot) {','for (uint slot = 0; slot < cksSlotCount && carried != cksEmptySlot; ++slot) {',functions),
 ('uint held = atomic_fetch_min_explicit(&slots[target * contactSlots + slot], carried, memory_order_relaxed);','uint held = atomic_fetch_min_explicit(&slots[entry * cksSlotCount + slot], carried, memory_order_relaxed);',functions),
 ('carried = max(held, carried);','carried = max(held, carried);',functions),
 ('listed = listed || slots[own * contactSlots + slot] == threadIndex;','listed = listed || slots[entry * cksSlotCount + slot] == index;',functions),
 ('if (heads[target] != u.stamp) {','return heads[entry] == stamp && (!still || moved[entry] == stamp);',functions),
 ('if (still && moved[target] != u.stamp) {','return heads[entry] == stamp && (!still || moved[entry] == stamp);',functions),
 ('moved[target] = u.stamp;','moved[entry] = u.stamp;',kernels),
 ('if (any(contactCell(otherPosition, u) != c)) {','if (any(cksCell(otherPosition, origin, u.cellSize) != visited)) {',kernels),
]
text=frozen.decode()
for original,shared,where in adapted:
    assert original in text,'original statement: '+original
    assert shared in where,'adapted statement: '+shared
assert 'constant uint contactSlots = 8;' in text and 'constant uint cksSlotCount = 8;' in functions
print('PASS frozen BombCAD contact source and its %d adapted statements'%len(adapted))
