#!/usr/bin/env perl

# dump a single table in parallel.  dumping a table with parallel jobs is much faster that doing it individually

# usage: $0 --table < table name > --jobs < num jobs >

use strict;
use warnings;

use v5.10;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use Fcntl qw(:flock);
use Getopt::Long;
use Parallel::ForkManager;

use MediaWords::DB;
use MediaWords::Util::SQL;

# get the min primary id and max primary id of the table
sub get_key_min_max
{
    my ( $db, $table ) = @_;

    my $key = $db->primary_key_column( $table );

    die( "no primary key for table '$table'" ) unless ( $key );

    my ( $min, $max ) = $db->query( <<SQL )->flat;
select min( $key ), max( $key ) from $table
SQL

    return ( $key, $min, $max );
}

sub flush_lines_buf
{
    my ( $fh, $lines ) = @_;

    flock( $fh, LOCK_EX );

    map { print encode( 'utf8', $_ ) } @{ $lines };

    flock( $fh, LOCK_UN );

    @{ $lines } = ();
}

sub dump_table_single
{
    my ( $lock_file, $table, $key, $min, $range ) = @_;

    open( my $fh, ">$lock_file" ) || die( "Unable to open lock file '$lock_file': $!" );

    # reconnect after starting new process
    my $db = MediaWords::DB::connect_to_db;

    $| = 1;

    $db->query( <<SQL );
copy
    ( select * from $table where $key between $min and ( $min + $range ) )
    to STDOUT
    with csv
SQL

    my $lines_buf = [];
    my $line      = '';
    while ( $db->dbh->pg_getcopydata( $line ) > -1 )
    {
        push( @{ $lines_buf }, $line );

        # only print lines every 1000 lines to avoid locking too much
        flush_lines_buf( $fh, $lines_buf ) if ( @{ $lines_buf } > 1000 );
    }

    flush_lines_buf( $fh, $lines_buf );

    close( $fh );
}

# print the csv header line once before the parallel processes start writing to stdout
sub print_csv_header
{
    my ( $db, $table ) = @_;

    $db->query( "copy ( select * from $table where false ) to STDOUT with csv header" );

    my $line = '';
    $db->dbh->pg_getcopydata( $line );

    print $line;
}

sub dump_table
{
    my ( $db, $table, $num_proc ) = @_;

    my $day = substr( MediaWords::Util::SQL::sql_now, 0, 10 );

    my ( $key, $min, $max ) = get_key_min_max( $db, $table );

    my $range = int( ( $max - $min ) / $num_proc ) + 1;

    my $pm = new Parallel::ForkManager( $num_proc );

    print_csv_header( $db, $table );

    my $lock_file = "/tmp/dump-$table-$day-$$";

    for my $proc ( 1 .. $num_proc )
    {
        if ( $pm->start )
        {
            $min += $range + 1;
        }
        else
        {
            dump_table_single( $lock_file, $table, $key, $min, $range );
            $pm->finish;
        }
    }

    $pm->wait_all_children;

    unlink( $lock_file );

}

sub main
{
    my ( $table, $jobs );

    $| = 1;

    Getopt::Long::GetOptions(
        "jobs=i"  => \$jobs,
        "table=s" => \$table
    ) || return;

    die( "usage:  $0 --table < table name > --jobs < num jobs >" ) if ( !$jobs || !$table );

    my $db = MediaWords::DB::connect_to_db;

    dump_table( $db, $table, $jobs );
}

main();
