package MediaWords::DB::Schema;

# import functions into server schema

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.db.schema.schema' );

use MediaWords::DB::Schema::Version;
use MediaWords::Util::Paths;

use Data::Dumper;
use File::Slurp;

# Upgrade database schema to the latest version
# die()s on error
sub upgrade_db($;$)
{
    my ( $label, $echo_instead_of_executing ) = @_;

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
    my $mediawords_sql_path = "/schema/mediawords.sql";

    my $sql                   = read_file( $mediawords_sql_path );
    my $target_schema_version = MediaWords::DB::Schema::Version::schema_version_from_lines( $sql );

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
        LOGDIE( "Current schema version is newer than the target schema version, please update the source code." );
    }

    # Check if the SQL diff files that are needed for upgrade are present before doing anything else
    my @sql_diff_files;
    for ( my $version = $current_schema_version ; $version < $target_schema_version ; ++$version )
    {
        my $diff_filename = './schema/migrations/mediawords-' . $version . '-' . ( $version + 1 ) . '.sql';
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
