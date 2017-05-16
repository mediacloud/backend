#!/bin/bash

#
# Install mecab-ipadic-neologd for Japanese language support
#

set -e
set -u

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

if [ `uname` == 'Darwin' ]; then
    # greadlink from coreutils
    READLINK="greadlink"
else
    READLINK="readlink"
fi

MECAB_IPADIC_NEOLOGD_DIST_PATH="lib/MediaWords/Languages/resources/ja/mecab-ipadic-neologd-dist/"
MECAB_IPADIC_NEOLOGD_TARGET_PATH="lib/MediaWords/Languages/resources/ja/mecab-ipadic-neologd/"

# Set by Mecab install script itself, we just replicate it here
MECAB_IPADIC_NEOLOGD_BUILD_DIR="$MECAB_IPADIC_NEOLOGD_DIST_PATH/build/"

MECAB_IPADIC_NEOLOGD_DIST_PATH=`$READLINK -m $MECAB_IPADIC_NEOLOGD_DIST_PATH`
MECAB_IPADIC_NEOLOGD_TARGET_PATH=`$READLINK -m $MECAB_IPADIC_NEOLOGD_TARGET_PATH`

if [ ! -d "$MECAB_IPADIC_NEOLOGD_DIST_PATH/seed/" ]; then
    echo "Path does not look like it contains mecab-ipadic-neologd: $MECAB_IPADIC_NEOLOGD_DIST_PATH"
    echo "Maybe you forgot to pull Git submodule?"
    exit 1
fi

if [ ! -d "$MECAB_IPADIC_NEOLOGD_TARGET_PATH" ]; then
    echo "Target directory does not exist: $MECAB_IPADIC_NEOLOGD_TARGET_PATH"
    exit 1
fi

if [ -d "$MECAB_IPADIC_NEOLOGD_BUILD_DIR" ]; then
    echo "Cleaning up build directory from the old build..."
    rm -rf "$MECAB_IPADIC_NEOLOGD_BUILD_DIR"
fi

echo "Installing mecab-ipadic-neologd..."
cd "$MECAB_IPADIC_NEOLOGD_DIST_PATH/bin/"
./install-mecab-ipadic-neologd \
    --prefix "$MECAB_IPADIC_NEOLOGD_TARGET_PATH" \
    --forceyes

if [ ! -f "$MECAB_IPADIC_NEOLOGD_TARGET_PATH/sys.dic" ]; then
    echo "mecab-ipadic-neologd doesn't seem to be installed into $MECAB_IPADIC_NEOLOGD_TARGET_PATH."
    exit 1
fi

echo "Cleaning up build directory..."
rm -rf "$MECAB_IPADIC_NEOLOGD_BUILD_DIR"

echo
echo "mecab-ipadic-neologd is now installed into $MECAB_IPADIC_NEOLOGD_TARGET_PATH."
echo
echo "Run mecab as:"
echo
echo "    mecab --dicdir=$MECAB_IPADIC_NEOLOGD_TARGET_PATH"
echo
