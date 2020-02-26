#!/bin/bash

# start simple http server hosting the api, for manual testing of the api

if [ -z "$PORT" ]; then
    PORT=9999
fi

exec plackup \
    --server HTTP::Simple::Server \
    --port $PORT
    --nproc 1 \
    --access-log /dev/stdout \
    /opt/mediacloud/bin/app.psgi
