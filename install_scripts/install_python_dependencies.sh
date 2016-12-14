#!/bin/bash

set -e
# no "set -u" because installation scripts address various undefined variables

# Version comparison functions
function verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

function verlt() {
    [ "$1" = "$2" ] && return 1 || verlte "$1" "$2"
}

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    COMMAND_PREFIX=""    # doesn't need sudo as Python gets installed via Homebrew
else
    # assume Ubuntu
    COMMAND_PREFIX="sudo"
fi

echo "Installing (upgrading) Setuptools..."
wget https://bootstrap.pypa.io/ez_setup.py -O - | $COMMAND_PREFIX python2.7 -
wget https://bootstrap.pypa.io/ez_setup.py -O - | $COMMAND_PREFIX python3.5 -

echo "Installing (upgrading) Pip..."
$COMMAND_PREFIX easy_install-2.7 pip
$COMMAND_PREFIX easy_install-3.5 pip

echo "Installing (upgrading) Supervisor..."
# * change dir, otherwise the installer might think we're trying to install from the supervisor/ directory
# * also, Supervisor only supports Python 2.7 at the moment
( cd /tmp; $COMMAND_PREFIX pip2.7 install --upgrade supervisor )

echo "Installing (upgrading) Virtualenv..."
$COMMAND_PREFIX pip2.7 install --upgrade virtualenv
$COMMAND_PREFIX pip3.5 install --upgrade virtualenv

echo "Installing Python 2.7 dependencies..."
$COMMAND_PREFIX pip2.7 install --upgrade -r python_scripts/requirements.txt || {
    # Sometimes fails with some sort of Setuptools error
    echo "'pip2.7 install' failed the first time, retrying..."
    $COMMAND_PREFIX pip2.7 install --upgrade -r python_scripts/requirements.txt
}

echo "Creating mc-venv virtualenv..."
virtualenv --python=python3.5 mc-venv
source mc-venv/bin/activate

echo "Installing Python 3.5 dependencies..."
pip3.5 install --upgrade -r mediacloud/requirements.txt || {
    # Sometimes fails with some sort of Setuptools error
    echo "'pip3.5 install' failed the first time, retrying..."
    pip3.5 install --upgrade -r mediacloud/requirements.txt
}
