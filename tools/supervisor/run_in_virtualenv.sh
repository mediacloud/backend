#!/bin/bash
#
# Wrapper for Supervisor scripts wanting to activate Media Cloud's virtualenv
# before running Python 3 scripts
#

working_dir=`dirname $0`
cd "$working_dir/../../"

set -u
set -o errexit

# Make sure Inline::Python uses correct virtualenv
set +u; source mc-venv/bin/activate; set -u

# Also set PYTHONHOME for Python to search for modules at correct location

if [ `uname` == 'Darwin' ]; then
	# greadlink from coreutils
	PYTHONHOME=`greadlink -m mc-venv/`
else
	PYTHONHOME=`readlink -m mc-venv/`
fi

PYTHONHOME=$PYTHONHOME exec python3 "$@"
