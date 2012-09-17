#!/bin/bash

cmd_str="$1"
shift
if [ `uname` == 'Darwin' ]; then
	# greadlink from coreutils
	full_path_str=`greadlink -m $cmd_str`
else
	full_path_str=`readlink -m $cmd_str`
fi

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

cd ..

export CARTON_EXTRA_PERL5OPT="-mDevel::NYTProf"
exec ./script/run_wrappered_carton.sh exec -- "$full_path_str" "$@"

