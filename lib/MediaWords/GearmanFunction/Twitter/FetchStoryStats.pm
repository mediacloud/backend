package MediaWords::GearmanFunction::Twitter::FetchStoryStats;

#
# Fetch story's tweet count statistics via Twitter API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Twitter/FetchStoryStats.pm
#

use strict;
use warnings;

use Moose;

# Don't log each and every job into the database
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
use MediaWords::Util::Twitter;
use MediaWords::Util::Process;
use MediaWords::Util::GearmanJobSchedulerConfiguration;
use Readonly;
use Data::Dumper;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    say STDERR "Fetching story stats for story $stories_id...";
    eval {

        my $stories_url = $story->{ url };
        unless ( $stories_url )
        {
            die "Story URL for story ID $stories_id is empty.";
        }
        say STDERR "Story URL: $stories_url";

        my $count = MediaWords::Util::Twitter::get_and_store_tweet_count( $db, $story );
        say STDERR "url_tweet_count: $count";
    };
    if ( $@ )
    {
        say STDERR "Twitter helper died while fetching and storing statistics: $@";
    }
    else
    {
        say STDERR "Done fetching story stats for story $stories_id.";
    }
}

# write a single log because there are a lot of Bit.ly processing jobs so it's
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

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
