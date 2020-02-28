#!/bin/bash

# start simple http server hosting the api, for manual testing of the api

PORT="$1"

if [ -z "$PORT" ]; then
    PORT=9999
fi

exec plackup \
    --server HTTP::Server::Simple \
    --port $PORT \
    --manager MediaWords::MyFCgiManager \
    /opt/mediacloud/bin/app.psgi
