package MediaWords::DBI::Media;

#
# Various helper functions relating to media.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Feed::Parse;
use MediaWords::Util::Web::UserAgent;

use Readonly;

# add a feed with the given url to the medium if the feed does not already exist and
# if the feed validates
sub add_feed_url_to_medium
{
    my ( $db, $medium, $feed_url ) = @_;

    my $feed_exists = $db->query( <<SQL,
        SELECT *
        FROM feeds
        WHERE
            media_id = ? AND
            LOWER(url) = LOWER(?)
SQL
        $medium->{ media_id }, $feed_url
    )->hash;

    return if $feed_exists;

    eval {
        my $ua = MediaWords::Util::Web::UserAgent->new();
        $ua->set_timeout( 30 );
        my $response = $ua->get( $feed_url );

        unless ( $response->is_success() ) {
            die "Unable to fetch feed: " . $response->status_line();
        }

        my $feed_xml = $response->decoded_content();
        my $parsed_feed = undef;
        eval {
            $parsed_feed = MediaWords::Feed::Parse::parse_feed( $feed_xml );
        };
        if ( $@ ) {
            die "Parsing failed: $@";
        }

        unless ( $parsed_feed ) {
            die "Parsed feed is empty, probably the parsing failed.";
        }
    };
    if ( $@ ) {
        WARN "Unable to add feed from URL $feed_url: $@";
        return;
    }

    $db->create(
        'feeds',
        {
            media_id => $medium->{ media_id },
            name => 'csv imported feed',
            url => $feed_url,
        }
    );
}

# Return true if the media sources has enough stories or is old enough that we
# are ready to analyze it for primary language, geo tagging, etc.
#
# Use the following rules to determine if the media source is ready:
#
# * return true if the medium has an active feed and more than 100 stories;
#
# * return false otherwise
sub medium_is_ready_for_analysis($$)
{
    my ( $db, $medium ) = @_;

    my $media_id = $medium->{ media_id };

    my $active_feed = $db->query( <<SQL,
        SELECT 1
        FROM feeds
        WHERE
            active = 't' AND
            media_id = \$1
SQL
        $media_id
    )->hash;

    return 0 unless ( $active_feed );

    my $first_story = $db->query( <<SQL,
        SELECT *
        FROM stories
        WHERE media_id = ?
        LIMIT 1
SQL
        $media_id
    )->hash;

    return 0 unless ( $first_story );

    my $story_101 = $db->query( <<SQL,
        SELECT *
        FROM stories
        WHERE media_id = ?
        OFFSET 101
        LIMIT 1
SQL
        $media_id
    )->hash;

    return $story_101 ? 1 : 0;
}

1;
