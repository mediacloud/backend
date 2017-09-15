#!/bin/bash
#
# Initialize required Perl / Python requirements before running the Perl / Python script.
#

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

source script/set_perlbrew_environment.sh
source script/set_virtualenv_environment.sh

exec "$@"
