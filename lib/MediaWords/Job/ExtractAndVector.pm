package MediaWords::Job::ExtractAndVector;

#
# Extract and vector a download
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/ExtractAndVector.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Downloads;

# Extract, vector, and process the download or story; LOGDIE() and / or return
# false on error.
#
# Arguments:
# * stories_id OR downloads_id -- story ID or download ID to extract
# * (optional) extractor_method -- extractor method to use (e.g. "PythonReadability")
# * (optional) disable_story_triggers -- disable triggers on "stories" table
#              (probably skips updating db_row_last_updated?)
sub run($$)
{
    my ( $self, $args ) = @_;

    unless ( $args->{ downloads_id } or $args->{ stories_id } )
    {
        LOGDIE "Either 'downloads_id' or 'stories_id' should be set.";
    }
    if ( $args->{ downloads_id } and $args->{ stories_id } )
    {
        LOGDIE "Can't use both downloads_id and stories_id";
    }

    my $extract_by_downloads_id = exists $args->{ downloads_id };
    my $extract_by_stories_id   = exists $args->{ stories_id };

    my $config = MediaWords::Util::Config::get_config();

    my $original_extractor_method = $config->{ mediawords }->{ extractor_method };

    my $alter_extractor_method = 0;
    my $new_extractor_method;
    if ( $args->{ extractor_method } )
    {
        $alter_extractor_method = 1;
        $new_extractor_method   = $args->{ extractor_method };
    }

    my $db = MediaWords::DB::connect_to_db();
    $db->dbh->{ AutoCommit } = 0;

    if ( exists $args->{ disable_story_triggers } and $args->{ disable_story_triggers } )
    {
        $db->query( "SELECT disable_story_triggers(); " );
        MediaWords::DB::disable_story_triggers();
    }
    else
    {
        $db->query( "SELECT enable_story_triggers(); " );
        MediaWords::DB::enable_story_triggers();
    }

    eval {

        my $process_id = 'job:' . $$;

        if ( $alter_extractor_method )
        {
            $config->{ mediawords }->{ extractor_method } = $new_extractor_method;
        }

        if ( $extract_by_downloads_id )
        {
            my $downloads_id = $args->{ downloads_id };
            unless ( defined $downloads_id )
            {
                LOGDIE "'downloads_id' is undefined.";
            }

            my $download = $db->find_by_id( 'downloads', $downloads_id );
            unless ( $download->{ downloads_id } )
            {
                LOGDIE "Download with ID $downloads_id was not found.";
            }

            MediaWords::DBI::Downloads::process_download_for_extractor_and_record_error( $db, $download, $process_id );
        }
        elsif ( $extract_by_stories_id )
        {
            my $stories_id = $args->{ stories_id };
            unless ( defined $stories_id )
            {
                LOGDIE "'stories_id' is undefined.";
            }

            my $story = $db->find_by_id( 'stories', $stories_id );
            unless ( $story->{ stories_id } )
            {
                LOGDIE "Download with ID $stories_id was not found.";
            }

            MediaWords::DBI::Stories::extract_and_process_story( $db, $story, $process_id );
        }
        else
        {
            LOGDIE "shouldn't be reached";
        }

        ## Enable story triggers in case the connection is reused due to connection pooling.
        $db->query( "SELECT enable_story_triggers(); " );
    };

    my $error_message = "$@";

    if ( $alter_extractor_method )
    {
        $config->{ mediawords }->{ extractor_method } = $original_extractor_method;
    }

    if ( $error_message )
    {
        # Probably the download was not found
        LOGDIE "Extractor LOGDIEd: $error_message; job args: " . Dumper( $args );
    }

    return 1;
}

# write a single log because there are a lot of extraction jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

# run extraction for the crawler. run in process of mediawords.extract_in_process is configured.
# keep retrying on error.
sub extract_for_crawler
{
    my ( $self, $db, $args, $fetcher_number ) = @_;

    if ( MediaWords::Util::Config::get_config->{ mediawords }->{ extract_in_process } )
    {
        DEBUG "extracting in process...";
        MediaWords::Job::ExtractAndVector->run( $args );
    }
    else
    {
        while ( 1 )
        {
            eval { MediaWords::Job::ExtractAndVector->add_to_queue( $args ); };

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
        DEBUG "queued extraction";
    }
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
