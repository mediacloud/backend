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
      'USAGE: ./mediawords_restore_table.pl --table_name foo --sql_dump_file dump_file --line_number_file file ';

    my ( $table_name, $sql_dump_file, $line_number_file );

    GetOptions(
        'table_name=s'       => \$table_name,
        'sql_dump_file=s'    => \$sql_dump_file,
        'line_number_file=s' => \$line_number_file
    ) or die "$usage\n";

    die "$usage\n"
      unless $table_name && $sql_dump_file && $line_number_file;

    MediaWords::Util::DatabaseRestore::test_opening_files( $line_number_file, $sql_dump_file );

    #say STDERR Dumper( [ $table_name, $sql_dump_file, $line_number_file ] );

    say STDERR "starting --  " . localtime();

    my $start_and_end_lines = MediaWords::Util::DatabaseRestore::get_start_and_end_line_for_table( $line_number_file, $table_name );

    my $start_line = $start_and_end_lines->{ start_line };
    my $end_line   = $start_and_end_lines->{ end_line };

    open my $SQL_DUMP_FILE_HANDLE, "<$sql_dump_file" or die $!;

    MediaWords::Util::DatabaseRestore::read_until_line_num( $SQL_DUMP_FILE_HANDLE, $start_line );

    my $line_num = $start_line;

    #say $line;

    my $query =  MediaWords::Util::DatabaseRestore::read_until_copy_statement( $SQL_DUMP_FILE_HANDLE, $table_name, \$line_num );

    my $restored_table_name = MediaWords::Util::DatabaseRestore::get_restore_table_name( $table_name );

    $query =~ s/^COPY $table_name \(/COPY $restored_table_name \(/;

    my $restore_table_query =
      "CREATE TABLE $restored_table_name ( LIKE $table_name INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES ); ";

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    $db->dbh->{ AutoCommit } = 0;

    $db->query( $restore_table_query );

    my $end_line_1 = int( $line_num + ( $end_line - $line_num ) / 2 );

    my $end_line_2 = $end_line;

    MediaWords::Util::DatabaseRestore::copy_data_until_line_num( $db, $SQL_DUMP_FILE_HANDLE, $query, $line_num, $end_line_1 );

    say STDERR "committing first copy";

    $db->commit;
    $db->disconnect;

    $db = 0;

    $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    $db->dbh->{ AutoCommit } = 0;

    MediaWords::Util::DatabaseRestore::copy_data_until_line_num( $db, $SQL_DUMP_FILE_HANDLE, $query, $line_num, $end_line_1 );

    say STDERR "committing first copy";

    $db->commit;
    $db->disconnect;

    say STDERR "finished datacopy at -- " . localtime();
}

main();
