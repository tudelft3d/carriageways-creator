# Roads generation scripts

Code that creates a multi-LoD CityJSON dataset with roads from OpenStreetMap and BGT data.

## Requirements

- `numpy`
- `gdal`
- `geopandas`
- `osmnx`
- `jupyter`

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

### The jupyter notebook

Run `jupyter-notebook` and open `processing.ipynb`

### The basic script does less, for now

- Download an `osm` file (you can use QGIS or JOSM to do so).
- Run `osm2cityjson.py`.

Main syntax is:

```
python osm2cityjson.py [input.osm] [output.json]
```