package MediaWords::Util::DatabaseRestore;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Try::Tiny;

# misc utility functions for sql

use strict;

use Time::Local;

#Tests opening the files to make sure they're valid
sub test_opening_files
{
    my ( $line_number_file, $sql_dump_file ) = @_;

    open my $LINE_NUMBERS_FILE_HANDLE, "<", $line_number_file or die $!;
    open my $SQL_DUMP_FILE_HANDLE,     "<", $sql_dump_file    or die $!;
}

sub process_data_until_line_num
{
    my ( $SQL_DUMP_FILE_HANDLE, $start_line, $end_line, $routine ) = @_;

    my $line_num = $start_line;

    while ( ( my $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $line_num++;

        #say "line number $line_num: '$line'";

        $routine->( $line, $line_num );

        last if $line_num >= $end_line;

        if ( ( $line_num % 10000 ) == 0 )
        {
            say STDERR "On line $line_num continuing until $end_line " .
              ( 100.0 * ( $line_num - $start_line ) / ( $end_line - $start_line ) ) . '%';
        }
    }

    die unless $line_num == $end_line;
}

sub copy_data_until_line_num
{
    my ( $db, $SQL_DUMP_FILE_HANDLE, $copy_query, $start_line, $end_line ) = @_;

    say STDERR "starting datacopy at -- " . localtime();

    say STDERR "SQL Query '$copy_query'";

    $db->dbh->do( $copy_query );

    my $routine = sub {
        my ( $line, $line_num ) = @_;

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
    };

    process_data_until_line_num( $SQL_DUMP_FILE_HANDLE, $start_line, $end_line, $routine );
    say STDERR "running pg_putcopyend()";
    $db->dbh->pg_putcopyend();

    return;
}

sub get_start_and_end_line_for_table
{
    my ( $line_number_file, $table_name ) = @_;

    open my $LINE_NUMBERS_FILE_HANDLE, "<", $line_number_file or die $!;

    my $line_num = 0;
    my $line;

    while ( ( $line = <$LINE_NUMBERS_FILE_HANDLE> ) )
    {

        #last if ($line =~ m/Data f/ );
        last if ( $line =~ /^.\d+\:-- Data for Name: $table_name; Type\: TABLE DATA; Schema\: public;/ );

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

sub get_restore_table_name
{
    my ( $table_name ) = @_;

    my $restored_table_name = $table_name . '_restore';

    return $restored_table_name;
}

sub read_until_copy_statement
{
    my ( $SQL_DUMP_FILE_HANDLE, $table_name, $line_num ) = @_;

    my $line;

    while ( ( $line = <$SQL_DUMP_FILE_HANDLE> ) )
    {
        $$line_num++;
        last if ( $line =~ /^COPY $table_name \(.*\) FROM stdin;/ );
    }

    die unless $line;

    my $copy_statement = $line;

    chomp( $copy_statement );
    return $copy_statement;
}

1;
