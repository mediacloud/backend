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

# TODO: test python 3.6
PYTHON3_MAJOR_VERSION="3.5"

if [ `uname` == 'Darwin' ]; then
    COMMAND_PREFIX=""
else
    COMMAND_PREFIX="sudo"
fi

echo "Installing (upgrading) Pip..."
if [ `uname` == 'Darwin' ]; then
    # doesn't need get-pip as python always comes with pip installed on Mac OS X
    # should theoretically be pre-installed on all platforms from Python 2.7+
    pip2.7 install --upgrade pip
    pip$PYTHON3_MAJOR_VERSION install --upgrade pip
else
    # assume Ubuntu
    wget https://bootstrap.pypa.io/get-pip.py -O - | $COMMAND_PREFIX python2.7 -
    $COMMAND_PREFIX rm setuptools-*.zip || echo "No setuptools to cleanup"
    wget https://bootstrap.pypa.io/get-pip.py -O - | $COMMAND_PREFIX python$PYTHON3_MAJOR_VERSION -
    $COMMAND_PREFIX rm setuptools-*.zip || echo "No setuptools to cleanup"
fi

echo "Installing (upgrading) Supervisor..."
# * change dir, otherwise the installer might think we're trying to install from the supervisor/ directory
# * also, Supervisor only supports Python 2.7 at the moment
( cd /tmp; $COMMAND_PREFIX pip2.7 install --upgrade supervisor )

echo "Installing (upgrading) Virtualenv..."
$COMMAND_PREFIX pip2.7 install --force-reinstall --upgrade virtualenv
$COMMAND_PREFIX pip$PYTHON3_MAJOR_VERSION install --force-reinstall --upgrade virtualenv


# Installing WordNet of NLTK with wget
echo "Installing NLTK WordNet data..."
echo "  Set NLTK data path"
if [ `uname` == 'Darwin' ]; then
    NLTK_DATA_PATH=/usr/local/share/nltk_data
else
    NLTK_DATA_PATH=/usr/share/nltk_data
fi
echo "  Download data with wget, this may take a while"
wget -nv https://github.com/nltk/nltk_data/archive/gh-pages.zip
echo "  Unzip data with unzio, this may take a while"
unzip gh-pages.zip
echo "  Move data to ideal directory"
mv nltk_data-gh-pages/ $NLTK_DATA_PATH


echo "Creating mc-venv virtualenv..."
echo "$(which python$PYTHON3_MAJOR_VERSION)"
echo "$(which virtualenv)"
virtualenv --python=python$PYTHON3_MAJOR_VERSION mc-venv
source mc-venv/bin/activate

echo "Adding 'mediacloud/' to module search path..."
SITE_PACKAGES_PATH="./mc-venv/lib/python$PYTHON3_MAJOR_VERSION/site-packages/"
if [ ! -d "$SITE_PACKAGES_PATH" ]; then
    echo "'site-packages' at $SITE_PACKAGES_PATH does not exist."
    exit 1
fi
cat > "$SITE_PACKAGES_PATH/mediacloud.pth" << EOF
#
# Include "mediacloud/" in sys.path to scripts under "tools/"
#
../../../../mediacloud/
EOF

echo "Installing Python $PYTHON3_MAJOR_VERSION dependencies..."
pip$PYTHON3_MAJOR_VERSION install --upgrade -r mediacloud/requirements.txt || {
    # Sometimes fails with some sort of Setuptools error
    echo "'pip$PYTHON3_MAJOR_VERSION install' failed the first time, retrying..."
    pip$PYTHON3_MAJOR_VERSION install --upgrade -r mediacloud/requirements.txt
}



