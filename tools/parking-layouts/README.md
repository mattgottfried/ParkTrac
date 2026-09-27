# Parking lot presets

`genlots.py` turns an OpenStreetMap export (Overpass: `amenity=parking` + `service=parking_aisle`
around the Disney/Universal lots, saved as GeoJSON) into Swift preset data: each named section's
outline and its row lines, sorted across the lot.

    python3 tools/parking-layouts/genlots.py export.geojson ParkTrac/Services/ParkingLayoutData.swift

`ParkTrac/Services/ParkingLayoutData.swift` is the output (14 sections: EPCOT ×8, Hollywood Studios ×5,
Epic Universe Explorer). Row numbers come from `ParkingLots` (the Disney/Universal apps' ranges).
Map data © OpenStreetMap contributors, ODbL.
