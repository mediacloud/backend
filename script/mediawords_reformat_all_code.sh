#!/bin/bash

find script script_archive/ t lib -iname '*.pm' -print0  -or -iname '*.pl' -print0 | xargs -0 -n1 ./script/run_with_carton.sh ./script/mediawords_reformat_code.pl
find script script_archive/ t lib -iname '*.pm.bak' -print0  -or -iname '*.pl.bak' -print0 | xargs -0 rm
