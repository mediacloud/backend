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

echo "Starting profiling..."
echo "Run './script/run_carton.sh exec nytprofhtml' to convert profile output to html after profiling is complete."

echo "Run './script/run_carton.sh exec nytprofcsv' to convert profile output to csv after profiling is complete."

export CARTON_EXTRA_PERL5OPT="-d:NYTProf -mDevel::NYTProf"
exec ./script/run_wrappered_carton.sh exec "$full_path_str" "$@"


