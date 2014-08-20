#!/usr/bin/env perl

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

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::Process;
use MediaWords::Util::XML;

use XML::LibXML;
use MIME::Base64;
use Encode;
use List::Util qw (min max);
use Parallel::ForkManager;

sub set_relative_path_downloads
{
    my ( $start_downloads_id, $end_downloads_id, $batch_number, $max_downloads_id ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    my $batch_information = '';

    if ( defined( $batch_number ) )
    {
        $batch_information = "Batch $batch_number";
    }

    my $max_downloads_id_message = '';
    if ( defined( $max_downloads_id ) )
    {
        $max_downloads_id_message = " max overall downloads_id $max_downloads_id";
    }

    say STDERR "$batch_information downloads_id $start_downloads_id -- $end_downloads_id  $max_downloads_id_message";

    my $download = $db->query_with_large_work_mem(
"UPDATE downloads set relative_file_path = get_relative_file_path( path ) where relative_file_path = 'tbd' and downloads_id >= ?  and downloads_id <= ? ",
        $start_downloads_id, $end_downloads_id
    );

    return;
}

sub set_relative_path_all_downloads
{

    my ( $start_id ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    my ( $max_downloads_id ) = $db->query( " SELECT max( downloads_id) from downloads where state = 'success' " )->flat();

    my ( $min_downloads_id ) = $db->query( " SELECT min( downloads_id) from downloads " )->flat();

    $start_id //= $min_downloads_id;
    $min_downloads_id = max( $min_downloads_id, $start_id );

    #Make sure the file start and end ranges are multiples of 1000
    my $start_downloads_id = int( $min_downloads_id / 1000 ) * 1000;

    Readonly my $download_batch_size => 10000;

    my $batch_number = 0;

    my $pm = new Parallel::ForkManager( 9 );

    my $empty_download_check_frequency = 10;

    while ( $start_downloads_id <= $max_downloads_id )
    {
        unless ( $pm->start )
        {

            set_relative_path_downloads( $start_downloads_id, $start_downloads_id + $download_batch_size,
                $batch_number, $max_downloads_id );
            $pm->finish;
        }

        $start_downloads_id += $download_batch_size;
        $batch_number++;

        ## Skip over large ranges of empty downloads_id's
        # if ( ( $batch_number % $empty_download_check_frequency ) == 0 )
        # {
        #     ( $start_downloads_id ) =
        #       $db->query( " SELECT min( downloads_id) from downloads where downloads_id >= ? ", $start_downloads_id )
        #       ->flat();
        #     my $start_downloads_id = int( $start_downloads_id / 1000 ) * 1000;
        # }

        #exit;
    }

    say "Waiting for children";

    $pm->wait_all_children;

}

# fork of $num_processes
sub main
{
    my ( $start_id ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    set_relative_path_all_downloads( $start_id );
}

main();
