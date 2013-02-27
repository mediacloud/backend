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

MC=`pwd`

ARCHIVE_TO_RESTORE="$1"
ARCHIVE_FILENAME=`basename "$ARCHIVE_TO_RESTORE"`
ARCHIVE_DIRECTORY=`cd $(dirname $ARCHIVE_TO_RESTORE); pwd`
ARCHIVE_TO_RESTORE="$ARCHIVE_DIRECTORY/$ARCHIVE_FILENAME"
BUILD_DIR=`mktemp -d -t buildXXXXX`

echo "Input: $ARCHIVE_TO_RESTORE"
echo "Temp. directory: $BUILD_DIR"
echo "MC: $MC"

echo "Removing existing data..."
rm -rf ./data/content/*
if [ -f mediawords.yml ]; then
	rm mediawords.yml
fi

# Include PostgreSQL path helpers
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/postgresql_path_helpers.inc.sh"

# Drop databases
echo "DROPPING db mediacloud"
run_dropdb mediacloud
echo "DROPPING db mediacloud_test"
run_dropdb mediacloud_test

# Remove user
run_psql "DROP USER IF EXISTS mediaclouduser "

echo "Recreating database..."
source "$PWD/create_default_db_user_and_databases.sh"

echo "Extracting..."
cd "$BUILD_DIR" && tar -jxvf "$ARCHIVE_TO_RESTORE" && cd "$MC"

echo "Moving configuration and data to places..."
cd "$MC"
mv "$BUILD_DIR/content/"* ./data/content/
mv "$BUILD_DIR/mediawords.yml" ./mediawords.yml

echo "Importing PostgreSQL dump..."
chmod 777 "$BUILD_DIR"
chmod 666 "$BUILD_DIR/mediacloud.sql"
run_psql_import "$BUILD_DIR/mediacloud.sql" mediacloud

echo "Cleaning up..."
rm -rf "$BUILD_DIR/"

echo "Done."
