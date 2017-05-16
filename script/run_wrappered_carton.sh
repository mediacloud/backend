#!/bin/bash

working_dir=`dirname $0`

source $working_dir/set_perl_brew_environment.sh

set -u
set -o  errexit

# Make sure Inline::Python uses correct virtualenv
set +u; cd "$working_dir/../"; source mc-venv/bin/activate; set -u

# Also set PYTHONHOME for Python to search for modules at correct location

if [ `uname` == 'Darwin' ]; then
	# greadlink from coreutils
	PYTHONHOME=`greadlink -m mc-venv/`
else
	PYTHONHOME=`readlink -m mc-venv/`
fi

#echo carton "$@"
PYTHONHOME=$PYTHONHOME exec $working_dir/mediawords_carton_wrapper.pl "$@"
