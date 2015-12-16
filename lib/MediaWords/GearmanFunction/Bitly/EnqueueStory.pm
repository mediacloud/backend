package MediaWords::GearmanFunction::Bitly::EnqueueStory;

#
# Enqueue a single story for processing via Bit.ly API based on its "publish_date"
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/EnqueueStory.pm
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
use MediaWords::Util::GearmanJobSchedulerConfiguration;
use MediaWords::Util::Bitly;
use MediaWords::Util::DateTime;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;
use MediaWords::GearmanFunction::Bitly::FetchStoryURLStats;
use Readonly;
use DateTime;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# Don't fetch data for stories older than this date
sub _publish_timestamp_lower_bound()
{
    return DateTime->new( year => 2008, month => 01, day => 01 )->epoch;
}

# Don't fetch data for stories newer than this date
sub _publish_timestamp_upper_bound()
{
    return DateTime->now()->epoch;
}

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    say STDERR "Will enqueue story $stories_id for Bit.ly processing.";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story $stories_id was not found";
    }

    my $stories_url          = $story->{ url };
    my $stories_publish_date = $story->{ publish_date };

    unless ( $stories_url )
    {
        die "URL is unset for story $stories_id";
    }
    unless ( MediaWords::Util::URL::is_http_url( $stories_url ) )
    {
        die "URL '$stories_url' is not a HTTP(S) URL for story $stories_id";
    }

    unless ( $stories_publish_date )
    {
        die "Publish date is unset for story $stories_id";
    }

    my $publish_timestamp = MediaWords::Util::SQL::get_epoch_from_sql_date( $stories_publish_date );
    if ( $publish_timestamp <= _publish_timestamp_lower_bound() )
    {
        die "Publish timestamp is lower than the lower bound for story $stories_id";
    }
    if ( $publish_timestamp >= _publish_timestamp_upper_bound() )
    {
        die "Publish timestamp is bigger than the upper bound for story $stories_id";
    }

    # Round timestamp to the nearest day because that's what Bitly.pm does
    my $publish_datetime = gmt_datetime_from_timestamp( $publish_timestamp );
    $publish_datetime->set( hour => 0, minute => 0, second => 0 );
    $publish_timestamp = $publish_datetime->epoch;

    # Span across ~300 days
    my $start_timestamp = $publish_timestamp - ( 60 * 60 * 24 * 150 );
    my $end_timestamp   = $publish_timestamp + ( 60 * 60 * 24 * 150 );

    say STDERR "Enqueueing story $stories_id for Bit.ly processing (start TS: $start_timestamp, end TS: $end_timestamp)...";

    MediaWords::GearmanFunction::Bitly::FetchStoryURLStats->enqueue_on_gearman(
        {
            stories_id      => $stories_id,
            start_timestamp => $start_timestamp,
            end_timestamp   => $end_timestamp
        }
    );

    say STDERR "Done enqueueing story $stories_id for Bit.ly processing.";
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
