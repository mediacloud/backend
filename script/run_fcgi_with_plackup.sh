#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

echo "Running FCGI plackup on PID $$" >&2
exec ./script/run_in_env.sh plackup -I lib -s FCGI --nproc 0 --manager MediaWords::MyFCgiManager
