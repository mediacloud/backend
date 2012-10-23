#!/bin/sh
#
# Create a PostgreSQL diff between two SQL dumps before a SVN / Git commit.

PATH_TO_AGPDIFF="./script/pre_commit_hooks/apgdiff-2.4.jar"
SCHEMA_FILE="script/mediawords.sql"


# Exit on error
set -u
set -o errexit

# Version control
if [ -d .svn ]; then
    #echo "This is a Subversion repository."
    SCHEMA_DIFF=`svn diff ${SCHEMA_FILE}`

elif [ -d .git ]; then
    #echo "This is a Git repository."
    # FIXME the version of a file that is staged might be different from the file that exists in the filesystem
    SCHEMA_DIFF=`git diff --staged ${SCHEMA_FILE}`

else
    echo "Unknown repository."
    exit 1
fi

# Figure out the old / new revisions
OLD_SCHEMA_VERSION=`echo "$SCHEMA_DIFF"  \
    | perl -lne 'print if /\-.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT/'   \
    | perl -lpe 's/\-.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);/$1/'`
NEW_SCHEMA_VERSION=`echo "$SCHEMA_DIFF"  \
    | perl -lne 'print if /\+.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT/'   \
    | perl -lpe 's/\+.+?MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);/$1/'`
if [ -z "$OLD_SCHEMA_VERSION" ]; then
    echo "Unable to determine old database schema version number from the version control diff."
    exit 1
fi
if [ -z "$NEW_SCHEMA_VERSION" ]; then
    echo "Unable to determine new database schema version number from the version control diff."
    exit 1
fi

# Create the temporary directory to hold two files
TEMP_DIR=`mktemp -d -t diffXXXXX`

# Copy the SQL schema and the diff
cp "$SCHEMA_FILE" "$TEMP_DIR/mediawords-old.sql"
cp "$SCHEMA_FILE" "$TEMP_DIR/mediawords-new.sql"
echo "$SCHEMA_DIFF" > "$TEMP_DIR/mediawords.diff"

# Apply diff in reverse
patch --quiet --reverse "$TEMP_DIR/mediawords-old.sql" "$TEMP_DIR/mediawords.diff"

# Run PostgreSQL diff
POSTGRES_DIFF=`java -jar ${PATH_TO_AGPDIFF} --add-transaction \
	"$TEMP_DIR/mediawords-old.sql" "$TEMP_DIR/mediawords-new.sql"`

# Check for DROPs
if [[ ! "$POSTGRES_DIFF" == "*DROP TABLE*" ]]; then
	# to STDERR
	echo "PostgreSQL diff contains DROP TABLE clauses. Make sure to revise the diff before committing!" 1>&2
fi

# Print everything out
echo "--"
echo "-- This is a Media Cloud PostgreSQL schema difference file (a \"diff\") between schema"
echo "-- versions ${OLD_SCHEMA_VERSION} and ${NEW_SCHEMA_VERSION}."
echo "--"
echo "-- If you are running Media Cloud with a database that was set up with a schema version"
echo "-- ${OLD_SCHEMA_VERSION}, and you would like to upgrade both the Media Cloud and the"
echo "-- database to be at version ${NEW_SCHEMA_VERSION}, import this SQL file:"
echo "--"
echo "--     psql mediacloud < mediawords-${OLD_SCHEMA_VERSION}-${NEW_SCHEMA_VERSION}.sql"
echo "--"
echo "-- You might need to import some additional schema diff files to reach the desired version."
echo "--"
echo
echo "--"
echo "-- 1 of 2. Import the output of 'apgdiff' with a single transaction:"
echo "--"
echo "$POSTGRES_DIFF"
echo
echo "--"
echo "-- 2 of 2. Reset the database version."
echo "--"
echo "SELECT set_database_schema_version();"
echo
