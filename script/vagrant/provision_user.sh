#!/bin/bash
#
# Provisioning script for the *unprivileged* user (vagrant).
#
# Tested on Ubuntu (64 bit)
#

# Path to where Media Cloud's repository is mounted on Vagrant
MEDIACLOUD_ROOT=/mediacloud


# Exit on error
set -e
set -u
set -o errexit

echo "Installing Media Cloud..."
cd $MEDIACLOUD_ROOT
MEDIAWORDS_CREATE_DB_DO_NOT_CONFIRM=1 ./install.sh

echo "Running full test suite..."
./script/run_test_suite.sh

echo "Done."
