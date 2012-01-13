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

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $restored_table_name = $table_name . '_restore';

    $db->query(
        "CREATE TABLE $restored_table_name ( LIKE $table_name INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES ); "
    );

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

    $line_num = 0;

    open my $SQL_DUMP_FILE_HANDLE, "<$sql_dump_file" or die $!;

    say STDERR "reading dump file in search of start line ($start_line#) at --" . localtime();

    while ( ( $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $line_num++;

        #say "line number $line_num: '$line'";
        last if $line_num >= $start_line;

        if ( ( $line_num % 100000 ) == 0 )
        {
            say STDERR "Reading line $line_num -- continuing until $start_line";
        }
    }

    die "line is '$line' $line_num != $start_line " unless $line_num == $start_line;

    say STDERR "Reached file start line ($start_line#) at --" . localtime();
    say $line;

    undef( $line );

    while ( ( $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $line_num++;
        last if ( $line =~ /^COPY $table_name \(.*\) FROM stdin;/ );
    }

    die unless $line;

    #say $line;

    my $query = $line;

    $query =~ s/^COPY $table_name \(/COPY $restored_table_name \(/;

    say STDERR "starting datacopy at -- " . localtime();

    say STDERR "SQL Query '$query'";

    $db->dbh->do( $query );

    while ( ( $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $line_num++;

        #say "line number $line_num: '$line'";

        $db->dbh->pg_putcopydata( $line );

        last if $line_num >= $end_line;

        if ( ( $line_num % 10000 ) == 0 )
        {
            say STDERR "On line $line_num continuing until $end_line";
        }
    }

    $db->dbh->pg_putcopyend();

    say STDERR "finished datacopy at -- " . localtime();
}

main();
