#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

# use MediaWords::Crawler::Extractor;
use Getopt::Long;

# use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::CommonLibs;

use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Perl6::Say;
use Data::Dumper;

# use MediaWords::Util::HTML;
# use MediaWords::Util::ExtractorTest;
# use Data::Compare;
# use Storable;
# use MediaWords::DBI::Downloads;

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

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'      => \$file,
        'downloads|d=s' => \@download_ids,
    ) or die;

    my $downloads;

    if ( @download_ids )
    {
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    elsif ( $file )
    {
        open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
        @download_ids = <DOWNLOAD_ID_FILE>;
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    else
    {

        Readonly my $download_batch_size => 50;

        Readonly my $max_iterations => 1_000;

        Readonly my $num_threads => 5;
        my $q = Thread::Queue->new();    # A new empty queue

        foreach my $thread_num ( 1 .. $num_threads )
        {

            say "Creating thread: $thread_num";

            # Worker thread
            my $thr = threads->create(
                sub {

		    use TryCatch;

                    use MediaWords::DBI::Downloads;
                    my $thread_db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

                    my $thread_id = threads->tid();
		    
		    say STDERR "Thread $thread_id";

		    say STDERR "Try::Tiny used";

                    try
                    {
			say STDERR "Starting while loop in thread $thread_id";
                        while ( my $download = $q->dequeue() )
                        {
                            last if $download == -1;

                            #die "test";
                            say STDERR "Thread $thread_id rewriting download: " . $download->{ downloads_id };
                            say STDERR "Thread $thread_id old download path: " . $download->{ path };
                            MediaWords::DBI::Downloads::rewrite_downloads_content( $thread_db, $download );
                        }
                        say "Thread $thread_id returning ";
                        threads->exit();

                    }
                    catch
                    {
                        say STDERR "Thread $thread_id dying due to caught error: $_ ";
                        #die "Thread $thread_id dying due to caught error: $_ ";
                    }
                    return;
                }
            );

        }

        my $iterations = 0;

        do
        {
            $downloads = $dbs->query(
"select * from downloads where state = 'success' and path like 'content/%' ORDER BY downloads_id asc limit $download_batch_size; "
            )->hashes;

            foreach my $download ( @{ $downloads } )
            {
                $q->enqueue( $download );
            }

            say STDERR "queued downloads for itertaion $iterations";
	    say STDERR scalar( @ { $downloads} ) . " downloads downloaded ";
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

	while ($q->pending() > 0 )
	{
	    threads->yield();
	    sleep(1);
	}

	say STDERR "q emptied joining threads";

        foreach my $thr ( threads->list() )
        {
            $q->enqueue( -1 );
            $thr->join();
            say STDERR "joined thread";
        }
    }
}

main();
