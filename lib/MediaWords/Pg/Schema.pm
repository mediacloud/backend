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
use File::Slurp;
use FindBin;
use Data::Dumper;

# recreates all schemas
sub _reset_all_schemas($)
{
    my ( $db ) = @_;

    my $schemas = $db->query(
        <<SQL
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name NOT LIKE 'pg_%'
          AND schema_name != 'information_schema'
        ORDER BY schema_name
SQL
    )->flat;
    foreach my $schema ( @{ $schemas } )
    {
        $db->query( "DROP SCHEMA IF EXISTS $schema CASCADE" );
    }
}

# Given the PostgreSQL response line (notice) returned while importing schema,
# return 1 if the response line is something that is likely to be in the
# initial schema and 0 otherwise
sub _postgresql_response_line_is_expected($)
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
# useful for rebuilding the database schema after a call to _reset_schema()
sub _load_sql_file
{
    my ( $label, $sql_file ) = @_;

    sub _parse_line
    {
        my ( $line ) = @_;

        chomp( $line );

        TRACE "Got line: '$line'";

        # Die on unexpected SQL (e.g. DROP TABLE)
        unless ( _postgresql_response_line_is_expected( $line ) )
        {
            LOGCONFESS "Unexpected PostgreSQL response line: '$line'";
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
    # INFO "loadsql: $script_dir/loadsql.$db_type.sh";
    my $command = [ "$script_dir/loadsql.$db_type.sh", $sql_file, $host, $database, $username, $port ];
    run3( $command, \$password, \&_parse_line, \&_parse_line );

    my $ret = $?;
    if ( $ret != 0 )
    {
        die "Unable to load schema with command: " . Dumper( $command );
    }

    return 1;
}

# (Re)create database schema; die() on error
sub recreate_db
{
    my ( $label ) = @_;

    my $do_not_check_schema_version = 1;
    my $db = MediaWords::DB::connect_to_db( $label, $do_not_check_schema_version );

    DEBUG( 'Resetting schema...' );
    _reset_all_schemas( $db );

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;
    TRACE( "script_dir: $script_dir" );

    DEBUG( "Importing schema..." );
    _load_sql_file( $label, "$script_dir/mediawords.sql" );

    return 1;
}

# Upgrade database schema to the latest version
# die()s on error
sub upgrade_db($;$)
{
    my ( $label, $echo_instead_of_executing ) = @_;

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    DEBUG "script_dir: $script_dir";
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

    INFO "Current schema version: $current_schema_version";

    # Target schema version
    open SQLFILE, "$script_dir/mediawords.sql" or LOGDIE $!;
    my @sql = <SQLFILE>;
    close SQLFILE;
    my $target_schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( @sql );
    unless ( $target_schema_version )
    {
        LOGDIE( "Invalid target schema version." );
    }

    INFO "Target schema version: $target_schema_version";

    if ( $current_schema_version == $target_schema_version )
    {
        INFO "Schema is up-to-date, nothing to upgrade.";
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
