#!/bin/bash
#
# Test Media Cloud installation process by creating a new Ubuntu instance on
# Vagrant and running Media Cloud's ./install.sh and ./script/run_test_suite.sh
# on it.
#
# Script returns with zero exit status if the Media Cloud has been installed
# and tested successfully, non-zero exit status if the Media Cloud installation
# script or the test suite has failed.
#
# The script is path-independent (you can copy / symlink it to any location on
# the system).
#

# Lock file that will be created while the script is running in order to
# prevent other instances of the script running at the same time
LOCK_FILE="vagrant_test_suite.lock"

# Directory in which the script will check
# out Media Cloud's Git repository
TEMP_MC_REPO_DIR="temp-vagrant-mediacloud/"

# ---

set -e
set -u
set -o errexit


PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


if [ -f "$LOCK_FILE" ]; then
    echo "Lock file \"$LOCK_FILE\" exists."
    echo "Either Vagrant is running or it had failed last time."
    exit 1
fi

if [[ "$TEMP_MC_REPO_DIR" != /* ]]; then
    # Resolve relative path
    TEMP_MC_REPO_DIR="$PWD/$TEMP_MC_REPO_DIR"
    echo "Full path to the repository directory: $TEMP_MC_REPO_DIR"
fi

if [ -d "$TEMP_MC_REPO_DIR" ]; then
    echo "Temporary repository directory \"$TEMP_MC_REPO_DIR\" already exists."
    echo "Please remove it before proceeding."
    exit 1
fi

touch "$LOCK_FILE"

if [[ ! `vagrant box list | grep precise64` ]]; then
    echo "\"precise64\" missing in the list of Vagrant boxes, installing..."
    vagrant box add precise64 http://files.vagrantup.com/precise64.box
fi

echo "Cloning the Media Cloud repository..."
git clone http://github.com/berkmancenter/mediacloud.git "$TEMP_MC_REPO_DIR"
cd "$TEMP_MC_REPO_DIR/script/vagrant/"

echo "Setting up the virtual machine..."
VAGRANT_SUCCEEDED=1
vagrant up || { VAGRANT_SUCCEEDED=0; }

if [ $VAGRANT_SUCCEEDED == 0 ]; then
    echo
    echo "Media Cloud installation on Vagrant has failed."
    echo "I am shutting down the virtual machine for someone to look at."
    echo "To connect to the virtual machine:"
    echo
    echo "    cd `pwd`"
    echo "    vagrant up --no-provision"
    echo "    vagrant ssh"
    echo

    vagrant halt --force

    exit 1
fi

#
# Tests have been run at this point so things look okay; time for the teardown
#

echo "Destroying virtual machine..."
vagrant destroy --force

cd "$PWD"

echo "Removing the temporary Media Cloud repository..."
rm -rf "$TEMP_MC_REPO_DIR"

echo "Cleaning up \".vagrant\" directory..."
rm -rf .vagrant

echo "Removing lock file..."
rm "$LOCK_FILE"

echo "All done."
