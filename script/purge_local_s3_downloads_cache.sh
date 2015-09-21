#!/bin/bash

#
# Removes CHI cache files older than 3 (or $ARGV[1]) days
#

set -e

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

MC_ROOT="$PWD/../"
S3_CACHE_ROOT="$MC_ROOT/data/cache/s3_downloads/"
S3_CACHE_DEFAULT_DIR="$S3_CACHE_ROOT/Default/"

if [ ! -z "$1" ]; then
    if [[ ! "$1" =~ ^-?[0-9]+$ ]]; then
        echo "Max. age in days is not an integer."
        exit 1
    fi
    MAX_AGE_DAYS="$1"
else
    MAX_AGE_DAYS="3"
fi

#
# ---
#

if [ ! -d "$S3_CACHE_DEFAULT_DIR" ]; then
    echo "S3 cache 'Default' directory does not exist at: $S3_CACHE_DEFAULT_DIR"
    exit 1
fi

# Verify that the directory has the "0", "1", "2", ..., "e", "f" directory structure
if [ ! -d "$S3_CACHE_DEFAULT_DIR/0" ]; then
    echo "S3 cache 'Default' directory doesn't look like it contains CHI cache: $S3_CACHE_DEFAULT_DIR"
    exit 1
fi

find "$S3_CACHE_DEFAULT_DIR" -name "*.dat" -type f -mtime "+$MAX_AGE_DAYS" -exec rm {} \;

exit 0
