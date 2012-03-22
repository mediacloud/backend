#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Lingua::EN::Sentence::MediaWords;
use Perl6::Say;
use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use Data::Compare;
use Storable;
use MediaWords::DBI::Downloads;
use Thread::Pool;
use 5.14.2;

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

sub worker_routine
{
    my ( $download ) = @_;

    say STDERR "Calling worker_routine";

    #return;

    return _rewrite_download_list( $db_global, [ $download ] );
}

sub _get_pool
{
    my $pool = Thread::Pool->new(
        {
            optimize => 'cpu',    # default: memory

            do => \&worker_routine,    # must have
                                      pre => sub { $db_global = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info ); },      # default: none
                                      #post => sub { print "stopping with @_\n",     # default: none

            #stream => sub { print "streamline with @_\n", # default: none

            #monitor => sub { print "monitor with @_\n",   # default: none
            pre_post_monitor_only => 0,    # default: 0 = also for "do"
                                           #checkpoint => \&checkpoint,
                                           #frequency => 1000,

            autoshutdown => 1,             # default: 1 = yes

            workers => 10,                 # default: 1
            maxjobs => 50,                 # default: 5 * workers
            minjobs => 20,                 # default: maxjobs / 2
        },

    );

    return $pool;
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

        Readonly my $max_iterations => 2;

        my $iterations = 0;

	say STDERR "Calling _get_pool";

	my $pool = _get_pool();

	say STDERR "Called _get_pool";

        do
        {
            $downloads = $dbs->query(
"select * from downloads where state = 'success' and path like 'content/%' ORDER BY downloads_id asc limit $download_batch_size; "
            )->hashes;

	    my $jobs_added = 0;

	    foreach my $download ( @ { $downloads } )
	    {
		$pool->job( $download);
		$jobs_added++;
		say "Added $jobs_added";
	    }

            #_rewrite_download_list( $dbs, $downloads );
            $iterations++;

        } while ( ( scalar( $downloads ) > 0 ) && ( $iterations < $max_iterations ) );

	say STDERR "Shutting down pool";
	$pool->shutdown();
	say STDERR "Shut down pool";

	
    }
}

main();
