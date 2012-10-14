#!/usr/bin/env perl

# periodically check for new media sources that have not had default feeds added to them and add the default feeds.
# look for feeds that are most likely to be real feeds.  If we find more than one but no more than MAX_DEFAULT_FEEDS
# of those feeds, use the first such one and do not moderate the source.  Else, do a more expansive search
# and mark for moderation.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use constant MAX_DEFAULT_FEEDS => 4;

use DBIx::Simple::MediaWords;
use Feed::Scrape::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    while ( 1 )
    {
        my $db = MediaWords::DB::connect_to_db();

        my $media = $db->query( "select * from media where feeds_added = false order by media_id" )->hashes;

        for my $medium ( @{ $media } )
        {
            my $existing_urls = [];

            # first look for <link> feeds or a set of url pattern feeds that are likely to be
            # main feeds if present (like "$url/feed")
            my $default_feed_links = Feed::Scrape->get_main_feed_urls_from_url( $medium->{ url } );

            # otherwise do an expansive search
            my $feed_links;
            my $need_to_moderate;
            if ( !@{ $default_feed_links } )
            {
                $need_to_moderate = 1;
                $feed_links =
                  Feed::Scrape::MediaWords->get_valid_feeds_from_index_url( $medium->{ url }, 1, $db, [], $existing_urls );

                # look through all feeds found for those with the host name in them and if found
                # treat them as default feeds
                my $medium_host = lc( URI->new( $medium->{ url } )->host );
                $default_feed_links = [ grep { lc( URI->new( $_->{ url } )->host ) eq $medium_host } @{ $feed_links } ];
                $default_feed_links = [ grep { $_->{ url } !~ /foaf/ } @{ $default_feed_links } ];
            }

            # if there are more than 0 default feeds, use those.  If there are no more than
            # MAX_DEFAULT_FEEDS, use the first one and don't moderate.
            if ( @{ $default_feed_links } )
            {
                $default_feed_links = [ sort { length( $a->{ url } ) <=> length( $b->{ url } ) } @{ $default_feed_links } ];
                $default_feed_links = [ $default_feed_links->[ 0 ] ] if ( @{ $default_feed_links } <= MAX_DEFAULT_FEEDS );
                $feed_links         = $default_feed_links;
                $need_to_moderate   = 0;
            }

            for my $feed_link ( @{ $feed_links } )
            {
                print "ADDED $medium->{ name }: $feed_link->{ name } - $feed_link->{ url }\n";
                my $feed = { name => $feed_link->{ name }, url => $feed_link->{ url }, media_id => $medium->{ media_id } };
                eval { $db->create( 'feeds', $feed ); };

                if ( $@ )
                {
                    my $error = "Error adding feed $feed_link->{ url }: $@\n";
                    $medium->{ moderation_notes } .= $error;
                    print $error;
                    next;
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
                "update media set feeds_added = true, moderation_notes = ?, moderated =  ? where media_id = ?",
                $medium->{ moderation_notes },
                $moderated, $medium->{ media_id }
            );

        }

        $db->disconnect;

        sleep( 60 );
    }
}

main();
