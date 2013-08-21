#!/bin/bash

set -u
set -o  errexit

# Fetch and update all local branches
git fetch --all
git pull --all
STARTING_BRANCH=$(git branch | grep '\*' | sed 's/^.//')
for i in $(git branch | sed 's/^.//'); do
	git checkout $i
	git pull || exit 1
done
git checkout $STARTING_BRANCH
