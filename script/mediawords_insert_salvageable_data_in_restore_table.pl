#!/usr/bin/perl -w

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use XML::LibXML;
use Getopt::Long;
use Readonly;
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

    my Readonly $usage = 'USAGE: ./mediawords_insert_salvageable_data_in_restore_table.pl --table_name foo ';

    my ( $table );

    GetOptions( 'table_name=s' => \$table, ) or die "$usage\n";

    die "$usage\n"
      unless $table;

    say STDERR "starting --  " . localtime();

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $restore_table = $table . '_restore';

    Readonly my $back_records_to_test => 1000;

    Readonly my $restore_table_max_id_query => "select max($table" . "_id) from $restore_table ";

    Readonly my $table_id_range_query => "$table" . "_id > ( ( $restore_table_max_id_query ) - 10 ) and $table" . "_id < ( $restore_table_max_id_query ) ";

    Readonly my $sql_query => "INSERT INTO $restore_table (select * from $table where $table_id_range_query EXCEPT select * from $restore_table where $table_id_range_query ) ";

    say STDERR "Starting SQL query at " . localtime() . " : '$sql_query'";
    $db->query( $sql_query );

    Readonly my $restore_after_old_max_id_query => "INSERT INTO $restore_table 
}

main();
