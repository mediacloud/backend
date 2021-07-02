#!/bin/bash

set -u
set -e

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

exec "$PWD/nytlabels_http_server.py" --num_threads "$(/container_cpu_limit.sh)"
