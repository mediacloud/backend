#!/bin/bash

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/supervisor_is_up_to_date.inc.sh"
validate_supervisor_version

cd "$PWD/"
supervisord -c supervisord.conf
