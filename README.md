# Carriageways Creator (CC)

Jupyter notebooks that create carriageways using areal dataset and OSM

## Requirements

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

### The jupyter notebooks

- Run `jupyter-notebook` and open `processing.ipynb`
- Change the areal dataset path to your dataset
- Run

### Fix dead ends

- Some dead ends are broken. You can fix them with `fix_deadends.ipynb`.

### Stats

- You can extract stats using `road_stats.ipynb`
