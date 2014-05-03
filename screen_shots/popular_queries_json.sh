#!/bin/bash

./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --db-label 'database readonly' -t  -c 'select array_to_json(array_agg(row_to_json(t))) from ( SELECT * from popular_queries where dashboards_id = 1  order by count desc limit 10) t limit 10;' > screen_shots/top_10/pop_queries.json
./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --db-label 'database readonly' -t  -c 'select array_to_json(array_agg(row_to_json(t))) from ( SELECT * from popular_queries where dashboards_id = 1  order by count desc limit 100) t;' > screen_shots/top_100/pop_queries.json
./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --db-label 'database readonly' -t  -c 'select array_to_json(array_agg(row_to_json(t))) from ( SELECT * from popular_queries where dashboards_id = 1  order by count desc limit 1000) t ;' > screen_shots/top_1000/pop_queries.json
./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --db-label 'database readonly' -t  -c 'select array_to_json(array_agg(row_to_json(t))) from ( SELECT * from popular_queries where dashboards_id = 1  order by count desc) t limit 1000;' > screen_shots/all/pop_queries.json


