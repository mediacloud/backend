package MediaWords::Job::ExtractAndVector;

#
# Extract a story
#
# Start this worker script by running:
#
# ./script/run_in_env.sh mjm_worker.pl lib/MediaWords/Job/ExtractAndVector.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::ExtractorArguments;

# sleep for one second if there are more than this number of consecutive requeues
Readonly my $SLEEP_AFTER_REQUEUES => 100;

# count the number of consecutive requeues
my $_consecutive_requeues = 0;

# Extract, vector and process a story; LOGDIE() and / or return
# false on error.
#
# Arguments:
# * stories_id -- story ID to extract
# * (optional) skip_bitly_processing -- don't add extracted story to the Bit.ly
#              processing queue
sub run($$)
{
    my ( $self, $args ) = @_;

    unless ( $args->{ stories_id } )
    {
        LOGDIE "stories_id is not set.";
    }

    my $stories_id = $args->{ stories_id };

    my $db = MediaWords::DB::connect_to_db();

    my $story = $db->require_by_id( 'stories', $stories_id );

    if ( MediaWords::StoryVectors::medium_is_locked( $db, $story->{ media_id } ) )
    {
        WARN( "requeueing job for story $story->{ stories_id } in locked medium $story->{ media_id } ..." );

        # prevent spamming these requeue events if the locked media source is the only one in the queue
        sleep( 1 ) if ( ++$_consecutive_requeues > $SLEEP_AFTER_REQUEUES );

        MediaWords::Job::ExtractAndVector->add_to_queue( $args, $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_LOW );
        return 1;
    }

    $_consecutive_requeues = 0;

    $db->begin;

    my $extractor_args = MediaWords::DBI::Stories::ExtractorArguments->new(
        {
            skip_bitly_processing => $args->{ skip_bitly_processing },
            use_cache             => $args->{ use_cache }
        }
    );

    eval {
        my $story = $db->find_by_id( 'stories', $stories_id );
        unless ( $story->{ stories_id } )
        {
            LOGDIE "Story with ID $stories_id was not found.";
        }

        MediaWords::DBI::Stories::extract_and_process_story( $db, $story, $extractor_args );
    };
    if ( $@ )
    {
        LOGDIE "Extractor died: $@; job args: " . Dumper( $args );
    }

    $db->commit;

    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
