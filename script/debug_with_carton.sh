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
#echo "$BASHPID"
#echo ./script/run_carton.sh exec -- "$full_path_str" "$@"
export CARTON_EXTRA_PERL5OPT=-d
exec ./script/run_wrappered_carton.sh exec -- "$full_path_str" "$@"

