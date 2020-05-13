# Roads generation scripts

Code that creates a multi-LoD CityJSON dataset with roads from OpenStreetMap and BGT data.

## Requirements

- `numpy`
- `gdal`
- `geopandas`

## Installation

### Use a virtual environment (Optional)

```
virtualenv venv
. venv/bin/activate
```

### Install dependencies

```
pip install -r requirements.txt
```

## Usage

- Download an `osm` file (you can use QGIS or JOSM to do so).
- Run `osm2cityjson.py`.

Main syntax is:

```
python osm2cityjson.py [input.osm] [output.json]
```