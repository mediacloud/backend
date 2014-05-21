#!/bin/bash
#
# Check if Perl source files that are being committed are formatted properly and have a correct syntax.
#
# Usage:
# 1) Do some changes in Media Cloud's code under version control (SVN or Git) adding / changing Perl files or modules.
# 2) Run ./script/pre_commit_hooks/hook-perl-syntax-formatting.sh before committing.
# 3) The script will exit with a non-zero exit status if there are some additional modifications that you have
#    to do before committing.

if [ -d .git ]; then
    #echo "This is a Git repository."
    # FIXME the version of a file that is staged might be different from the file that exists in the filesystem
    REPOSITORY="git"
    ADDED_MODIFIED_FILES=`git diff --staged --name-status |  grep "^[M|A]" | awk '{ print $2}'`

else
    echo "Unknown repository."
    exit 1
fi

# Will create a list of files that have to be tidied here
FILES_THAT_HAVE_TO_BE_TIDIED=()

for filepath in $ADDED_MODIFIED_FILES; do
    filename=$(basename "$filepath")
    extension=`echo "${filename##*.}" | tr '[A-Z]' '[a-z]'`

    # skip perl test data b/c it takes a long time to process and doesn't need pretty formatting
    if echo "$filepath" | grep -q 't/data'; then
        continue;
    fi

    if [[ "$extension" == "pl" || "$extension" == "pm" || "$extension" == "t" ]]; then
        #echo "File '$filepath' is Perl source."

        # Copy file to the temp. location, tidy it and see if it differs from what we're trying to commit
        TEMPDIR=`mktemp -d -t perltidyXXXXX`
        target_filepath="$TEMPDIR/$filename"
        cp "$filepath" "$target_filepath"
        ./script/run_with_carton.sh ./script/mediawords_reformat_code.pl "$target_filepath"
        if [ $? -ne 0 ]; then
            echo "Error while trying to Perl tidy '$target_filepath'."
            exit 1
        fi

        DIFF=`diff -uN "$filepath" "$target_filepath" | wc -l`
        if [ "$DIFF" -ne 0 ]; then
            #echo "File differs."
            FILES_THAT_HAVE_TO_BE_TIDIED=( "${FILES_THAT_HAVE_TO_BE_TIDIED[@]}" "$filepath" )
        fi

        rm -rf "$TEMPDIR"

    fi

done

# Are there files that have to be tidied?
if [ ${#FILES_THAT_HAVE_TO_BE_TIDIED[@]} -gt 0 ]; then
    echo "Some Perl files have to be reformatted (tidied) before they can be committed to the repository:"
    echo
    for filename in "${FILES_THAT_HAVE_TO_BE_TIDIED[@]}"; do
        echo "$filename"
    done
    echo
    echo "You can tidy the files listed above by running:"
    echo
    for filename in "${FILES_THAT_HAVE_TO_BE_TIDIED[@]}"; do
        echo "./script/run_with_carton.sh ./script/mediawords_reformat_code.pl $filename"
        if [ "$REPOSITORY" == "git" ]; then
            echo "git add $filename"
        fi
        echo
    done
    echo "Alternatively, you can run:"
    echo
    echo "./script/mediawords_reformat_all_code.sh"
    if [ "$REPOSITORY" == "git" ]; then
        echo "git add -A"
    fi
    echo
    echo "to reformat all Perl files that are placed in this repository."
    exit 1
fi

# Things are fine.
exit 0
