#!/bin/bash

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/supervisor_is_up_to_date.inc.sh"
validate_supervisor_version

/usr/local/bin/supervisorctl \
    -c `dirname "$0"`/supervisord.conf \
    -s http://localhost:4398 \
    -u supervisord \
    -p qHujfp7n4J \
    $*
