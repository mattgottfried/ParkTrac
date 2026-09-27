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
out = []
for f in d['features']:
    n = f['properties'].get('name')
    if f['properties'].get('amenity') != 'parking' or n not in MAP or f['geometry']['type'] != 'Polygon': continue
    ring = f['geometry']['coordinates'][0]
    lat0 = sum(p[1] for p in ring)/len(ring); lon0 = sum(p[0] for p in ring)/len(ring)
    kx = math.cos(math.radians(lat0))*111320; ky = 110540
    xy = lambda p: ((p[0]-lon0)*kx, (p[1]-lat0)*ky)
    lines = [a for a in aisles if inside(a[len(a)//2], ring)]
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
    segs = []
    for c, a0, a1 in merged:
        p1 = ll(c*px + a0*ux, c*py + a0*uy); p2 = ll(c*px + a1*ux, c*py + a1*uy)
        segs.append((p1, p2))
    step = max(1, len(ring)//40)
    poly = [(p[1], p[0]) for p in ring[::step]]
    lot, sec = MAP[n]
    out.append((lot, sec, poly, segs))
    print(f"{lot:18} {sec:8} rows={len(segs):2} poly={len(poly)}", file=sys.stderr)

def f6(v): return f"{v:.6f}"
lines = ["import CoreLocation", "",
 "// Generated from OpenStreetMap (© OpenStreetMap contributors, ODbL) — parking lot outlines and",
 "// parking-aisle lines for the sections OSM names. Row lines are sorted across the lot; OSM has",
 "// no row numbers, so the numbering comes from saved spots (`ParkingRowGuess`).",
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
