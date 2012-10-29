#!/bin/sh
#
# Check if Perl source files that are being committed are formatted properly.
#
# Usage:
# 1) Do some changes in Media Cloud's code under version control (SVN or Git) adding / changing Perl files or modules.
# 2) Run ./script/pre_commit_hooks/hook-perl-formatting.sh before committing.
# 3) The script will exit with a non-zero exit status if there are some additional modifications that you have
#    to do before committing.

if [ -d .svn ]; then
    #echo "This is a Subversion repository."
    ADDED_MODIFIED_FILES=`svn status -q | grep "^[M|A]" | awk '{ print $2}'`

elif [ -d .git ]; then
    #echo "This is a Git repository."
    # FIXME the version of a file that is staged might be different from the file that exists in the filesystem
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

    if [[ "$extension" == "pl" || "$extension" == "pm" ]]; then
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
    echo "$FILES_THAT_HAVE_TO_BE_TIDIED"
    echo
    echo "You can tidy the files listed above by running:"
    echo
    for filename in "${FILES_THAT_HAVE_TO_BE_TIDIED[@]}"; do
        echo "./script/run_with_carton.sh ./script/mediawords_reformat_code.pl $filename"
    done
    echo
    echo "Also, you can run:"
    echo
    echo "./script/run_with_carton.sh ./script/mediawords_reformat_all_code.pl"
    echo
    echo "to reformat all Perl files that are placed in this repository."
    exit 1
fi

# Things are fine.
exit 0
