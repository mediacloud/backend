#!/bin/sh

set -e
# no "set -u" because installation scripts address various undefined variables

# Version comparison functions
function verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

function verlt() {
    [ "$1" = "$2" ] && return 1 || verlte "$1" "$2"
}

# Install / upgrade Setuptools (easy_install) to both Python versions before installing dependencies
wget https://bootstrap.pypa.io/ez_setup.py -O - | sudo python2 -
wget https://bootstrap.pypa.io/ez_setup.py -O - | sudo python3 -

# Install / upgrade Pip to both Python versions before installing dependencies
sudo easy_install-2.7 pip
if [ `uname` == 'Darwin' ]; then
    sudo easy_install3 pip
else
    source /etc/lsb-release
    if verlt "$DISTRIB_RELEASE" "16.04"; then
        # 8.0.0+ doesn't support Python 3.2 on Ubuntu 12.04
        sudo easy_install3 pip==7.1.2
    else
        sudo easy_install3 pip
    fi
fi

# Make sure Pip is latest version to avoid errors
sudo pip2 install --upgrade pip
sudo pip3 install --upgrade pip

# Install (upgrade) Supervisor:
# * change dir, otherwise the installer might think we're trying to install from the supervisor/ directory
# * also, Supervisor only supports Python 2.7 at the moment
( cd /tmp; sudo pip2 install --upgrade supervisor )

# Install (upgrade Virtualenv)
sudo pip2 install --upgrade virtualenv
sudo pip3 install --upgrade virtualenv

# Install Python 2 dependencies
sudo pip install --upgrade -r python_scripts/requirements.txt || {
    # Sometimes fails with some sort of Setuptools error
    echo "'pip install' failed the first time, retrying..."
    sudo pip install --upgrade -r python_scripts/requirements.txt
}

# Create virtualenv and activate it
virtualenv --python=python3 mc-venv
source mc-venv/bin/activate

# Install Python 3 dependencies (no sudo because we're in virtualenv)
pip3 install --upgrade -r mediacloud/requirements.txt || {
    # Sometimes fails with some sort of Setuptools error
    echo "'pip install' failed the first time, retrying..."
    pip3 install --upgrade -r mediacloud/requirements.txt
}
