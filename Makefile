datadir = data
facilit_exclude = 'Bike-Friendly Parking', 'Potential Bike Path', 'Potential Bike Route', 'Removed'

all: osm nyc city_not_osm

clean_boroughs:
	rm -rf data/boroughs data/nybbwi_14d data/boroughs.zip

boroughs: clean_boroughs
	mkdir -p data
	mkdir -p data/boroughs
	
	@echo "Downloading boroughs..."
	curl -L "https://data.cityofnewyork.us/api/geospatial/tv64-9x69?method=export&format=Shapefile" -o data/boroughs/boroughs.zip
	unzip data/boroughs/boroughs.zip -d data/boroughs/
	
	@echo "Dissolving boroughs"
	ogr2ogr -simplify 0.2 -t_srs EPSG:4326 -overwrite data/boroughs/dissolved.shp data/boroughs/nybbwi_14d/nybbwi.shp -dialect sqlite -sql "select ST_union(ST_buffer(Geometry,0.001)) from nybbwi"

clean_osm:
	rm -rf $(datadir)/osmlines.*

osm_bikelanes: clean_osm
	mkdir -p $(datadir)
	@echo "Downloading OSM data..."
	@echo "Heads up: you need to have osmtogeojson installed for this part: https://github.com/tyrasd/osmtogeojson"
	wget -O $(datadir)/osmlines.json "http://overpass-api.de/api/interpreter?data=[out:json]; ( way[bicycle][bicycle!=no](40.46,-74.28,40.93,-73.72); way[~\"cycleway\"~\".*\"](40.46,-74.28,40.93,-73.72); way[highway=cycleway](40.46,-74.28,40.93,-73.72);); out body; >; out skel qt;"
	osmtogeojson $(datadir)/osmlines.json > $(datadir)/osmlines.geojson
	
	@echo "Clipping"
	ogr2ogr -clipsrc data/boroughs/dissolved.shp data/osmlines.shp data/osmlines.geojson -nlt LINESTRING
	
	@echo "Deleting original files"
	rm $(datadir)/osmlines.json

osm_buffer:
	ogr2ogr -overwrite -t_srs EPSG:2263 $(datadir)/osmlines_2263.shp $(datadir)/osmlines.shp
	ogr2ogr -overwrite -t_srs EPSG:4326 -f "ESRI Shapefile" $(datadir)/osmlines_buffer.shp $(datadir)/osmlines_2263.shp -dialect sqlite -sql "select ST_union(ST_buffer(Geometry, 15)) from osmlines_2263"

osm_pgsql:
	ogr2ogr -skipfailures -overwrite -f PostgreSQL PG:"dbname='nycbikelanes' user='nycbikelanes'" $(datadir)/osmlines.shp -nln osmlines -nlt GEOMETRY
	ogr2ogr -skipfailures -overwrite -f PostgreSQL PG:"dbname='nycbikelanes' user='nycbikelanes'" $(datadir)/osmlines_buffer.shp -nln osmlines_buffer -nlt GEOMETRY

osm: boroughs osm_bikelanes osm_buffer osm_pgsql

nyc_bikelanes:
	rm -f $(datadir)/nyclines.*
	ogr2ogr -where "NOT (FT_Facilit = 'Bike-Friendly Parking' OR FT_Facilit ILIKE 'Potential%' OR FT_Facilit = 'Removed' OR TF_Facilit = 'Bike-Friendly Parking' OR TF_Facilit ILIKE 'Potential%' OR TF_Facilit = 'Removed')" -simplify 0.2 -t_srs EPSG:4326 $(datadir)/nyclines.shp $(datadir)/cscl_bike_routes/original/CSCL_BikeRoute.shp

nyc_pgsql:
	ogr2ogr -skipfailures -overwrite -f PostgreSQL PG:"dbname='nycbikelanes' user='nycbikelanes'" $(datadir)/nyclines.shp -nln nyclines

nyc: nyc_bikelanes nyc_pgsql

city_not_osm:
	rm challenges/city_not_osm/data.geojson
	ogr2ogr -f "GeoJSON" challenges/city_not_osm/data.geojson PG:"dbname='nycbikelanes' user='nycbikelanes'" -sql "`cat challenges/city_not_osm/select_data.sql`"
