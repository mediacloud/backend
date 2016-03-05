(DEVELOPER) CHANGING THE DATABASE SCHEMA
========================================

What follows is an imaginary tale of a Media Cloud developer who's trying to change the database schema and update the schema version appropriately.

1. Checkout the code from the repository:
-----------------------------------------

    svn co https://mediacloud.svn.sourceforge.net/svnroot/mediacloud/trunk mediacloud

1.1. I'm one of the Git fanboys so I use Git with a Subversion backend.

In this case, Git has a particular advantage -- it would automatically run pre-commit hooks for the developer (Subversion can only do that server-side, and Sourceforge doesn't support custom pre-commit hooks).

If you want to try Git out, install git-svn first (`sudo apt-get install git-core git-svn`) and then run:

    # Checkout original code -- takes a long time
    git svn clone -s https://mediacloud.svn.sourceforge.net/svnroot/mediacloud mediacloud
    cd mediacloud/

    # Export a list of ignored files from SVN to Git
    git svn show-ignore >> .git/info/exclude

    # Set up a symlink to the pre-commit hook that would run each and every time a commit by the
    # developer is attempted
    ./install_scripts/setup_git_precommit_hooks.sh

2. Make an arbitrary change to an irrelevant file and run the pre-commit hook:
------------------------------------------------------------------------------

    echo "Hello!" >> INSTALL
    ./script/pre_commit_hooks/pre-commit
    # after running the pre-commit script you would normally do "svn commit"

`pre-commit` doesn't output anything and returns with exit status 0 because there's nothing to do -- no Perl scripts are being committed, the schema haven't been changed.

2.1. If you're using Git, the pre-commit hook is being run automatically by Git so you don't have to run it manually.

    echo "Hello!" >> INSTALL

    # Add "INSTALL" to a list of "staged" files (files that are going to be committed)
    git add INSTALL

    # Do a commit to a local repository
    git commit

A text editor should appear at this point asking for a commit message because once again the pre-commit script ran fine and there's nothing wrong / incomplete with what's being committed. You can exit the editor without entering a commit message to abort a commit.

3. Make a change to the database schema and run the pre-commit hook:
--------------------------------------------------------------------

Open `script/mediawords.sql` and paste this at the end of the file without changing anything else:

    CREATE TABLE this_is_a_test (
        one VARCHAR(255) NOT NULL,
        two VARCHAR(255) NOT NULL,
        three VARCHAR(255) NOT NULL
    );

Then run the pre-commit hook again:

    ./script/pre_commit_hooks/pre-commit

The hook should now complain with a rather longish error message:

    You have changed the database schema (script/mediawords.sql) but haven't increased the schema
    version number (MEDIACLOUD_DATABASE_SCHEMA_VERSION constant) at the top of that file.

    Increase the following number in `script/mediawords.sql`:

        CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
        DECLARE

            <...>
            MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4379; <--------- This one.
            <...>
        END;
        $$
        LANGUAGE 'plpgsql';

    and then try committing again.

    Additionally, create a database schema diff SQL file if you haven't done so already. You have to
    generate a SQL schema diff between the current database schema and the schema that is being
    committed, and place it to `sql_migrations/mediawords-OLD_SCHEMA_VERSION-NEW_SCHEMA_VERSION.sql`.

    You can create a database schema diff automatically using the 'agpdiff' tool. Run:

        ./script/pre_commit_hooks/postgres-diff.sh > sql_migrations/mediawords-OLD_SCHEMA_VERSION-NEW_SCHEMA_VERSION.sql

    One of the pre-commit hooks failed. You have to make
    some additional fixes before your changes can be committed.
    If you're using Git (git-svn) and you are absolutely sure
    that your commit is fine as-is, repeat the commit with the
    --no-verify option.

Alternatively, run `script/generate_empty_sql_migration.sh` to generate an empty migration file in sql_migrations/ and
then manually edit the file to add the sql commands to update the database structure.

3.1. If you're using Git, the pre-commit hook is being run automatically by Git so you don't have to run it manually.

Make the change in the database schema (add the arbitrary table) as described above and then run:

    # Add the schema file to the list of committed files
    git add script/mediawords.sql

    # Try to do the commit
    git commit

The very same message as above should appear.

4. Increase the database schema version and run the pre-commit hook again:
--------------------------------------------------------------------------
  
The first part of this message tells the developer that he / she has changed the database schema (added a new table) but haven't changed the database schema number located at the top of the file. Let's do that -- open `script/mediawords.sql` and at the almost-top of the file (line 68 at the time of writing) increase the database schema version by one:

Was:

    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4391;

Should be:

    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4392;

After doing that, run the pre-commit hook again:

    ./script/pre_commit_hooks/pre-commit

The first part of the message is now gone but there's still one thing that has to be done.

4.1. If you're using Git, the pre-commit hook is being run automatically by Git so you don't have to run it manually.

Make the change in the database schema (increase the schema version by one) as described above and then run:

    # Add the schema file to the list of committed files
    git add script/mediawords.sql

    # Try to do the commit
    git commit

The very same message as above should appear.

5. Generate a SQL diff, add it to repository, and run the pre-commit hook again:
--------------------------------------------------------------------------------

Only one pre-commit hook's complaint is left to be addressed -- we have to create a SQL schema diff between two versions of the `mediawords.sql` file. We can do that by running:

    # Generate the diff
    # ("postgres-diff.sh" is a helper script that generates the "old" and "new" versions of mediawords.sql
    #  and then runs "apgdiff" Java tool to create a diff file)
    ./script/pre_commit_hooks/postgres-diff.sh > sql_migrations/mediawords-4391-4392.sql

    # Review the diff, make sure things are right
    # (apgdiff recreates function 'download_relative_file_path_trigger()' for some reason; I'm not sure why.)
    less sql_migrations/mediawords-4391-4392.sql

If the diff is fine, we have to add it to the repository:

    svn add sql_migrations/mediawords-4391-4392.sql

...and run the pre-commit hook again:

    ./script/pre_commit_hooks/pre-commit

The script is now silent again because it made sure that both the database schema version has been changed and that there is a way to incrementally upgrade the schema to the latest version using SQL diffs.

5.1. If you're using Git, the pre-commit hook is being run automatically by Git so you don't have to run it manually.

Create a SQL diff as described above and then run:

    # Add the SQL schema diff file to the list of committed files
    git add sql_migrations/mediawords-4391-4392.sql

    # Try to do the commit
    git commit

The hook should run just fine and an editor asking for a commit message should appear. Abort the commit by leaving the commit message empty.

----

(USER) UPGRADING THE DATABASE SCHEMA TO THE LATEST VERSION
==========================================================

If you happen to be a user who just have checked out the latest Media Cloud code and want to upgrade the database to the latest version, run:

    ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl

The script will:

1. Find out the source database schema version (the one that's currently running in the database software),
2. Find out the target database schema version (the one from the current `script/mediawords.sql`), and, if the upgrade is needed,
3. Run the required SQL diff files from the `sql_migrations/` directory one-by-one to incrementally upgrade to the latest database schema version.
