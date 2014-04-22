#!/bin/bash

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/supervisor_is_up_to_date.inc.sh"
validate_supervisor_version

supervisorctl \
    --configuration `dirname "$0"`/supervisord.conf \
    --serverurl http://localhost:4398 \
    --username supervisord \
    --password qHujfp7n4J \
    $*
