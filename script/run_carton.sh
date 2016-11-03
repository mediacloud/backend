#!/bin/bash

working_dir=`dirname $0`

source $working_dir/set_perl_brew_environment.sh

set -u
set -o  errexit

# Check if Carton is of version v1.0.0+
#
# v0.9.* used the old "carton.lock" to keep track of specific module versions,
# but since v0.9.65 "carton.lock" was replaced with "cpanfile.snapshot".
#
# While ignoring all v0.* versions is not very specific (for example, v0.9.66
# would still probably work), skipping all versions before v1.0.0 is simple and
# accurate enough for this purpose.
CARTON_VERSION=`carton --version | tr -d '[[:space:]]'` # e.g. "cartonv0.9.15"
if [[ ! "$CARTON_VERSION" == cartonv* ]]; then
    echo "Unable to determine Carton's version." 1>&2
    echo "I've tried running 'carton --version' but got: '$CARTON_VERSION'" 1>&2
    exit 1
fi
if [[ "$CARTON_VERSION" == cartonv0* ]]; then
    echo "You're using Carton version which is too old: '$CARTON_VERSION'" 1>&2
    echo "Run:" 1>&2
    echo "    ./install_modules_outside_of_carton.sh" 1>&2
    echo "to upgrade Carton to the latest version (v1.0.0 or newer)." 1>&2
    exit 1
fi

export PERL_LWP_SSL_VERIFY_HOSTNAME=0

#echo carton "$@"
exec carton "$@"
