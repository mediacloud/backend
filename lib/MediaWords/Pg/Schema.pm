package MediaWords::Pg::Schema;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;
use MediaWords::Util::Config;
use MediaWords::Util::SchemaVersion;

# import functions into server schema

use strict;
use warnings;

use IPC::Run3;
use Carp qw/ confess /;
use File::Slurp;
use FindBin;

# Path to where the "pgcrypto.sql" is located (on 8.4 and 9.0)
sub _path_to_pgcrypto_sql_file_84_90()
{
    my $pg_config_share_dir = `pg_config --sharedir`;
    $pg_config_share_dir =~ s/\n//;
    my $pgcrypto_sql_file = "$pg_config_share_dir/contrib/pgcrypto.sql";
    unless ( -e $pgcrypto_sql_file )
    {
        LOGDIE "'pgcrypto' file does not exist at path: $pgcrypto_sql_file";
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
        open PGCRYPTO_SQL, "< $pgcrypto_sql_file" or LOGDIE "Can't open $pgcrypto_sql_file : $!\n";
        while ( <PGCRYPTO_SQL> )
        {
            $sql .= $_;
        }
        close PGCRYPTO_SQL;

    }
    else
    {
        # PostgreSQL 9.1+
        $sql = 'CREATE EXTENSION IF NOT EXISTS pgcrypto;';
    }

    return $sql;
}

sub _add_pgcrypto_extension($)
{
    my ( $db ) = @_;

    DEBUG( 'Adding "pgcrypto" extension...' );

    # Add "pgcrypto" extension
    my $sql = _pgcrypto_extension_sql( $db );
    $db->query( $sql );

    unless ( _pgcrypto_is_installed( $db ) )
    {
        LOGDIE "'pgcrypto' extension has not been installed.";
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
        LOGDIE "Unable to parse PostgreSQL version: $postgres_version";
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
    if ( ( $schema ne 'enum' ) && ( $schema ne 'snap' ) )
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

    # schema to hold all of the topic snapshot snapshot tables
    reset_schema( $db, 'snap' );
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
        | ^Pager\ usage\ is\ off
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

    DEBUG( 'reset schema ...' );
    my $data_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ data_dir };
    if ( $data_dir )
    {
        my $cache_dir = "$data_dir/cache";
        File::Path::remove_tree( $cache_dir, { keep_root => 1 } );
    }

    reset_all_schemas( $db );

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    DEBUG( "script_dir: $script_dir" );

    DEBUG( "Adding 'pgcrypto' extension..." );
    _add_pgcrypto_extension( $db );

    DEBUG( "add mediacloud schema ..." );
    my $load_sql_file_result = load_sql_file( $label, "$script_dir/mediawords.sql" );

    return $load_sql_file_result;
}

# Upgrade database schema to the latest version
# die()s on error
sub upgrade_db($;$)
{
    my ( $label, $echo_instead_of_executing ) = @_;

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    DEBUG( sub { "script_dir: $script_dir" } );
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
        LOGDIE "Invalid current schema version.";
    }

    INFO( sub { "Current schema version: $current_schema_version" } );

    # Target schema version
    open SQLFILE, "$script_dir/mediawords.sql" or LOGDIE $!;
    my @sql = <SQLFILE>;
    close SQLFILE;
    my $target_schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( @sql );
    unless ( $target_schema_version )
    {
        LOGDIE( "Invalid target schema version." );
    }

    INFO( sub { "Target schema version: $target_schema_version" } );

    if ( $current_schema_version == $target_schema_version )
    {
        INFO( sub { "Schema is up-to-date, nothing to upgrade." } );
        return;
    }
    if ( $current_schema_version > $target_schema_version )
    {
        LOGIDE( "Current schema version is newer than the target schema version, please update the source code." );
    }

    # Check if the SQL diff files that are needed for upgrade are present before doing anything else
    my @sql_diff_files;
    for ( my $version = $current_schema_version ; $version < $target_schema_version ; ++$version )
    {
        my $diff_filename = './sql_migrations/mediawords-' . $version . '-' . ( $version + 1 ) . '.sql';
        unless ( -e $diff_filename )
        {
            LOGDIE "SQL diff file '$diff_filename' does not exist.";
        }

        push( @sql_diff_files, $diff_filename );
    }

    my $upgrade_sql = '';

    # Install "pgcrypto"
    unless ( _pgcrypto_is_installed( $db ) )
    {
        $upgrade_sql .= <<EOF;
--
-- "pgcrypto" extension
--
EOF
        $upgrade_sql .= _pgcrypto_extension_sql( $db );
        $upgrade_sql .= "\n\n";
    }

    if ( $echo_instead_of_executing )
    {
        $upgrade_sql .= <<"EOF";
-- --------------------------------
-- This is a concatenated schema diff between versions
-- $current_schema_version and $target_schema_version.
--
-- Please review this schema diff and import it manually.
-- --------------------------------

EOF
    }

    # Add SQL diff files one-by-one
    foreach my $diff_filename ( @sql_diff_files )
    {
        my $sql_diff = read_file( $diff_filename );
        unless ( defined $sql_diff )
        {
            LOGDIE "Unable to read SQL diff file: $sql_diff";
        }
        unless ( $sql_diff )
        {
            LOGDIE "SQL diff file is empty: $sql_diff";
        }

        $upgrade_sql .= $sql_diff;
        $upgrade_sql .= "\n-- --------------------------------\n\n\n";
    }

    # Wrap into a transaction
    if ( $upgrade_sql =~ /BEGIN;/i or $upgrade_sql =~ /COMMIT;/i )
    {
        LOGDIE "Upgrade script already BEGINs and COMMITs a transaction. Please upgrade the database manually.";
    }
    $upgrade_sql = "BEGIN;\n\n\n" . $upgrade_sql;
    $upgrade_sql .= "COMMIT;\n\n";

    if ( $echo_instead_of_executing )
    {
        binmode( STDOUT, ":utf8" );
        binmode( STDERR, ":utf8" );

        print "$upgrade_sql";
    }
    else
    {
        $db->query( $upgrade_sql );
    }

    $db->disconnect;
}

1;
