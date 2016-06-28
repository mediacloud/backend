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
# Usage:
# 
#     ./run_install_test_suite_on_vagrant.sh virtualbox
# or:
#     AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" \
#     AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG" \
#     AWS_KEYPAIR_NAME="development" \
#     AWS_SSH_PRIVKEY="~/development.pem" \
#     AWS_SECURITY_GROUP="default" \
#     ./run_install_test_suite_on_vagrant.sh aws
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

USAGE=$( cat <<EOF
Usage:
    ./run_install_test_suite_on_vagrant.sh virtualbox
or:
    AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" \\ 
    AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG" \\ 
    AWS_KEYPAIR_NAME="development" \\ 
    AWS_SSH_PRIVKEY="~/development.pem" \\ 
    AWS_SECURITY_GROUP="default" \\ 
    ./run_install_test_suite_on_vagrant.sh aws
EOF
)

if [ $# -ne 1 ]; then
    echo "$USAGE"
    exit 1
fi

PROVIDER="$1"
if [ "$PROVIDER" != "virtualbox" ] && [ "$PROVIDER" != "aws" ]; then
    echo "$USAGE"
    exit 1
fi


PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCK_FILE="$PWD/$LOCK_FILE"


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

if [ "$PROVIDER" == "virtualbox" ]; then
    if [[ ! `vagrant box list | grep xenial64` ]]; then
        echo "\"ubuntu/xenial64\" missing in the list of Vagrant boxes, installing..."
        vagrant box add ubuntu/xenial64
    fi
fi

echo "Cloning the Media Cloud repository..."
git clone http://github.com/berkmancenter/mediacloud.git "$TEMP_MC_REPO_DIR"
cd "$TEMP_MC_REPO_DIR/script/vagrant/"

echo "Setting up the virtual machine..."
VAGRANT_SUCCEEDED=1
vagrant up --provider="$PROVIDER" || { VAGRANT_SUCCEEDED=0; }

# Teardown

echo "Destroying virtual machine..."
vagrant destroy --force

# Back from ./$TEMP_MC_REPO_DIR/script/vagrant/
cd "../../../"

echo "Removing the temporary Media Cloud repository..."
rm -rf "$TEMP_MC_REPO_DIR"

echo "Cleaning up \".vagrant\" directory..."
rm -rf .vagrant

echo "Removing lock file..."
rm "$LOCK_FILE"

if [ $VAGRANT_SUCCEEDED == 0 ]; then
    echo "Vagrant deployment has failed."
    exit 1
else
    echo "Things look fine."
    exit 0
fi
