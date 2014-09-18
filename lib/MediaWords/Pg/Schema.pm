package MediaWords::Pg::Schema;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;
use MediaWords::Util::SchemaVersion;

# import functions into server schema

use strict;
use warnings;

use IPC::Run3;
use Carp qw/ confess /;
use FindBin;

# get is_stop_stem() stopword + stopword stem tables and a pl/pgsql function definition
sub get_is_stop_stem_function_tables_and_definition
{
    my $sql = '';

    my @stoplist_sizes = ( 'tiny', 'short', 'long' );

    for my $stoplist_size ( @stoplist_sizes )
    {

        # create tables
        $sql .= <<END

            -- PostgreSQL sends notices about implicit keys that are being created,
            -- and the test suite takes them for warnings.
            SET client_min_messages=WARNING;

            -- "Full" stopwords
            DROP TABLE IF EXISTS stopwords_${stoplist_size};
            CREATE TABLE stopwords_${stoplist_size} (
                stopwords_${stoplist_size}_id SERIAL PRIMARY KEY,
                stopword VARCHAR(256) NOT NULL,
                language VARCHAR(3) NOT NULL /* 2- or 3-character ISO 690 language code */
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopwords_${stoplist_size}_stopword
                ON stopwords_${stoplist_size}(stopword, language);

            -- Stopword stems
            DROP TABLE IF EXISTS stopword_stems_${stoplist_size};
            CREATE TABLE stopword_stems_${stoplist_size} (
                stopword_stems_${stoplist_size}_id SERIAL PRIMARY KEY,
                stopword_stem VARCHAR(256) NOT NULL,
                language VARCHAR(3) NOT NULL /* 2- or 3-character ISO 690 language code */
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopword_stems_${stoplist_size}_stopword_stem
                ON stopword_stems_${stoplist_size}(stopword_stem, language);

            -- Reset the message level back to "notice".
            SET client_min_messages=NOTICE;

END
          ;

        # For every language
        my @enabled_languages = MediaWords::Languages::Language::enabled_languages();
        foreach my $language_code ( @enabled_languages )
        {
            my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
            if ( !$lang )
            {
                die "Language '$language_code' is not enabled.";
            }

            # collect stopwords
            my $stopwords_hashref;
            if ( $stoplist_size eq 'tiny' )
            {
                $stopwords_hashref = $lang->get_tiny_stop_words();
            }
            elsif ( $stoplist_size eq 'short' )
            {
                $stopwords_hashref = $lang->get_short_stop_words();
            }
            elsif ( $stoplist_size eq 'long' )
            {
                $stopwords_hashref = $lang->get_long_stop_words();
            }
            my @stopwords;
            while ( my ( $stopword, $value ) = each %{ $stopwords_hashref } )
            {
                if ( $value == 1 )
                {
                    $stopword =~ s/'/''/;
                    push( @stopwords, "('$stopword', '$language_code')" );
                }
            }

            # collect stopword stems
            my $stopword_stems_hashref;
            if ( $stoplist_size eq 'tiny' )
            {
                $stopword_stems_hashref = $lang->get_tiny_stop_word_stems();
            }
            elsif ( $stoplist_size eq 'short' )
            {
                $stopword_stems_hashref = $lang->get_short_stop_word_stems();
            }
            elsif ( $stoplist_size eq 'long' )
            {
                $stopword_stems_hashref = $lang->get_long_stop_word_stems();
            }
            my @stopword_stems;
            while ( my ( $stopword_stem, $value ) = each %{ $stopword_stems_hashref } )
            {
                if ( $value == 1 )
                {
                    $stopword_stem =~ s/'/''/;
                    push( @stopword_stems, "('$stopword_stem', '$language_code')" );
                }
            }

            # insert stopwords and stopword stems
            my $joined_stopwords      = join( ', ', @stopwords );
            my $joined_stopword_stems = join( ', ', @stopword_stems );
            $sql .= <<"EOF";
                INSERT INTO stopwords_${ stoplist_size } (stopword, language)
                VALUES $joined_stopwords;

                INSERT INTO stopword_stems_${ stoplist_size } (stopword_stem, language)
                VALUES $joined_stopword_stems;
EOF
        }

    }

    # create a function
    $sql .= <<END

        CREATE OR REPLACE FUNCTION is_stop_stem(p_size TEXT, p_stem TEXT, p_language TEXT)
            RETURNS BOOLEAN AS \$\$
        DECLARE
            result BOOLEAN;
        BEGIN

            -- Tiny
            IF p_size = 'tiny' THEN
                IF p_language IS NULL THEN
                    SELECT 't' INTO result FROM stopword_stems_tiny
                        WHERE stopword_stem = p_stem;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                ELSE
                    SELECT 't' INTO result FROM stopword_stems_tiny
                        WHERE stopword_stem = p_stem AND language = p_language;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                END IF;

            -- Short
            ELSIF p_size = 'short' THEN
                IF p_language IS NULL THEN
                    SELECT 't' INTO result FROM stopword_stems_short
                        WHERE stopword_stem = p_stem;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                ELSE
                    SELECT 't' INTO result FROM stopword_stems_short
                        WHERE stopword_stem = p_stem AND language = p_language;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                END IF;

            -- Long
            ELSIF p_size = 'long' THEN
                IF p_language IS NULL THEN
                    SELECT 't' INTO result FROM stopword_stems_long
                        WHERE stopword_stem = p_stem;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                ELSE
                    SELECT 't' INTO result FROM stopword_stems_long
                        WHERE stopword_stem = p_stem AND language = p_language;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                END IF;

            -- unknown size
            ELSE
                RAISE EXCEPTION 'Unknown stopword stem size: "%" (expected "tiny", "short" or "long")', p_size;
                result := 'f';
            END IF;

            RETURN result;
        END;
        \$\$ LANGUAGE plpgsql;

END
      ;

    return $sql;
}

# get the sql function definitions
sub get_sql_function_definitions
{
    my $sql = '';

    # append is_stop_stem()
    $sql .= get_is_stop_stem_function_tables_and_definition();

    return $sql;
}

# add all of the functions defined in $_functions to the database
sub add_functions
{
    my ( $db ) = @_;

    my $sql = get_sql_function_definitions();
    $db->query( $sql );
}

# Path to where the "pgcrypto.sql" is located (on 8.4 and 9.0)
sub _path_to_pgcrypto_sql_file_84_90()
{
    my $pg_config_share_dir = `pg_config --sharedir`;
    $pg_config_share_dir =~ s/\n//;
    my $pgcrypto_sql_file = "$pg_config_share_dir/contrib/pgcrypto.sql";
    unless ( -e $pgcrypto_sql_file )
    {
        die "'pgcrypto' file does not exist at path: $pgcrypto_sql_file";
    }

    return $pgcrypto_sql_file;
}

sub _pgcrypto_extension_sql($)
{
    my ( $db ) = @_;

    my $sql = '';

    my $postgres_version = _postgresql_version( $db );
    if ( $postgres_version =~ /^PostgreSQL 8/ or $postgres_version =~ /^PostgreSQL 9\.0/ )
    {
        # PostgreSQL 8.x and 9.0
        my $pgcrypto_sql_file = _path_to_pgcrypto_sql_file_84_90;
        open PGCRYPTO_SQL, "< $pgcrypto_sql_file" or die "Can't open $pgcrypto_sql_file : $!\n";
        while ( <PGCRYPTO_SQL> )
        {
            $sql .= $_;
        }
        close PGCRYPTO_SQL;

    }
    else
    {
        # PostgreSQL 9.1+
        $sql = 'CREATE EXTENSION IF NOT EXISTS pgcrypto';
    }

    return $sql;
}

sub _add_pgcrypto_extension($)
{
    my ( $db ) = @_;

    # say STDERR 'Adding "pgcrypto" extension...';

    # Add "pgcrypto" extension
    my $sql = _pgcrypto_extension_sql( $db );
    $db->query( $sql );

    unless ( _pgcrypto_is_installed( $db ) )
    {
        die "'pgcrypto' extension has not been installed.";
    }
}

# Test if "pgcrypto" extension has been installed
sub _pgcrypto_is_installed($)
{
    my ( $db ) = @_;

    if ( $db->query( "SELECT 1 FROM pg_proc WHERE proname = 'gen_random_bytes'" )->hash )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Returns PostgreSQL version (e.g. "PostgreSQL 8.4.17 on
# i386-apple-darwin13.0.0, compiled by GCC Apple LLVM version 5.0
# (clang-500.2.78) (based on LLVM 3.3svn), 64-bit")
sub _postgresql_version($)
{
    my ( $db ) = @_;

    my $postgres_version = $db->query( 'SELECT VERSION() AS version' )->hash;
    $postgres_version = $postgres_version->{ version };
    $postgres_version =~ s/^\s+//;
    $postgres_version =~ s/\s+$//;

    if ( $postgres_version !~ /^PostgreSQL \d.+?$/ )
    {
        die "Unable to parse PostgreSQL version: $postgres_version";
    }

    return $postgres_version;
}

# removes all relations belonging to a given schema
# default schema is 'public'
sub reset_schema($;$)
{
    my ( $db, $schema ) = @_;

    $schema ||= 'public';

    my $postgres_version = _postgresql_version( $db );

    my $old_warn = $db->dbh->{ Warn };
    $db->dbh->{ Warn } = 0;

    $db->query( "DROP SCHEMA IF EXISTS $schema CASCADE" );

    unless ( $postgres_version =~ /^PostgreSQL 8/ or $postgres_version =~ /^PostgreSQL 9\.0/ )
    {
        # Assume PostgreSQL 9.1+ ('DROP EXTENSION' is only available+required since that version)
        $db->query( 'DROP EXTENSION IF EXISTS plpgsql CASCADE' );
    }
    $db->query( "DROP LANGUAGE IF EXISTS plpgsql CASCADE" );

    $db->query( "CREATE LANGUAGE plpgsql" );

    # these schemas will be created later so don't recreate it here
    if ( ( $schema ne 'enum' ) && ( $schema ne 'cd' ) )
    {
        $db->query( "CREATE SCHEMA $schema" );
    }

    $db->dbh->{ Warn } = $old_warn;

    return undef;
}

# recreates all schemas
sub reset_all_schemas($)
{
    my ( $db ) = @_;

    reset_schema( $db, 'public' );

    # removes schema used by dklab enum procedures
    # schema will be re-added in dklab sqlfile
    reset_schema( $db, 'enum' );

    # schema to hold all of the controversy dump snapshot tables
    reset_schema( $db, 'cd' );

    reset_schema( $db, 'stories_tags_map_media_sub_tables' );
}

# Given the PostgreSQL response line (notice) returned while importing schema,
# return 1 if the response line is something that is likely to be in the
# initial schema and 0 otherwise
sub postgresql_response_line_is_expected($)
{
    my $line = shift;

    # Escape whitespace (" ") when adding new options below
    my $expected_line_pattern = qr/
          ^NOTICE:
        | ^CREATE
        | ^ALTER
        | ^\SET
        | ^COMMENT
        | ^INSERT
        | ^\ enum_add.*
        | ^----------.*
        | ^\s+
        | ^\(\d+\ rows?\)
        | ^$
        | ^Time:
        | ^DROP\ LANGUAGE
        | ^DROP\ VIEW
        | ^DROP\ TABLE
        | ^DROP\ FUNCTION
        | ^drop\ cascades\ to\ view\ 
        | ^UPDATE\ \d+
        | ^DROP\ TRIGGER
        | ^Timing\ is\ on\.
        | ^DROP\ INDEX
        | ^psql.*:\ NOTICE:
        | ^DELETE
        | ^SELECT\ 0
    /x;

    if ( $line =~ $expected_line_pattern )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# loads and runs a given SQL file
# useful for rebuilding the database schema after a call to reset_schema
sub load_sql_file
{
    my ( $label, $sql_file ) = @_;

    sub parse_line
    {
        my ( $line ) = @_;

        chomp( $line );

        # say "Got line: '$line'";

        # Die on unexpected SQL (e.g. DROP TABLE)
        unless ( postgresql_response_line_is_expected( $line ) )
        {
            confess "Unexpected PostgreSQL response line: '$line'";
        }

        return "$line\n";
    }

    my $db_settings = MediaWords::DB::connect_settings( $label );
    my $script_dir  = MediaWords::Util::Config::get_config()->{ mediawords }->{ script_dir };
    my $db_type     = $db_settings->{ type };
    my $host        = $db_settings->{ host };
    my $database    = $db_settings->{ db };
    my $username    = $db_settings->{ user };
    my $port        = $db_settings->{ port };
    my $password    = $db_settings->{ pass } . "\n";

    # say "$host $database $username $password ";

    # TODO: potentially brittle, $? should be checked after run3
    # common shell script interface gives indirection to database with no
    # modification of this code.
    # if there is a way to do this without popping out to a shell, please use it

    # stdout and stderr go to this script's channels. password is passed on stdin
    # so it doesn't appear in the process table
    # say STDERR "loadsql: $script_dir/loadsql.$db_type.sh";
    run3( [ "$script_dir/loadsql.$db_type.sh", $sql_file, $host, $database, $username, $port ],
        \$password, \&parse_line, \&parse_line );

    my $ret = $?;
    return $ret;
}

sub recreate_db
{
    my ( $label ) = @_;

    my $do_not_check_schema_version = 1;
    my $db = MediaWords::DB::connect_to_db( $label, $do_not_check_schema_version );

    # say STDERR "reset schema ...";

    reset_all_schemas( $db );

    # say STDERR "add functions ...";
    MediaWords::Pg::Schema::add_functions( $db );

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    # say STDERR "script_dir: $script_dir";

    # say STDERR "add enum functions ...";
    my $load_dklab_postgresql_enum_result = load_sql_file( $label, "$script_dir/dklab_postgresql_enum_2009-02-26.sql" );

    die "Error adding dklab_postgresql_enum procecures" if ( $load_dklab_postgresql_enum_result );

    # say STDERR "Adding 'pgcrypto' extension...";
    _add_pgcrypto_extension( $db );

    # say STDERR "add mediacloud schema ...";
    my $load_sql_file_result = load_sql_file( $label, "$script_dir/mediawords.sql" );

    return $load_sql_file_result;
}

# Upgrade database schema to the latest version
# die()s on error
sub upgrade_db($;$)
{
    my ( $label, $echo_instead_of_executing ) = @_;

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    # say STDERR "script_dir: $script_dir";
    my $db;
    {

        my $do_not_check_schema_version = 1;
        $db = MediaWords::DB::connect_to_db( $label, $do_not_check_schema_version );
    }

    # Current schema version
    my $schema_version_query = <<EOF;
        SELECT value AS schema_version
        FROM database_variables
        WHERE name = 'database-schema-version'
        LIMIT 1
EOF
    my @schema_versions        = $db->query( $schema_version_query )->flat();
    my $current_schema_version = $schema_versions[ 0 ] + 0;
    unless ( $current_schema_version )
    {
        die "Invalid current schema version.";
    }

    # say STDERR "Current schema version: $current_schema_version";

    # Target schema version
    open SQLFILE, "$script_dir/mediawords.sql" or die $!;
    my @sql = <SQLFILE>;
    close SQLFILE;
    my $target_schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( @sql );
    unless ( $target_schema_version )
    {
        die "Invalid target schema version.";
    }

    # say STDERR "Target schema version: $target_schema_version";

    if ( $current_schema_version == $target_schema_version )
    {
        say STDERR "Schema is up-to-date, nothing to upgrade.";
        return;
    }
    if ( $current_schema_version > $target_schema_version )
    {
        die "Current schema version is newer than the target schema version, please update the source code.";
    }

    # Check if the SQL diff files that are needed for upgrade are present before doing anything else
    my @sql_diff_files;
    for ( my $version = $current_schema_version ; $version < $target_schema_version ; ++$version )
    {
        my $diff_filename = './sql_migrations/mediawords-' . $version . '-' . ( $version + 1 ) . '.sql';
        unless ( -e $diff_filename )
        {
            die "SQL diff file '$diff_filename' does not exist.";
        }

        push( @sql_diff_files, $diff_filename );
    }

    # Install "pgcrypto"
    unless ( _pgcrypto_is_installed( $db ) )
    {
        # say STDERR "Adding 'pgcrypto' extension...";

        if ( $echo_instead_of_executing )
        {

            my $pgcrypto_sql = _pgcrypto_extension_sql( $db );

            print "-- --------------------------------\n";
            print "-- 'pgcrypto' extension\n";
            print "-- --------------------------------\n\n\n";

            print $pgcrypto_sql;

        }
        else
        {

            _add_pgcrypto_extension( $db );

        }
    }

    # Import diff files one-by-one
    foreach my $diff_filename ( @sql_diff_files )
    {
        if ( $echo_instead_of_executing )
        {
            say STDERR "Echoing out $diff_filename to STDOUT...";

            print "-- --------------------------------\n";
            print "-- This is a concatenated schema diff between versions " .
              "$current_schema_version and $target_schema_version.\n";
            print "-- Please review this schema diff and import it manually.\n";
            print "-- --------------------------------\n\n\n";

            open DIFF, "< $diff_filename" or die "Can't open $diff_filename : $!\n";
            while ( <DIFF> )
            {
                print;
            }
            close DIFF;

            print "\n-- --------------------------------\n\n\n";

        }
        else
        {
            say STDERR "Importing $diff_filename...";

            my $load_sql_file_result = load_sql_file( $label, $diff_filename );
            if ( $load_sql_file_result )
            {
                die "Executing SQL diff file '$diff_filename' failed.";
            }
        }

    }

    if ( !$echo_instead_of_executing )
    {
        say STDERR "(Re-)adding functions...";
        MediaWords::Pg::Schema::add_functions( $db );
    }

    $db->disconnect;
}

1;
