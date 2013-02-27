#!/bin/bash

# Exit on error
set -u
set -o errexit
set -e

if [ ! $# -eq 1 ]; then
	echo "Usage: $0 path_to_archive.tar.bz2"
	exit 1
fi

if [ ! -f mediawords.yml.dist ]; then
	echo "You're not in Media Words root folder."
	exit 1
fi

ARCHIVE_TO_CREATE="$1"
ARCHIVE_FILENAME=`basename "$ARCHIVE_TO_CREATE"`
ARCHIVE_DIRECTORY=`cd $(dirname $ARCHIVE_TO_CREATE); pwd`
BUILD_DIR=`mktemp -d -t buildXXXXX`
BUILD_DIR_2=`mktemp -d -t buildXXXXX`

echo "Output: $ARCHIVE_TO_CREATE (directory: $ARCHIVE_DIRECTORY; filename: $ARCHIVE_FILENAME)"
echo "Temp. directory: $BUILD_DIR"

echo "Exporting database..."
pg_dump mediacloud > "$BUILD_DIR/mediacloud.sql"

echo "Copying mediawords.yml..."
cp mediawords.yml "$BUILD_DIR/mediawords.yml"

echo "Copying content..."
cp -R ./data/content "$BUILD_DIR/content"

echo "Archiving..."
PWD=`pwd`
cd "$BUILD_DIR" && tar -cvf "$BUILD_DIR_2/mc-backup.tar" * && cd "$PWD"

echo "Compressing..."
bzip2 -v9 "$BUILD_DIR_2/mc-backup.tar"

echo "Moving to destination..."
mv "$BUILD_DIR_2/mc-backup.tar.bz2" "$ARCHIVE_TO_CREATE"

echo "Cleaning up..."
rm -rf "$BUILD_DIR"
rm -rf "$BUILD_DIR_2"

echo "Done."
