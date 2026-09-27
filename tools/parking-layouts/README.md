# Parking lot presets

`genlots.py` turns an OpenStreetMap export (Overpass: `amenity=parking` + `service=parking_aisle`
around the Disney/Universal lots, saved as GeoJSON) into Swift preset data: each named section's
outline and its row lines, sorted across the lot. Lots OSM doesn't name by section (Magic Kingdom,
Animal Kingdom, Epic Universe's Monster/Viking/Dragon/Hero) are cut by `GROUPS`: a box around the
aisle midpoints, an aisle-angle range, an order (west→east or north→south) and the sections with
their row counts, taken from the parks' lot diagrams (Sept 2026).

    python3 tools/parking-layouts/genlots.py export.geojson ParkTrac/Services/ParkingLayoutData.swift

`ParkTrac/Services/ParkingLayoutData.swift` is the output (36 sections: Magic Kingdom ×12, Animal Kingdom ×6,
EPCOT ×8, Hollywood Studios ×5, Epic Universe ×5). Row numbers come from `ParkingLots` (the Disney/Universal apps' ranges).
Map data © OpenStreetMap contributors, ODbL.
