# Carriageways Creator (CC)

<p align="center">
	<img src="./CC.png"/>
</p>

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

## If you use CC in a scientific context, please cite this article:

Stelios Vitalis, Anna Labetski, Hugo Ledoux & Jantien Stoter (2022) From road centrelines to carriageways-A reconstruction algorithm, PLoS ONE, DOI: 10.1371/journal.pone.0262801 

[Article available here.](https://doi.org/10.1371/journal.pone.0262801)

```
@article{Vitalis2022,
	Author = {Vitalis, Stelios and Labetski, Anna and Ledoux, Hugo and Stoter, Jantien},
	Title = {From road centrelines to carriageways-{A} reconstruction algorithm},
	Journal = {PLoS ONE},
	Year = {2022},
	Volume = {17(2): e0262801},
	Doi = {https://doi.org/10.1371/journal.pone.0262801}
```