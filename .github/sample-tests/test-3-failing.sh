#!/bin/bash

set -u
set -e

echo "Test 3 (failing) line 1"
echo "Test 3 (failing) line 2"
echo "Test 3 (failing) line 3"

sleep 1

exit 1
