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

#Tests opening the files to make sure they're valid
sub test_opening_files
{
    my ( $line_number_file, $sql_dump_file ) = @_;

    open my $LINE_NUMBERS_FILE_HANDLE, "<", $line_number_file or die $!;
    open my $SQL_DUMP_FILE_HANDLE,     "<", $sql_dump_file    or die $!;
}

sub copy_data_until_line_num
{
    my ( $db, $SQL_DUMP_FILE_HANDLE, $copy_query, $start_line, $end_line ) = @_;

    say STDERR "starting datacopy at -- " . localtime();

    say STDERR "SQL Query '$copy_query'";

    $db->dbh->do( $copy_query );

    my $line_num = $start_line;

    while ( ( my $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $line_num++;

        #say "line number $line_num: '$line'";

        try
        {

            #say STDERR "putting data";

            $db->dbh->pg_putcopydata( $line );
        }
        catch
        {
            my $message =
              "Database error with pg_putcopydata line number $line_num '$line' " . "at " . localtime() . " :\n" . "$_";
            die $message;
        };

        last if $line_num >= $end_line;

        if ( ( $line_num % 10000 ) == 0 )
        {
            say STDERR "On line $line_num continuing until $end_line " .
              ( 100.0 * ( $line_num - $start_line ) / ( $end_line - $start_line ) ) . '%';
        }
    }

    die unless $line_num == $end_line;

    say STDERR "running pg_putcopyend()";
    $db->dbh->pg_putcopyend();

    return;
}

sub get_start_and_end_line_for_table
{
    my ( $line_number_file, $table_name ) = @_;

    open my $LINE_NUMBERS_FILE_HANDLE, "<$line_number_file" or die $!;

    my $line_num = 0;
    my $line;

    while ( ( $line = <$LINE_NUMBERS_FILE_HANDLE> ) )
    {

        #last if ($line =~ m/Data f/ );
        last if ( $line =~ /.\d+\:-- Data for Name: $table_name; Type\: TABLE DATA; Schema\: public;/ );

        #last if ($line =~ m/.\d+/ );
        $line_num++;
    }

    say STDERR "Line:'$line'";

    #say STDERR $line_num;

    my ( $start_line ) = split ':', $line;

    say STDERR "start line:$start_line";

    $line = <$LINE_NUMBERS_FILE_HANDLE>;
    $line = <$LINE_NUMBERS_FILE_HANDLE>;

    my ( $end_line ) = split ':', $line;

    say STDERR "end_line: $end_line";

    close( $LINE_NUMBERS_FILE_HANDLE );

    return { start_line => $start_line, end_line => $end_line };

}

sub read_until_line_num
{

    my ( $SQL_DUMP_FILE_HANDLE, $start_line ) = @_;

    my $line_num = 0;

    say STDERR "reading dump file in search of start line ($start_line#) at --" . localtime();

    while ( <$SQL_DUMP_FILE_HANDLE> )
    {
        $line_num++;

        #say "line number $line_num: '$line'";
        last if $line_num >= $start_line;

        if ( ( $line_num % 100000 ) == 0 )
        {
            say STDERR "Reading line $line_num -- continuing until $start_line " . ( 100.0 * $line_num / $start_line ) . "%";
        }
    }

    die " $line_num != $start_line " unless $line_num == $start_line;

    say STDERR "Reached file start line ($start_line#) at --" . localtime();

    return;
}

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

    test_opening_files( $line_number_file, $sql_dump_file );

    #say STDERR Dumper( [ $table_name, $sql_dump_file, $line_number_file ] );

    say STDERR "starting --  " . localtime();

    my $start_and_end_lines = get_start_and_end_line_for_table( $line_number_file, $table_name );

    my $start_line = $start_and_end_lines->{ start_line };
    my $end_line   = $start_and_end_lines->{ end_line };

    open my $SQL_DUMP_FILE_HANDLE, "<$sql_dump_file" or die $!;

    read_until_line_num( $SQL_DUMP_FILE_HANDLE, $start_line );

    my $line_num = $start_line;

    #say $line;

    my $line;

    while ( ( $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $line_num++;
        last if ( $line =~ /^COPY $table_name \(.*\) FROM stdin;/ );
    }

    die unless $line;

    #say $line;

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    $db->dbh->{ AutoCommit } = 0;

    my $restored_table_name = $table_name . '_restore';

    $db->query(
        "CREATE TABLE $restored_table_name ( LIKE $table_name INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES ); "
    );

    my $query = $line;

    $query =~ s/^COPY $table_name \(/COPY $restored_table_name \(/;

    my $end_line_1 = int( $line_num + ( $end_line - $line_num ) / 2 );

    my $end_line_2 = $end_line;

    copy_data_until_line_num( $db, $SQL_DUMP_FILE_HANDLE, $query, $line_num, $end_line_1 );

    say STDERR "committing first copy";

    $db->commit;
    $db->disconnect;

    $db = 0;

    $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    $db->dbh->{ AutoCommit } = 0;

    copy_data_until_line_num( $db, $SQL_DUMP_FILE_HANDLE, $query, $line_num, $end_line_1 );

    say STDERR "committing first copy";

    $db->commit;
    $db->disconnect;

    say STDERR "finished datacopy at -- " . localtime();
}

main();
