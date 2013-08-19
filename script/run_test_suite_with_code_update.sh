#!/bin/bash

set -u
set -o  errexit

cd `dirname $0`/../
source ./script/update_code_from_git.sh
./script/run_test_suite.sh

