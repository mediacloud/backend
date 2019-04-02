#!mjm_worker.pl

package MediaWords::Job::Facebook::FetchStoryStats;

#
# Fetch story's share count statistics via Facebook's Graph API
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Config::Facebook;
use MediaWords::Util::Facebook;
use MediaWords::Util::Process;
use Readonly;
use Data::Dumper;

# Run job
sub run($;$)
{
    my ( $class, $args ) = @_;

    unless ( MediaWords::Util::Config::Facebook::is_enabled() )
    {
        fatal_error( 'Facebook API processing is not enabled.' );
    }

    my $db = MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    INFO "Fetching story stats for story $stories_id...";
    eval {

        my $stories_url = $story->{ url };
        unless ( $stories_url )
        {
            die "Story URL for story ID $stories_id is empty.";
        }
        DEBUG "Story URL: $stories_url";

        my ( $share_count, $comment_count ) = MediaWords::Util::Facebook::get_and_store_share_comment_counts( $db, $story );
        DEBUG "share count: $share_count, comment count: $comment_count";
    };
    if ( $@ )
    {
        die "Facebook helper died while fetching and storing statistics: $@";
    }
    else
    {
        INFO "Done fetching story stats for story $stories_id.";
    }
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
