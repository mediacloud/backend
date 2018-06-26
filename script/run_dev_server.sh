#!/bin/bash
#
# Run Catalyst webserver on port 3000, auto-restart on code changes
#

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

./script/run_in_env.sh ./script/server.pl \
    --restart \
    --restart_regex '\.yml$|\.yaml$|\.conf|\.pm|\.txt|\.pot?$'
