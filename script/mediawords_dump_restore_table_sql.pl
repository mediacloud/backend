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
use Try::Tiny;
use MediaWords::Util::DatabaseRestore;

sub main
{

    my Readonly $usage =
      'USAGE: ./mediawords_dump_restore_table_sql.pl --table_name foo --sql_dump_file dump_file --line_number_file file ';

    my ( $table_name, $sql_dump_file, $line_number_file, $output_file );

    GetOptions(
        'table_name=s'       => \$table_name,
        'sql_dump_file=s'    => \$sql_dump_file,
        'line_number_file=s' => \$line_number_file,
        'output_file=s'      => \$output_file,
    ) or die "$usage\n";

    die "$usage\n"
      unless $table_name && $sql_dump_file && $line_number_file && $output_file;

    MediaWords::Util::DatabaseRestore::test_opening_files( $line_number_file, $sql_dump_file );

    open my $OUTPUT_FILE, '>', $output_file;

    #say STDERR Dumper( [ $table_name, $sql_dump_file, $line_number_file ] );

    say STDERR "starting --  " . localtime();

    my $start_and_end_lines =
      MediaWords::Util::DatabaseRestore::get_start_and_end_line_for_table( $line_number_file, $table_name );

    my $start_line = $start_and_end_lines->{ start_line };
    my $end_line   = $start_and_end_lines->{ end_line };

    open my $SQL_DUMP_FILE_HANDLE, "<", $sql_dump_file or die $!;

    MediaWords::Util::DatabaseRestore::read_until_line_num( $SQL_DUMP_FILE_HANDLE, $start_line );

    my $line_num = $start_line;

    my $restored_table_name = MediaWords::Util::DatabaseRestore::get_restore_table_name( $table_name );
    my $copy_query =
      MediaWords::Util::DatabaseRestore::read_until_copy_statement( $SQL_DUMP_FILE_HANDLE, $table_name, \$line_num );

    $copy_query =~ s/^COPY $table_name \(/COPY $restored_table_name \(/;

    my $restore_table_query =
      "CREATE TABLE $restored_table_name ( LIKE $table_name INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES ); ";

    say $OUTPUT_FILE, $restore_table_query;

    say $OUTPUT_FILE, $copy_query;

    my $routine = sub {
        my ( $line, $line_num ) = @_;

        print  $OUTPUT_FILE $line;
    };

    MediaWords::Util::DatabaseRestore::process_data_until_line_num( $SQL_DUMP_FILE_HANDLE, $start_line, $end_line,
        $routine );

    close( $OUTPUT_FILE );

    say STDERR "finished datacopy at -- " . localtime();
}

main();
