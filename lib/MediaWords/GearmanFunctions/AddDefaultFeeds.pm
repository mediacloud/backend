package MediaWords::GearmanFunctions::AddDefaultFeeds;

#
# periodically check for new media sources that have not had default feeds added to them and add the default feeds.
# look for feeds that are most likely to be real feeds.  If we find more than one but no more than MAX_DEFAULT_FEEDS
# of those feeds, use the first such one and do not moderate the source.  Else, do a more expansive search
# and mark for moderation.
#
# start with:
#
# /script/run_with_carton.sh ./script/gjs_worker.pl lib/MediaWords/GearmanFunctions/AddDefaultFeeds.pm
#

use strict;
use warnings;

use Moose;
with 'Gearman::JobScheduler::AbstractFunction';

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use Feed::Scrape::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    my $media = $db->query( "select * from media where feeds_added = false order by media_id" )->hashes;

    for my $medium ( @{ $media } )
    {
        my ( $feed_links, $need_to_moderate, $existing_urls ) =
          Feed::Scrape::get_feed_links_and_need_to_moderate_and_existing_urls( $db, $medium );

        for my $feed_link ( @{ $feed_links } )
        {
            my $feed = {
                name        => $feed_link->{ name },
                url         => $feed_link->{ url },
                media_id    => $medium->{ media_id },
                feed_type   => $feed_link->{ feed_type } || 'syndicated',
                feed_status => $need_to_moderate ? 'inactive' : 'active',
            };

            eval { $db->create( 'feeds', $feed ); };

            if ( $@ )
            {
                my $error = "Error adding feed $feed_link->{ url }: $@\n";
                $medium->{ moderation_notes } .= $error;
                print $error;
                next;
            }
            else
            {
                say STDERR "ADDED $medium->{ name }: $feed->{ name } " .
                  "[$feed->{ feed_type }, $feed->{ feed_status }]" . " - $feed->{ url }\n";
            }
        }

        if ( @{ $existing_urls } )
        {
            my $error = "These urls were found but already exist in the database:\n" .
              join( "\n", map { "\t$_" } @{ $existing_urls } ) . "\n";
            $medium->{ moderation_notes } .= $error;
            print $error;
        }

        my $moderated = $need_to_moderate ? 'f' : 't';

        $db->query(
            "update media set feeds_added = true, moderation_notes = ?, moderated = ? where media_id = ?",
            $medium->{ moderation_notes },
            $moderated, $medium->{ media_id }
        );

    }

    $db->disconnect;
}

# Don't allow two or more jobs with the same parameters to run at once?
sub unique()
{
    # The effect of the "uniqueness" of this job is that only a single instance
    # of add_default_feeds() will be run at a time
    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
