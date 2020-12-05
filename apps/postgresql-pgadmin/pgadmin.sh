#!/bin/bash

exec gunicorn \
    --bind 0.0.0.0:5050 \
    --timeout 60 \
    --workers 1 \
    --threads 25 \
    --chdir /usr/local/lib/python3.8/dist-packages/pgadmin4/ \
    --access-logfile - \
    pgAdmin4:app
