#!/bin/sh
#
# Check if database schema has been changed, and if so, has the database schema version number been
# updated and the diff has been created.

SCHEMA_FILE="script/mediawords.sql"

if [ -d .svn ]; then
    #echo "This is a Subversion repository."
    ADDED_MODIFIED_FILES=`svn status -q | grep "^[M|A]" | awk '{ print $2}'`
    SCHEMA_DIFF=`svn diff $SCHEMA_FILE |  grep "^[+|-]"`

elif [ -d .git ]; then
    #echo "This is a Git repository."
    # FIXME the version of a file that is staged might be different from the file that exists in the filesystem
    ADDED_MODIFIED_FILES=`git diff --staged --name-status |  grep "^[M|A]" | awk '{ print $2}'`
    SCHEMA_DIFF=`git diff --staged $SCHEMA_FILE |  grep "^[+|-]"`

else
    echo "Unknown repository."
    exit 1
fi

# If the schema has been changed
if [ ! -z "$SCHEMA_DIFF" ]; then

    if [[ "$SCHEMA_DIFF" == *MEDIACLOUD_DATABASE_SCHEMA_VERSION* ]]; then

        # Database schema revisions
        OLD_DB_VERSION=`echo "$SCHEMA_DIFF"  \
            | perl -lne 'print if /\-.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT/'   \
            | perl -lpe 's/\-.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);/$1/'`
        NEW_DB_VERSION=`echo "$SCHEMA_DIFF"  \
            | perl -lne 'print if /\+.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT/'   \
            | perl -lpe 's/\+.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);/$1/'`
        if [ -z "$OLD_DB_VERSION" ]; then
            echo "Unable to determine old database schema version number."
            exit 1
        fi
        if [ -z "$NEW_DB_VERSION" ]; then
            echo "Unable to determine new database schema version number."
            exit 1
        fi

    else

        OLD_DB_VERSION=0
        NEW_DB_VERSION=0

    fi

    ERR=""

    # Check if version number has been changed
    if [ ! "$NEW_DB_VERSION" -gt "$OLD_DB_VERSION" ]; then
        ERR="${ERR}You have changed the database schema ($SCHEMA_FILE) but haven't increased the schema version "
        ERR="${ERR}number (MEDIACLOUD_DATABASE_SCHEMA_VERSION) at the top of that file. The old version and new "
        ERR="${ERR}version numbers currently are ${OLD_DB_VERSION} and ${NEW_DB_VERSION} respectively.\n"
    fi

    # Check if the SQL migration is being committed too
    SCHEMA_MIGR_FILE_EXISTS=""
    SCHEMA_MIGR_FILE="sql_migrations/mediawords-${OLD_DB_VERSION}-${NEW_DB_VERSION}.sql"
    for filepath in $ADDED_MODIFIED_FILES; do
        if [ "$filepath" == "$SCHEMA_MIGR_FILE" ]; then
            SCHEMA_MIGR_FILE_EXISTS="yes"
        fi
    done
    if [ -z "$SCHEMA_MIGR_FILE_EXISTS" ]; then
        ERR="${ERR}You have changed the database schema ($SCHEMA_FILE) but haven't added the schema migration "
        ERR="${ERR}file ($SCHEMA_MIGR_FILE) to this commit."
    fi

    # If there are errors
    if [ ! -z "$ERR" ]; then
        echo $ERR
        exit 1
    fi
        
fi

# Things are fine.
exit 0
