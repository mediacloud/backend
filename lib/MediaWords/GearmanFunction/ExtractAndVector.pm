package MediaWords::GearmanFunction::ExtractAndVector;

#
# Extract and vector a download
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/ExtractAndVector.pm
#

use strict;
use warnings;

use Moose;

# Don't log each and every extraction job into the database
with 'Gearman::JobScheduler::AbstractFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::GearmanJobSchedulerConfiguration;

# extract + vector the download; die() and / or return false on error
sub run($$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();
    $db->dbh->{ AutoCommit } = 0;

    my $downloads_id = $args->{ downloads_id };
    unless ( defined $downloads_id )
    {
        die "'downloads_id' is undefined.";
    }

    my $download = $db->find_by_id( 'downloads', $downloads_id );
    unless ( $download->{ downloads_id } )
    {
        die "Download with ID $downloads_id was not found.";
    }

    my $config = MediaWords::Util::Config::get_config();

    my $original_extractor_method = $config->{ mediawords }->{ extractor_method };

    if ( exists $args->{ extractor_method } )
    {
        #set the extractor method
        #NOTE: assumes single threaded processes

        $config->{ mediawords }->{ extractor_method } = $args->{ extractor_method };

        #say STDERR "setting extractor_method to " . $args->{ extractor_method };
    }
    else
    {
        #say STDERR "extractor method not set using default extractor method $original_extractor_method";
    }

    eval {

        my $process_id = 'gearman:' . $$;
        MediaWords::DBI::Downloads::extract_and_vector( $db, $download, $process_id );
        $config->{ mediawords }->{ extractor_method } = $original_extractor_method;
    };
    if ( $@ )
    {
        $config->{ mediawords }->{ extractor_method } = $original_extractor_method;

        # Probably the download was not found
        die "Extractor died: $@\n";

    }

    return 1;
}

# write a single log because there are a lot of extraction jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

# run extraction for the crawler. run in process of mediawords.extract_in_process is configured.
# keep retrying on enqueue error.
sub extract_for_crawler
{
    my ( $self, $db, $download, $fetcher_number ) = @_;

    if ( MediaWords::Util::Config::get_config->{ mediawords }->{ extract_in_process } )
    {
        say STDERR "extracting in process...";
        MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, $fetcher_number );
    }
    else
    {
        while ( 1 )
        {
            eval {
                MediaWords::GearmanFunction::ExtractAndVector->enqueue_on_gearman(
                    { downloads_id => $download->{ downloads_id } } );
            };

            if ( $@ )
            {
                warn( "extractor job queue failed.  sleeping and trying again in 5 seconds: $@" );
                sleep 5;
            }
            else
            {
                last;
            }
        }
        say STDERR "queued extraction";
    }
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
