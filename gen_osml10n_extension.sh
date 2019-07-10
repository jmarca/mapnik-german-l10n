#!/bin/bash

# generate psql extension "osml10n"
# from plpgsql scripts
# version must be given as parameter
if [ $# -ne 2 ]; then
  echo "usage: genextension.sh <data_target_dir> <version>" >&2
  exit 1
fi

# check if commands we need are available
for cmd in curl sed basename; do
  if ! command -v $cmd >/dev/null; then
    echo "ERROR: command >>$cmd<< not found, please install!" >&2
    exit 1
  fi
done

# country_osm_grid.sql is now included as lfs object in the repository
# if git-lfs is not installed we will just get a small pointer file
# thus we need to get the file otherwise

# this will replace the pointer file if git-lfs is available at build time
git lfs pull 2>/dev/null >/dev/null

# download from nominatim otherwise
if $(head -n 3 country_osm_grid.sql |grep -q version); then
  rm -f country_osm_grid.sql
  echo -n "git-lfs seems to be unavailable, trying to download country_grid.sql.gz from nominatim.org... "
  curl -s http://www.nominatim.org/data/country_grid.sql.gz |gzip -d >country_osm_grid.sql

  if ! [ -s country_osm_grid.sql ]; then
    rm -f country_osm_grid.sql
    echo "failed."
    exit 1
  else
    echo "done."
  fi
fi

SCRIPTS=plpgsql/*

(
echo "-- complain if script is sourced in psql, rather than via CREATE EXTENSION"
echo '\echo Use "CREATE EXTENSION osml10n" to load this file. \quit'
echo
echo "-- enable ICU any-latin transliteration function -----------------------------------------------------------------"
echo
echo "CREATE OR REPLACE FUNCTION osml10n_kanji_transcript(text)RETURNS text AS"
echo "'\$libdir/osml10n_kanjitranscript', 'osml10n_kanji_transcript'"
echo "LANGUAGE C STRICT;"
echo
echo "-- enable libkakasi based kanji transcription function -----------------------------------------------------------------" 
echo
echo "CREATE OR REPLACE FUNCTION osml10n_translit(text)RETURNS text AS"
echo "'\$libdir/osml10n_translit', 'osml10n_translit'"
echo "LANGUAGE C STRICT;" ) >>osml10n--$2.sql

for f in $SCRIPTS; do
  bn=$(basename $f)
  echo "" >>osml10n--$2.sql
  echo "-- pl/pgSQL code from file $bn -----------------------------------------------------------------" >>osml10n--$2.sql
  cat $f >>osml10n--$2.sql
done
echo "-- country_osm_grid.sql -----------------------------------------------------------------" >>osml10n--$2.sql
sed '/^COPY.*$/,/^\\\.$/d;//d' country_osm_grid.sql |grep -v -e '^--' |grep -v 'CREATE INDEX' | cat -s >>osml10n--$2.sql
echo -e "COPY country_osm_grid (country_code, area, geometry) FROM '$1/osml10n_country_osm_grid.data';\n"  >>osml10n--$2.sql
grep 'CREATE INDEX' country_osm_grid.sql  >>osml10n--$2.sql
echo "GRANT SELECT on country_osm_grid to public;" >>osml10n--$2.sql

echo -e "\n-- country_languages table from http://wiki.openstreetmap.org/wiki/Nominatim/Country_Codes -----------------------------" >>osml10n--$2.sql
echo "CREATE TABLE country_languages(iso text, langs text[]);" >>osml10n--$2.sql
echo "COPY country_languages (iso, langs) FROM '$1/country_languages.data';"  >>osml10n--$2.sql
echo -e "GRANT SELECT on country_languages to public;\n" >>osml10n--$2.sql

echo "
-- function osml10n_version  -----------------------------------------------------------------
CREATE or REPLACE FUNCTION osml10n_version() RETURNS TEXT AS \$\$
 BEGIN
  RETURN '$2';
 END;
\$\$ LANGUAGE 'plpgsql' IMMUTABLE;
" >>osml10n--$2.sql

sed '/^COPY.*$/,/^\\\.$/!d;//d'  country_osm_grid.sql >osml10n_country_osm_grid.data
