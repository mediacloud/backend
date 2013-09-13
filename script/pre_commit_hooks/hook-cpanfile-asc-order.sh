#!/bin/bash
#
# Check if the list of Perl module dependencies in "cpanfile" have been changed, and if so, are they in the ascending alphabetical order.
#
# Usage:
# 1) Do some changes in Media Cloud's code under version control (SVN or Git) involving "cpanfile".
# 2) Run ./script/pre_commit_hooks/hook-cpanfile-asc-order.sh before committing.
# 3) The script will exit with a non-zero exit status if there are some additional modifications that you have
#    to do before committing.

CPANFILE="cpanfile"

if [ -d .git ]; then
    #echo "This is a Git repository."
    # FIXME the version of a file that is staged might be different from the file that exists in the filesystem
    REPOSITORY="git"
    CPANFILE_DIFF=`git diff --staged $CPANFILE`

else
    echo "Unknown repository."
    exit 1
fi

# If "cpanfile" has been changed
if [ ! -z "$CPANFILE_DIFF" ]; then

    # Check for tabs
    if grep -q $'\t' "${CPANFILE}"; then
        echo "Perl module dependency list '${CPANFILE}' contains tabs."
        echo "Please use spaces instead of tabs."
        exit 1
    fi

    # Copy file to the temp. location, sort it and see if it differs from what we're trying to commit
    TEMPDIR=`mktemp -d -t cpanfileXXXXX`
    orig_path="${TEMPDIR}/cpanfile.orig"
    sorted_path="${TEMPDIR}/cpanfile.should_be"

    grep -v "^#" "${CPANFILE}" > "${orig_path}"     # don't attempt to sort comments
    cat "${orig_path}" | LC_ALL=C sort -f | uniq > "${sorted_path}"

    SORTED_DIFF=`diff -uN ${orig_path} ${sorted_path}`
    if [ ! -z "$SORTED_DIFF" ]; then
        echo "Perl module dependency list '${CPANFILE}' is not sorted in an alphabetical order,"
        echo "and / or contains duplicates."
        echo
        echo "Keeping the list in alphabetical, non-case sensitive order without duplicates helps"
        echo "merging branches back into the trunk."
        echo
        echo "Please sort the dependency list in a non-case sensitive alphabetical order:"
        echo
        echo "    cat ${CPANFILE} | LC_ALL=C sort -f | uniq > ${CPANFILE}.sorted"
        echo "    mv ${CPANFILE}.sorted ${CPANFILE}"
        if [ "$REPOSITORY" == "git" ]; then
            echo "    git add ${CPANFILE}"
        fi
        echo
        echo "The diff between unsorted and sorted versions of '${CPANFILE}' follows:"
        echo
        echo "$SORTED_DIFF"
        exit 1
    fi

fi

# Things are fine.
exit 0
