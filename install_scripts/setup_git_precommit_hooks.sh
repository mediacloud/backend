#!/bin/bash
#
# Set up Git pre-commit hooks helpful for developing Media Cloud
#

set -u
set -o errexit

if [ `uname` == 'Darwin' ]; then
    # greadlink from coreutils
    READLINK="greadlink"
else
    READLINK="readlink"
fi

HOOK_SOURCE="script/pre_commit_hooks/pre-commit"
HOOK_TARGET=".git/hooks/pre-commit"

# ---

if [ ! -d .git ]; then
    echo ".git directory doesn't exist in the current path."
    echo "Either you didn't checkout Media Cloud from the GitHub repository, or you're not in the Media Cloud root path."
    exit 1
fi

if [ ! -f "$HOOK_SOURCE" ]; then
    echo "Target pre-commit hook doesn't exist in its expected location at $HOOK_SOURCE."
    echo "This script must be broken then."
    exit 1
fi

if [ ! -x "$HOOK_SOURCE" ]; then
    echo "Source pre-commit hook is not executable, chmodding +x $HOOK_SOURCE..."
    chmod +x "$HOOK_SOURCE"

    if [ ! -x "$HOOK_SOURCE" ]; then
        echo "I've tried to make a source pre-commit hook at $HOOK_SOURCE executable, but failed."
        exit 1
    fi
fi

if [ -f "$HOOK_TARGET" ]; then

    if [ -L "$HOOK_TARGET" ]; then

        pre_commit_hook_expected_target=`$READLINK -m $HOOK_SOURCE`
        pre_commit_hook_actual_target=`$READLINK -m $HOOK_TARGET`

        if [ "$pre_commit_hook_expected_target" == "$pre_commit_hook_actual_target" ]; then

            echo "Correct pre-commit hook already exists in an expected location."
            echo "Nothing to do."
            exit 0

        else

            echo "Current pre-commit hook is a symlink, but it points to an incorrect target."
            echo "Expected location: $pre_commit_hook_expected_target"
            echo "Actual location: $pre_commit_hook_actual_target"
            echo "I won't delete it; go and fix it manually."
            exit 1

        fi

    else

        echo "Some sort of a non-Media Cloud commit hook already exists in $HOOK_TARGET."
        echo "I won't delete it; go and fix it manually."
        exit 1

    fi
fi

echo "Linking $HOOK_SOURCE to $HOOK_TARGET..."
cd $(dirname $HOOK_TARGET)
ln -s "../../$HOOK_SOURCE" $(basename $HOOK_TARGET)
chmod +x $(basename $HOOK_TARGET)
cd ../../

if [ ! -x "$HOOK_TARGET" ]; then
    echo "Target pre-commit hook is not executable, something went wrong."
    exit 1
fi

if [ ! -L "$HOOK_TARGET" ]; then
    echo "Target pre-commit hook is not a symlink, something went wrong."
    exit 1
fi

pre_commit_hook_expected_target=`$READLINK -m $HOOK_SOURCE`
pre_commit_hook_actual_target=`$READLINK -m $HOOK_TARGET`

if [ ! "$pre_commit_hook_expected_target" == "$pre_commit_hook_actual_target" ]; then

    echo "Created pre-commit hook is a symlink, but it points to an incorrect target."
    echo "Expected location: $pre_commit_hook_expected_target"
    echo "Actual location: $pre_commit_hook_actual_target"
    echo "Something went wrong."
    exit 1

fi

echo "Done."
