#!/bin/bash

DIR=`dirname -- "$0"`
cd "$DIR"

source "supervisor_is_up_to_date.inc.sh"
validate_supervisor_version

supervisord -c supervisord.conf
