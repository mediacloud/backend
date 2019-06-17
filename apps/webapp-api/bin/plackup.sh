#!/bin/bash

set -u
set -e

#
# * "--nproc 1": every container runs a single FastCGI worker; scaling is to be
#   done by increasing Compose replica count, and Nginx in "webapp-httpd" will
#   round-robin between FastCGI workers
#
# * "--access-log /dev/stdout": we can't log to STDOUT directly because then
#   the log gets sent to FastCGI clients too (i.e. Nginx), and Nginx then
#   thinks that FastCGI is throwing errors
#
exec plackup \
    --server FCGI \
    --port 9090 \
    --nproc 1 \
    --access-log /dev/stdout \
    --manager MediaWords::MyFCgiManager \
    /opt/mediacloud/bin/app.psgi
