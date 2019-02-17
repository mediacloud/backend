#!/bin/bash

set -u
set -o errexit

cd "$MC_ROOT_DIR"

exec ./script/run_in_env.sh prove -r t/compile.t


