#!/bin/bash

set -u
set -o errexit

find script script_archive/ t lib -path t/data -prune -or -iname '*.pm' -print0  -or -iname '*.pl' -print0 -or -iname '*.t'  -print0 | xargs -0 -n 1 -P 8 ./script/run_with_carton.sh ./script/mediawords_reformat_code.pl
find script script_archive/ t lib -iname '*.pm.bak' -print0  -or -iname '*.pl.bak' -print0  -or -iname '*.t.bak'  -print0 | xargs -0 rm
