#!/usr/bin/perl

# run a loop extracting the text of any downloads that have not been extracted yet

# usage: mediawords_extract_text.pl [<process num> <num of processes>]
#
# to run several instances in parallel, supply the number of the given process and the total number of processes
# example:
# mediawords_extract_tags.pl 1 4 &
# mediawords_extract_tags.pl 2 4 &
# mediawords_extract_tags.pl 3 4 &
# mediawords_extract_tags.pl 4 4 &

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

BEGIN
{
    use constant MODULES => qw(Calais);

    for my $module ( MODULES )
    {
        eval( "use MediaWords::Tagger::${module};" );
        if ( $@ )
        {
            die( "error loading $module: $@" );
        }
    }
}

use Encode;
use MediaWords::DB;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
use MediaWords::Tagger;
use MediaWords::Crawler::Extractor;
use MediaWords::DBI::Downloads;
use List::Uniq ':all';

sub main
{

    my ( $process_num, $num_processes ) = @ARGV;

    $process_num   ||= 1;
    $num_processes ||= 1;

    my $db = MediaWords::DB->authenticate();

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $downloads_processed = 0;

    my $downloads_id_window_start = 0;
    my $downloads_batch_size      = 100000;
    my $downloads_id_window_end   = $downloads_id_window_start + $downloads_batch_size;

    while ( 1 )
    {
        print STDERR "while(1) loop\n";

        my $unextracted_downloads_query =
"SELECT downloads.* from downloads left join download_texts on (download_texts.downloads_id=downloads.downloads_id) where download_texts.downloads_id is null and extracted and type='content' and downloads.downloads_id >= ? and downloads.downloads_id <= ? limit 200000 ";

        ( my $max_downloads_id ) = $dbs->query( "select max(downloads_id) from downloads" )->flat();

        print STDERR "max downloads_id = $max_downloads_id\n";
        $downloads_id_window_end = $max_downloads_id;

        print STDERR "Running query '$unextracted_downloads_query'\n";

        my $downloads = $dbs->query( $unextracted_downloads_query, $downloads_id_window_start, $downloads_id_window_end );

        print STDERR "query completed for $unextracted_downloads_query\n";

        my $download_found;
        my $previous_processed_down_load_end_time = time();
        while ( my $download = $downloads->hash() )
        {

            $downloads_processed++;

            if ( $downloads_processed > 1000 )
            {

                #exit;
            }

            print STDERR ' while ( my $download' . "\n";

            # ignore downloads for multi-processor runs
            if ( ( $download->{ downloads_id } + $process_num ) % $num_processes )
            {
                print STDERR "Ignoring  " . $download->{ downloads_id } . "  + $process_num \n";
                next;
            }

            my @rows =
              $dbs->query( "select * from download_texts where downloads_id = ? ", $download->{ downloads_id } )->array;

            if ( @rows > 0 )
            {
                print @rows;
                print STDERR "download " . $download->{ downloads_id } . " already in download_texts\n";
                next;
            }

            print STDERR "processing download id:" . $download->{ downloads_id } . "  -- " .
              ( ( time() ) - $previous_processed_down_load_end_time ) . " since last download processed\n";

            $download_found = 1;

            my $extracted_text_start_time = time();

            my $extracted_text = MediaWords::DBI::Downloads::get_previously_extracted_text( $dbs, $download );

            my $extracted_text_end_time = time();

            print STDERR "Got extracted text took " . ( $extracted_text_end_time - $extracted_text_start_time ) .
              " secs : " .
              length( $extracted_text ) . "characters\n";

            print "\n";
            print STDERR "Completed storing extracted text for download\n";

            $previous_processed_down_load_end_time = time();

        }    #end while

        if ( !$download_found )
        {
            print STDERR "no downloads found. sleeping ...\n";

            sleep 1;

            #             print STDERR "incrementing downloads_id window ...\n";
            #             $downloads_id_window_start += $downloads_batch_size;
            #             $downloads_id_window_end   += $downloads_batch_size;
            #             print STDERR "downloads_id windows: $downloads_id_window_start -  $downloads_id_window_end \n";
        }

        print STDERR "Completed batches of download text extraction and storage\n";
    }
}

eval { main(); };

print "exit: $@\n";
