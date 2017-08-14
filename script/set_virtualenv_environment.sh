#!/bin/bash

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

# Make sure Inline::Python uses correct virtualenv
set +u
source mc-venv/bin/activate
set -u

# Also set PYTHONHOME for Python to search for modules at correct location
if [ `uname` == 'Darwin' ]; then
    # greadlink from coreutils
    PYTHONHOME=`greadlink -m mc-venv/`
else
    PYTHONHOME=`readlink -m mc-venv/`
fi

export PYTHONHOME=$PYTHONHOME
