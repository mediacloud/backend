#!/bin/bash

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

# Make sure Inline::Python uses correct virtualenv
set +u
source ~/.virtualenvs/mediacloud/bin/activate
set -u

# Also set PYTHONHOME for Python to search for modules at correct location
if [ `uname` == 'Darwin' ]; then
    # greadlink from coreutils
    PYTHONHOME=`greadlink -m ~/.virtualenvs/mediacloud/`
else
    PYTHONHOME=`readlink -m ~/.virtualenvs/mediacloud/`
fi

export PYTHONHOME=$PYTHONHOME
