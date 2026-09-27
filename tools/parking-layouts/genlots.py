import json, math, sys
d = json.load(open(sys.argv[1]))
MAP = {  # OSM name -> (app lot, app section)
    'Crush': ('EPCOT', 'Crush'), 'Dory': ('EPCOT', 'Dory'), 'Heihei': ('EPCOT', 'HeiHei'), 'Moana': ('EPCOT', 'Moana'),
    'EVE': ('EPCOT', 'Eve'), 'Gamora': ('EPCOT', 'Gamora'), 'Rocket': ('EPCOT', 'Rocket'), 'WALL-E': ('EPCOT', 'WALL-E'),
    'Buzz Lightyear Lot': ('Hollywood Studios', 'Buzz'), 'Jessie Lot': ('Hollywood Studios', 'Jessie'),
    'Mickey Mouse Lot': ('Hollywood Studios', 'Mickey'), 'Minnie Mouse Lot': ('Hollywood Studios', 'Minnie'),
    'Olaf Lot': ('Hollywood Studios', 'Olaf'), 'Explorer': ('Epic Universe', 'Explorer'),
}
def inside(pt, ring):
    x, y = pt; c = False
    for i in range(len(ring)):
        x1, y1 = ring[i]; x2, y2 = ring[i-1]
        if (y1 > y) != (y2 > y) and x < (x2-x1)*(y-y1)/(y2-y1)+x1: c = not c
    return c
aisles = [f['geometry']['coordinates'] for f in d['features']
          if f['properties'].get('service') == 'parking_aisle' and f['geometry']['type'] == 'LineString']
def frame(points):
    lat0 = sum(p[1] for p in points)/len(points); lon0 = sum(p[0] for p in points)/len(points)
    kx = math.cos(math.radians(lat0))*111320; ky = 110540
    return lat0, lon0, kx, ky

def row_lines(lines, fr):
    """Aisles → straight row lines [across, along0, along1] + axes, sorted across the lot."""
    lat0, lon0, kx, ky = fr
    xy = lambda p: ((p[0]-lon0)*kx, (p[1]-lat0)*ky)
    # dominant aisle direction (length-weighted, direction folded)
    sx = sy = 0
    for a in lines:
        (x1, y1), (x2, y2) = xy(a[0]), xy(a[-1])
        dx, dy = x2-x1, y2-y1
        ang = math.atan2(dy, dx)*2
        L = math.hypot(dx, dy); sx += L*math.cos(ang); sy += L*math.sin(ang)
    th = math.atan2(sy, sx)/2
    ux, uy = math.cos(th), math.sin(th)      # along the aisles
    px, py = -uy, ux                          # across the rows
    rows = []
    for a in lines:
        pts = [xy(p) for p in a]
        along = [x*ux+y*uy for x, y in pts]; across = [x*px+y*py for x, y in pts]
        # keep aisles that run with the lot (drop cross-connectors)
        (x1, y1), (x2, y2) = pts[0], pts[-1]
        L = math.hypot(x2-x1, y2-y1)
        if L < 15 or abs((x2-x1)*ux+(y2-y1)*uy)/L < 0.8: continue
        rows.append([sum(across)/len(across), min(along), max(along)])
    rows.sort()
    merged = []
    for r in rows:   # pieces of the same row line (within 4 m across) become one
        if merged and abs(r[0]-merged[-1][0]) < 4:
            m = merged[-1]; m[0] = (m[0]+r[0])/2; m[1] = min(m[1], r[1]); m[2] = max(m[2], r[2])
        else: merged.append(r[:])
    def ll(x, y): return (lat0 + y/ky, lon0 + x/kx)
    def end(c, a): return ll(c*px + a*ux, c*py + a*uy)
    return merged, end

out = []
for f in d['features']:
    n = f['properties'].get('name')
    if f['properties'].get('amenity') != 'parking' or n not in MAP or f['geometry']['type'] != 'Polygon': continue
    ring = f['geometry']['coordinates'][0]
    lines = [a for a in aisles if inside(a[len(a)//2], ring)]
    merged, end = row_lines(lines, frame(ring))
    segs = [(end(c, a0), end(c, a1)) for c, a0, a1 in merged]
    step = max(1, len(ring)//40)
    poly = [(p[1], p[0]) for p in ring[::step]]
    lot, sec = MAP[n]
    out.append((lot, sec, poly, segs))
    print(f"{lot:18} {sec:8} rows={len(segs):2} poly={len(poly)}", file=sys.stderr)

# Lots OSM maps without section names — cut from the parks' lot diagrams (Sept 2026).
# (lot, (lat0, lon0, lat1, lon1) box the aisle midpoints fall in, aisle angle range in degrees
#  from east, order of the lines ('lon' = west→east, 'lat' = north→south),
#  [(section, rows in it)] split across the lines in that order)
GROUPS = [
    # Magic Kingdom: TTC to the north. Heroes west, Villains east; blocks north→south.
    ('Magic Kingdom', (28.4020, -81.5870, 28.4035, -81.5820), (-15, 15), 'lat', [('Woody', 10)]),
    ('Magic Kingdom', (28.4020, -81.5820, 28.4035, -81.5795), (-15, 15), 'lat', [('Aladdin', 9)]),
    ('Magic Kingdom', (28.4020, -81.5795, 28.4035, -81.5773), (-15, 15), 'lat', [('Jafar', 8)]),
    ('Magic Kingdom', (28.4020, -81.5773, 28.4035, -81.5750), (-15, 15), 'lat', [('Zurg', 9)]),
    ('Magic Kingdom', (28.3994, -81.5870, 28.4019, -81.5824), (-15, 15), 'lat', [('Simba', 17)]),
    ('Magic Kingdom', (28.3994, -81.5824, 28.4019, -81.5795), (-15, 15), 'lat', [('Peter Pan', 17)]),
    ('Magic Kingdom', (28.3994, -81.5795, 28.4019, -81.5767), (-15, 15), 'lat', [('Hook', 17)]),
    ('Magic Kingdom', (28.3994, -81.5767, 28.4019, -81.5740), (-15, 15), 'lat', [('Scar', 17)]),
    ('Magic Kingdom', (28.3965, -81.5870, 28.3993, -81.5805), (-15, 15), 'lat', [('Mulan', 20)]),
    ('Magic Kingdom', (28.3965, -81.5805, 28.3993, -81.5785), (-15, 15), 'lat', [('Rapunzel', 12)]),
    ('Magic Kingdom', (28.3965, -81.5785, 28.3993, -81.5762), (-15, 15), 'lat', [('Ursula', 12)]),
    ('Magic Kingdom', (28.3965, -81.5762, 28.3993, -81.5735), (-15, 15), 'lat', [('Cruella', 10)]),
    # Animal Kingdom: entrance to the NW. Peacock + Butterfly in the fan, the south block
    # Dinosaur → Yeti west to east, Unicorn the westmost block.
    ('Animal Kingdom', (28.3495, -81.5935, 28.3530, -81.5895), (10, 40), 'lat', [('Unicorn', 9)]),
    ('Animal Kingdom', (28.3505, -81.5895, 28.3540, -81.5835), (60, 80), 'lon', [('Peacock', 15), ('Butterfly', 13)]),
    ('Animal Kingdom', (28.3485, -81.5895, 28.3505, -81.5835), (85, 95), 'lon', [('Dinosaur', 9), ('Giraffe', 9), ('Yeti', 10)]),
    # Epic Universe: the park is west. Middle row Monster (north) / Viking (south),
    # far row Dragon (north) / Hero (south).
    ('Epic Universe', (28.4382, -81.4426, 28.4410, -81.4385), (80, 100), 'lon', [('Monster', 11), ('Dragon', 10)]),
    ('Epic Universe', (28.4355, -81.4426, 28.4382, -81.4385), (80, 100), 'lon', [('Viking', 11), ('Hero', 11)]),
]

def angle(a):
    lat0 = a[0][1]; k = math.cos(math.radians(lat0))
    d = math.degrees(math.atan2(a[-1][1]-a[0][1], (a[-1][0]-a[0][0])*k)) % 180
    return d - 180 if d > 90 + 45 else d   # -45…135: near-east lines stay near 0

for lot, (la0, lo0, la1, lo1), (g0, g1), order, sections in GROUPS:
    mid = lambda a: ((a[0][0]+a[-1][0])/2, (a[0][1]+a[-1][1])/2)
    lines = [a for a in aisles if la0 < mid(a)[1] < la1 and lo0 < mid(a)[0] < lo1
             and g0 <= angle(a) <= g1
             and math.hypot((a[-1][1]-a[0][1])*110540, (a[-1][0]-a[0][0])*97900) >= 40]
    pts = [p for a in lines for p in a]
    merged, end = row_lines(lines, frame(pts))
    ends = [(end(c, a0), end(c, a1), c, a0, a1) for c, a0, a1 in merged]
    key = (lambda e: (e[0][1]+e[1][1])/2) if order == 'lon' else (lambda e: -(e[0][0]+e[1][0])/2)
    ends.sort(key=key)
    total = sum(n for _, n in sections); start = 0; done = 0
    for sec, n in sections:
        done += n
        stop = round(len(ends)*done/total)
        part = ends[start:stop]; start = stop
        # Outline: a ladder around the section's lines, half a row out on every side
        cs = sorted(e[2] for e in part)
        gap = (cs[-1]-cs[0])/(len(cs)-1)/2 if len(cs) > 1 else 8
        part_c = sorted(part, key=lambda e: e[2])
        side1 = [end(e[2], e[3]-6) for e in part_c]; side2 = [end(e[2], e[4]+6) for e in part_c]
        lo_c, hi_c = part_c[0], part_c[-1]
        poly = ([end(lo_c[2]-gap, lo_c[3]-6)] + side1 + [end(hi_c[2]+gap, hi_c[3]-6),
                 end(hi_c[2]+gap, hi_c[4]+6)] + side2[::-1] + [end(lo_c[2]-gap, lo_c[4]+6)])
        out.append((lot, sec, poly, [(e[0], e[1]) for e in part]))
        print(f"{lot:18} {sec:10} rows={len(part):2} ({n} signs)", file=sys.stderr)

def f6(v): return f"{v:.6f}"
lines = ["import CoreLocation", "",
 "// Generated by tools/parking-layouts/genlots.py from OpenStreetMap (© OpenStreetMap contributors,",
 "// ODbL) parking-aisle lines. Sections OSM names use its outline; Magic Kingdom, Animal Kingdom and",
 "// Epic Universe are cut from the parks' lot diagrams (`GROUPS`). Row lines are sorted across the",
 "// section; OSM has no row numbers — those come from the `ParkingLots` ranges (`ParkingGuess`).",
 "extension ParkingLayouts {", "    static let presets: [ParkingLayout] = ["]
for lot, sec, poly, segs in out:
    lines.append(f'        ParkingLayout(lot: "{lot}", section: "{sec}",')
    lines.append("            outline: [" + ", ".join(f"P({f6(a)}, {f6(b)})" for a, b in poly) + "],")
    lines.append("            rowLines: [")
    for (a, b) in segs:
        lines.append(f"                L({f6(a[0])}, {f6(a[1])}, {f6(b[0])}, {f6(b[1])}),")
    lines.append("            ]),")
lines += ["    ]", "}", ""]
open(sys.argv[2], 'w').write("\n".join(lines))
