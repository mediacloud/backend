package MediaWords::Crawler::Download::Feed::Syndicated;

#
# Handler for 'syndicated' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Download::DefaultFetcher', 'MediaWords::Crawler::Download::Feed::FeedHandler';

use MediaWords::Crawler::Engine;
use MediaWords::DBI::Downloads::Store;
use MediaWords::DBI::Feeds;
use MediaWords::DBI::Stories;

use Data::Dumper;
use Date::Parse;
use Encode;
use MediaWords::Feed::Parse;
use Readonly;

# parse the feed.  return a (non-db-backed) story hash for each story found in the feed.
sub _get_stories_from_syndicated_feed($$$)
{
    my ( $decoded_content, $media_id, $download_time ) = @_;

    my $feed = MediaWords::Feed::Parse::parse_feed( $decoded_content );

    die( "Unable to parse feed" ) unless $feed;

    my $stories = [];

    for my $item ( @{ $feed->items() } )
    {
        my $url = $item->link();
        next unless ( $url );

        die( "url is a ref: " . Dumper( $url ) ) if ( ref( $url ) );

        my $guid  = $item->guid_if_valid() || $url;
        my $title = $item->title           || '(no title)';
        my $description = $item->description;
        my $publish_date = $item->publish_date_sql() || $download_time;

        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $media_id,
            publish_date => $publish_date,
            title        => $title,
            description  => $description,
        };

        push( @{ $stories }, $story );
    }

    return $stories;
}

# parse the feed content; create a story hash for each parsed story; check for a new url since the last
# feed download; if there is a new url, check whether each story is new, and if so add it to the database and
# ad a pending download for it.
# return new stories that were found in the feed.
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $media_id = MediaWords::DBI::Downloads::Store::get_media_id( $db, $download );
    my $download_time = $download->{ download_time };

    my $stories;
    eval { $stories = _get_stories_from_syndicated_feed( $decoded_content, $media_id, $download_time ); };
    if ( $@ )
    {
        die "Error processing feed for $download->{ url }: $@";
    }

    if ( MediaWords::DBI::Feeds::stories_checksum_matches_feed( $db, $download->{ feeds_id }, $stories ) )
    {
        return [];
    }

    my $new_story_ids = [];
    foreach my $story ( @{ $stories } )
    {
        $story = MediaWords::DBI::Stories::add_story_and_content_download( $db, $story, $download );
        push( @{ $new_story_ids }, $story->{ stories_id } ) if ( $story->{ is_new } );
    }

    TRACE( "add_stories_from_feed: new stories: " . scalar( @{ $new_story_ids } ) . " / " . scalar( @{ $stories } ) );

    return $new_story_ids;
}

sub return_stories_to_be_extracted_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    # Syndicated feed itself is not a story of any sort, so nothing to extract
    # (stories from this feed will be extracted as 'content' downloads)
    return [];
}

1;
