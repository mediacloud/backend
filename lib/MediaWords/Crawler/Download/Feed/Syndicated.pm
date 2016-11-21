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
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;

use Data::Dumper;
use Date::Parse;
use Encode;
use MediaWords::Feed::Parse;
use Readonly;

# check whether the checksum of the concatenated urls of the stories in the feed matches the last such checksum for this
# feed.  If the checksums don't match, store the current checksum in the feed
sub _stories_checksum_matches_feed
{
    my ( $db, $feeds_id, $stories ) = @_;

    my $story_url_concat = join( '|', map { $_->{ url } } @{ $stories } );

    my $checksum = Digest::MD5::md5_hex( encode( 'utf8', $story_url_concat ) );

    my ( $matches ) = $db->query(
        <<SQL,
        SELECT 1
        FROM feeds
        WHERE feeds_id = ?
          AND last_checksum = ?
SQL
        $feeds_id, $checksum
    )->flat;

    return 1 if ( $matches );

    $db->query( 'UPDATE feeds SET last_checksum = ? WHERE feeds_id = ?', $checksum, $feeds_id );

    return 0;
}

# parse the feed content; create a story hash for each parsed story; check for a new url since the last
# feed download; if there is a new url, check whether each story is new, and if so add it to the database and
# ad a pending download for it.
# return new stories that were found in the feed.
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $media_id = MediaWords::DBI::Downloads::get_media_id( $db, $download );

    my $feed;
    eval { $feed = MediaWords::Feed::Parse::parse_feed( $decoded_content ); };
    if ( $@ )
    {
        die "Error processing feed for $download->{ url }: $@";
    }

    my $items = [ $feed->get_item ];

    my $stories = [];
    for my $item ( @{ $items } )
    {
        my $url = $item->link();
        unless ( $url )
        {
            next;
        }

        my $guid  = $item->guid_if_valid() || $url;
        my $title = $item->title           || '(no title)';
        my $description = $item->description;
        my $publish_date = $item->publish_date_sql() || $download->{ download_time };

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

    if ( _stories_checksum_matches_feed( $db, $download->{ feeds_id }, $stories ) )
    {
        return [];
    }

    my $new_stories = [ grep { MediaWords::DBI::Stories::is_new( $db, $_ ) } @{ $stories } ];

    my $story_ids = [];
    foreach my $story ( @{ $new_stories } )
    {
        MediaWords::DBI::Stories::add_story_and_content_download( $db, $story, $download );
        push( @{ $story_ids }, $story->{ stories_id } );
    }

    return $story_ids;
}

sub return_stories_to_be_extracted_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    # Syndicated feed itself is not a story of any sort, so nothing to extract
    # (stories from this feed will be extracted as 'content' downloads)
    return [];
}

1;
