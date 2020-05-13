import json, sys, io
from osgeo import ogr
from osgeo import osr

osm_file = "../data/Breda/Breda extract.osm"

highway_types = [
    "primary",
    "secondary",
    "motorway",
    "trunk",
    "tertiary",
    "unclassified",
    "residential",

    "motorway_link",
    "trunk_link",
    "primary_link",
    "secondary_link",
    "tertiary_link",

    "living_street",
    "service",
    "pedestrian",
    "track",
    "bus_guideway",
    "escape",
    "raceway",
    "road"
]

cm = {
  "type": "CityJSON",
  "version": "1.0",
  "CityObjects": {},
  "vertices": []
}

source = osr.SpatialReference()
source.ImportFromEPSG(4326)

target = osr.SpatialReference()
target.ImportFromEPSG(28992)

transform = osr.CoordinateTransformation(source, target)

def is_road(feature):
    return feature.GetFieldAsString("highway") in highway_types

def add_cityobject(feature, citymodel):
    """Adds a CityJSON city object from an OGR feature."""
    geom = feature.GetGeometryRef()
    geom.Transform(transform)
    indices = [i + len(citymodel["vertices"]) for i in range(geom.GetPointCount())]
    for i in range(geom.GetPointCount()):
        citymodel["vertices"].append(geom.GetPoint(i))
    
    bufferDistance = 5
    lod1 = geom.Buffer(bufferDistance).Boundary()
    pcount = lod1.GetPointCount()
    lod1_indices = [i + len(citymodel["vertices"]) for i in range(pcount)]
    for i in range(lod1.GetPointCount()):
        citymodel["vertices"].append(lod1.GetPoint(pcount - i - 1))

    new_object = {
        "type": "Road",
        "attributes": {
            "osm_id": feature.GetFieldAsString("osm_id"),
            "road_type": feature.GetFieldAsString("highway"),
            "name": feature.GetFieldAsString("name")
        },
        "geometry": [
            {
                "type": "MultiLineString",
                "lod": "0.1",
                "boundaries": [
                    indices
                ]
            },
            {
                "type": "MultiSurface",
                "lod": "1",
                "boundaries": [
                    [ lod1_indices ]
                ]
            }
        ]
    }

    citymodel["CityObjects"][feature.GetFieldAsString("osm_id")] = new_object

def main():
    driver = ogr.GetDriverByName("OSM")

    datasource = driver.Open(osm_file, 0)

    if datasource is None:
        print("Oops! Something went wrong with opening the file {}..."
                .format(osm_file))
        return
    else:
        layer = datasource.GetLayerByName("lines")
        for feature in layer:
            if is_road(feature):
                add_cityobject(feature, cm)
    
    if (len(sys.argv) > 2):
        osm_file = sys.argv[1]
        with open(sys.argv[2], 'w') as file:
            json.dump(cm, file)
    else:
        print("Please provide an input and output file.")

if __name__ == "__main__":
    main()