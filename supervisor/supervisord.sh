#!/bin/bash

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine "childlogdir"
cd "$PWD/../"
CHILDLOGDIR=`./script/run_with_carton.sh ./script/mediawords_query_config.pl //supervisor/childlogdir`
if [[ -z "$CHILDLOGDIR" ]]; then
    echo "\"childlogdir\" is undefined in the configuration."
    exit 1
fi
CHILDLOGDIR="$(cd "$CHILDLOGDIR" && pwd )"

cd "supervisor/"
source "$PWD/supervisor_is_up_to_date.inc.sh"
validate_supervisor_version

cd "$PWD/"
/usr/local/bin/supervisord --childlogdir "$CHILDLOGDIR" --configuration "$PWD/supervisord.conf"
