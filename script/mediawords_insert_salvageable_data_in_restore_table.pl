#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use XML::LibXML;
use Getopt::Long;
use Carp;
use MIME::Base64;

#Tests opening the files to make sure they're valid
sub test_opening_files
{
    my ( $line_number_file, $sql_dump_file ) = @_;

    open my $LINE_NUMBERS_FILE_HANDLE, "<$line_number_file" or die $!;
    open my $SQL_DUMP_FILE_HANDLE,     "<$sql_dump_file"    or die $!;
}

sub main
{

    my $usage = 'USAGE: ./mediawords_insert_salvageable_data_in_restore_table.pl --table_name foo ';

    my ( $table );

    GetOptions( 'table_name=s' => \$table, ) or die "$usage\n";

    die "$usage\n"
      unless $table;

    my $start_time = localtime();

    say STDERR "starting --  $start_time";

    my $db = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    my $restore_table = $table . '_restore';

    my $back_records_to_test = 10000;

    my $restore_table_max_id_query = "SELECT MAX(${table}_id) FROM $restore_table ";

    my $table_id_range_query = <<"EOF";

        ${table}_id > ( ( $restore_table_max_id_query ) - $back_records_to_test )
    AND ${table}_id < ( $restore_table_max_id_query )

EOF

    my $sql_query = <<"EOF";

        INSERT INTO $restore_table (
            SELECT *
            FROM $table
            WHERE $table_id_range_query
            EXCEPT
                SELECT *
                FROM $restore_table
                WHERE $table_id_range_query
        )

EOF

    say STDERR "Starting SQL query at " . localtime() . " : '$sql_query'";
    $db->query( $sql_query );

    my $restore_after_old_max_id_query = <<"EOF";

        INSERT INTO $restore_table
            SELECT *
            FROM $table
            WHERE ${table}_id > ( $restore_table_max_id_query )

EOF

    #say STDERR "Starting SQL query at " . localtime() . " : '$restore_after_old_max_id_query'";
    #$db->query( $restore_after_old_max_id_query );

    my $end_time = localtime();

    say STDERR "Completed start: $start_time end: $end_time";
}

main();
