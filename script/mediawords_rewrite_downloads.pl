#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

# use HTML::Strip;
use MediaWords::DB;
use MediaWords::CommonLibs;

use Readonly;
#use List::Util qw(first max maxstr min minstr reduce shuffle sum);
#use List::Compare::Functional qw (get_unique get_complement get_union_ref );
#use Perl6::Say;
use Data::Dumper;
use Cwd;

#use Thread::Pool;
use 5.14.2;
use threads;
use Thread::Queue;

my $_re_generate_cache = 0;
my $_test_sentences    = 0;

my $_download_data_load_file;
my $_download_data_store_file;
my $_dont_store_preprocessed_lines;
my $_dump_training_data_csv;

my $db_global;

sub _rewrite_download_list
{
    my ( $dbs, $downloads ) = @_;

    say "Starting to process batch of " . scalar( @{ $downloads } );

    Readonly my $status_update_frequency => 10;

    my $downloads_processed = 0;

    foreach my $download ( @{ $downloads } )
    {

        #say "rewriting download " . $download->{ downloads_id };
        #say "Old download path: " . $download->{ path };
        MediaWords::DBI::Downloads::rewrite_downloads_content( $dbs, $download );

        #say "New download path: " . $download->{ path };

        $downloads_processed++;

        if ( $downloads_processed % $status_update_frequency == 0 )
        {
            say "Processed $downloads_processed of " . scalar( @{ $downloads } ) . " downloads";
        }
    }

    return;
}

# do a test run of the text extractor
sub main
{

    my $db = MediaWords::DB->authenticate();

    my $dbs = MediaWords::DB::connect_to_db();

    #my $file;
    #my @download_ids;

    # GetOptions(
    #     'file|f=s'      => \$file,
    #     'downloads|d=s' => \@download_ids,
    # ) or die;

    # my $downloads;

    # if ( @download_ids )
    # {
    #     $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    # }
    # elsif ( $file )
    # {
    #     open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
    #     @download_ids = <DOWNLOAD_ID_FILE>;
    #     $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    # }
    #else
    {

        Readonly my $download_batch_size => 2000;

        Readonly my $max_iterations => 2;

        Readonly my $num_threads => 30;
        my $q = Thread::Queue->new();    # A new empty queue

        my $cwd = getcwd();

        foreach my $thread_num ( 1 .. $num_threads )
        {

            say "Creating thread: $thread_num";

            # Worker thread
            my $thr = threads->create(
                sub {

                    chdir $cwd;

                    use TryCatch;

                    use MediaWords::DBI::Downloads;
                    my $thread_db = MediaWords::DB::connect_to_db();

                    my $thread_id = threads->tid();

                    say STDERR "Thread $thread_id";

                    say STDERR "Starting while loop in thread $thread_id";
                    while ( my $download = $q->dequeue() )
                    {
                        last if $download == -1;

                        #die "test";
                        try
                        {

                            say STDERR "Thread $thread_id rewriting download: " . $download->{ downloads_id };
                            say STDERR "Thread $thread_id old download path: " . $download->{ path };
                            MediaWords::DBI::Downloads::rewrite_downloads_content( $thread_db, $download );
                        }
                        catch
                        {
                            say STDERR "Thread $thread_id caught error on downloads " . $download->{ downloads_id } .
                              " : $@ ";
                            die "Thread $thread_id dying due to caught error on  downloads " . $download->{ downloads_id } .
                              " : $@ ";
                        }
                    }
                    say "Thread $thread_id returning ";
                    threads->exit();

                    return;
                }
            );

        }

        my $iterations = 0;

        my $last_downloads_id = 0;

        my $min_downloads_id_to_rewrite =
          $dbs->query( " SELECT min(downloads_id) from downloads where state = 'success' and path like 'content/%' ; " )
          ->hash->{ min };

        my $max_downloads_id_to_rewrite =
          $dbs->query( " SELECT max(downloads_id) from downloads where state = 'success' and path like 'content/%' ; " )
          ->hash->{ max };

        say STDERR "starting with downloads_id $min_downloads_id_to_rewrite";
	my $downloads;
        do
        {

            while ( $q->pending() > ( $download_batch_size * 3 ) )
            {
                say STDERR $q->pending() . " downloads in q";
                threads->yield();
                sleep( 10 );
            }

            $downloads = $dbs->query(
"select * from downloads where state = 'success' and path like 'content/%' and downloads_id > ? ORDER BY downloads_id asc limit $download_batch_size; ",
                $last_downloads_id
            )->hashes;

            foreach my $download ( @{ $downloads } )
            {
                $q->enqueue( $download );
                $last_downloads_id = $download->{ downloads_id };
            }

            say STDERR "queued downloads for itertaion $iterations";
            say STDERR scalar( @{ $downloads } ) . " downloads downloaded ";
            say STDERR " last queued download $last_downloads_id max download is $max_downloads_id_to_rewrite";
            say STDERR $q->pending() . " downloads in q";

            #_rewrite_download_list( $dbs, $downloads );
            $iterations++;

        } while ( ( scalar( $downloads ) > 0 ) && ( $iterations < $max_iterations ) );

        say STDERR "Joining thread";
        say STDERR $q->pending() . " downloads in q";

        say "Adding thread exit downloads";

        foreach my $thr ( threads->list() )
        {
            $q->enqueue( -1 );
        }

        say STDERR "waiting for queue to empty ";

        while ( $q->pending() > 0 )
        {
            say STDERR $q->pending() . " downloads in q";
            threads->yield();
            sleep( 10 );

            foreach my $thr ( threads->list() )
            {
                if ( $thr->is_joinable )
                {
                    my $tid = $thr->tid;
                    eval {
                        say STDERR "Joining done thread $tid ";
                        $thr->join();
                    };
                    say STDERR "joined thread $tid";
                }
            }

	    last if scalar( threads->list() ) == 0;

        }

        say STDERR "q emptied joining threads";

        foreach my $thr ( threads->list() )
        {
            my $tid = $thr->tid;
            $q->enqueue( -1 );
	    say "Tid is " . $thr->is_joinable . " done ";
            $thr->join();
            say STDERR "joined thread $tid";
        }
    }
}

main();
