#!/bin/bash
#
# Check if database schema has been changed, and if so, has the database schema version number been
# updated and the diff has been created.
#
# Usage:
# 1) Do some changes in Media Cloud's code under version control (SVN or Git) involving script/mediawords.sql.
# 2) Run ./script/pre_commit_hooks/hook-db-schema-version.sh before committing.
# 3) The script will exit with a non-zero exit status if there are some additional modifications that you have
#    to do before committing.

SCHEMA_FILE="script/mediawords.sql"

if [ -d .git ]; then
    #echo "This is a Git repository."
    # FIXME the version of a file that is staged might be different from the file that exists in the filesystem
    REPOSITORY="git"
    ADDED_MODIFIED_FILES=`git diff --staged --name-status |  grep "^[M|A]" | awk '{ print $2}'`
    SCHEMA_DIFF=`git diff --staged $SCHEMA_FILE`

else
    echo "Unknown repository."
    exit 1
fi


# Prints out instructions to increase schema's version number
helpIncreaseSchemaVersion()
{
    OLD_SCHEMA_VERSION="$1"
    NEW_SCHEMA_VERSION="$2"

    echo "You have changed the database schema (${SCHEMA_FILE}) but haven't increased the schema version "
    echo "number (MEDIACLOUD_DATABASE_SCHEMA_VERSION constant) at the top of that file."
    echo

    if [[ ! -z "$OLD_SCHEMA_VERSION" || ! -z "$NEW_SCHEMA_VERSION" ]]; then
        echo "The old version and new version numbers currently are ${OLD_SCHEMA_VERSION} and "
        echo "${NEW_SCHEMA_VERSION} respectively."
        echo
    fi

    echo "Increase the following number in ${SCHEMA_FILE}:"
    echo
    echo "    CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS \$\$"
    echo "    DECLARE"
    echo "    "
    echo "        <...>"
    echo "        MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4379; <--------- This one."
    echo "        <...>"
    echo "    END;"
    echo "    \$\$"
    echo "    LANGUAGE 'plpgsql';"
    echo
    echo "and then try committing again."
    echo
}


# Prints out instructions to make a schema diff
helpSchemaDiff()
{
    OLD_SCHEMA_VERSION="$1"
    NEW_SCHEMA_VERSION="$2"

    if [ -z "$OLD_SCHEMA_VERSION" ]; then
        OLD_SCHEMA_VERSION="OLD_SCHEMA_VERSION"
    fi
    if [ -z "$NEW_SCHEMA_VERSION" ]; then
        NEW_SCHEMA_VERSION="NEW_SCHEMA_VERSION"
    fi

    # Destination file
    SCHEMA_MIGRATION_FILE="sql_migrations/mediawords-${OLD_SCHEMA_VERSION}-${NEW_SCHEMA_VERSION}.sql"

    echo "You have to generate a SQL schema diff between the current database schema and the schema "
    echo "that is being committed, and place it to ${SCHEMA_MIGRATION_FILE}."
    echo
    echo "You can create a database schema diff automatically using the 'agpdiff' tool. Run:"
    echo
    echo "    ./script/pre_commit_hooks/postgres-diff.sh > ${SCHEMA_MIGRATION_FILE}"
    echo
    echo "You should then add this file to the repository in the same commit as the schema file:"
    echo
    if [ "$REPOSITORY" == "git" ]; then
        echo "    git add ${SCHEMA_MIGRATION_FILE}"
    elif [ "$REPOSITORY" == "svn" ]; then
        echo "    svn add ${SCHEMA_MIGRATION_FILE}"
    else
        echo "Unknown repository."
        exit 1
    fi
}


# If the schema has been changed
if [ ! -z "$SCHEMA_DIFF" ]; then

    # Check if there are any changes in the diff that look like the database schema version
    if [[ ! "$SCHEMA_DIFF" == *MEDIACLOUD_DATABASE_SCHEMA_VERSION* ]]; then

        helpIncreaseSchemaVersion "" ""
        echo "---------"
        echo
        echo "Additionaly, create a database schema diff SQL file if you haven't done so already."
        helpSchemaDiff "" ""

        exit 1
    fi

    # Database schema versions
    OLD_SCHEMA_VERSION=`echo "$SCHEMA_DIFF"  \
        | grep "^-" \
        | ./script/run_with_carton.sh ./script/database_schema_version.pl -`
    NEW_SCHEMA_VERSION=`echo "$SCHEMA_DIFF"  \
        | grep "^+" \
        | ./script/run_with_carton.sh ./script/database_schema_version.pl -`
    if [ -z "$OLD_SCHEMA_VERSION" ]; then
        echo "Unable to determine old database schema version number from the version control diff."
        exit 1
    fi
    if [ -z "$NEW_SCHEMA_VERSION" ]; then
        echo "Unable to determine new database schema version number from the version control diff."
        exit 1
    fi

    # Check if version number has been changed
    if [ ! "$NEW_SCHEMA_VERSION" -gt "$OLD_SCHEMA_VERSION" ]; then
        helpIncreaseSchemaVersion "$OLD_SCHEMA_VERSION" "$NEW_SCHEMA_VERSION"
        echo "Also, don't forget to create a database schema diff SQL file if you haven't done so already."
        helpSchemaDiff "$OLD_SCHEMA_VERSION" "$NEW_SCHEMA_VERSION"

        exit 1
    fi

    # Check if the SQL migration is being committed too
    SCHEMA_MIGRATION_FILE="sql_migrations/mediawords-${OLD_SCHEMA_VERSION}-${NEW_SCHEMA_VERSION}.sql"
    SCHEMA_MIGRATION_FILE_COMMITTED=""  # non-empty for true
    for filepath in $ADDED_MODIFIED_FILES; do
        if [ "$filepath" == "$SCHEMA_MIGRATION_FILE" ]; then
            SCHEMA_MIGRATION_FILE_COMMITTED="yes"
        fi
    done

    SCHEMA_MIGRATION_FILE_EXISTS=""
    if [ -e $SCHEMA_MIGRATION_FILE ]; then
        #echo " $SCHEMA_MIGRATION_FILE exists"
    SCHEMA_MIGRATION_FILE_EXISTS="true";
        #echo "File exists: $SCHEMA_MIGRA_FILE_EXISTS"
    else
        #echo "$SCHEMA_MIGRATION_FILE does not exist."
    :
    fi

    if [ -z "$SCHEMA_MIGRATION_FILE_COMMITTED" ]; then
        if [ -z "$SCHEMA_MIGRATION_FILE_EXISTS" ]; then
                echo "You have changed the database schema (${SCHEMA_FILE})."
                echo "However, you haven't created and added the database schema diff file to this commit."
                echo
                helpSchemaDiff "$OLD_SCHEMA_VERSION" "$NEW_SCHEMA_VERSION"
                exit 1
            else
           
                echo "You have changed the database schema (${SCHEMA_FILE}) and created a database schema "
                echo "diff file (${SCHEMA_MIGRATION_FILE})."
                echo "However, you haven't added the schema diff file to this commit."
                echo
                helpSchemaDiff "$OLD_SCHEMA_VERSION" "$NEW_SCHEMA_VERSION"
                exit 1
        fi
    fi
    
fi

# Things are fine.
exit 0
