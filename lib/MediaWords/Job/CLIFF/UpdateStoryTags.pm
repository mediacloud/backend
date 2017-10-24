package MediaWords::Job::CLIFF::UpdateStoryTags;

#
# Create / update story tags using CLIFF annotation
#
# Start this worker script by running:
#
# ./script/run_in_env.sh mjm_worker.pl lib/MediaWords/Job/CLIFF/UpdateStoryTags.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Job::NYTLabels::FetchAnnotation;
use MediaWords::Util::Annotator::CLIFF;
use MediaWords::Util::Annotator::NYTLabels;

use Readonly;
use Data::Dumper;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } + 0 or die "'stories_id' is not set.";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story->{ stories_id } )
    {
        die "Story with ID $stories_id was not found.";
    }

    # Annotate story with CLIFF
    my $cliff = MediaWords::Util::Annotator::CLIFF->new();
    eval { $cliff->update_tags_for_story( $db, $stories_id ); };
    if ( $@ )
    {
        die "Unable to process story $stories_id with CLIFF: $@\n";
    }

    # Pass the story further to NYTLabels annotator
    my $nytlabels = MediaWords::Util::Annotator::NYTLabels->new();

    if ( $nytlabels->annotator_is_enabled() and $nytlabels->story_is_annotatable( $db, $stories_id ) )
    {

        # NYTLabels annotator will mark the story as processed after running
        DEBUG "Adding story $stories_id to NYTLabels annotation queue...";
        MediaWords::Job::NYTLabels::FetchAnnotation->add_to_queue( { stories_id => $stories_id } );

    }
    else
    {

        TRACE "Won't add $stories_id to NYTLabels annotation queue because it's not annotatable with NYTLabels";

        # If NYTLabels is not enabled, mark the story as processed ourselves
        TRACE "Marking the story as processed...";
        unless ( MediaWords::DBI::Stories::mark_as_processed( $db, $stories_id ) )
        {
            die "Unable to mark story ID $stories_id as processed";
        }
    }

    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
