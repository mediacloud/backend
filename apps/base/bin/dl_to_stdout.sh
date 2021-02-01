#!/bin/bash
#
# curl helper for downloading big files, with retries and such
#


set -u
set -e

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 url > file"
    exit 1
fi

URL="$1"

exec curl --fail --location --retry 3 --retry-delay 5 "${URL}"
