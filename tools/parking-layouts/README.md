# Parking lot presets (work in progress)

`genlots.py` turns an OpenStreetMap export (Overpass: `amenity=parking` + `service=parking_aisle`
around the Disney/Universal lots, saved as GeoJSON) into Swift preset data: each named section's
outline and its row lines, sorted across the lot.

    python3 genlots.py export.geojson ParkingLayoutData.swift.generated

`ParkingLayoutData.swift.generated` is the current output (14 sections: EPCOT ×8, Hollywood
Studios ×5, Epic Universe Explorer). It is not compiled yet — it moves into
`ParkTrac/Services/` (registered in the pbxproj) once the row ranges per section are added.
Map data © OpenStreetMap contributors, ODbL.
