package MediaWords::Crawler::Download::Feed::Syndicated;

#
# Handler for 'syndicated' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::DefaultFetcher', 'MediaWords::Crawler::Download::FeedHandler';

use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::SQL;

use Data::Dumper;
use Date::Parse;
use Encode;
use Feed::Scrape::MediaWords;
use Readonly;
use URI::Split;

Readonly my $EXTERNAL_FEED_URL  => 'http://external/feed/url';
Readonly my $EXTERNAL_FEED_NAME => 'EXTERNAL FEED';

# if $v is a scalar, return $v, else return undef.
# we need to do this to make sure we don't get a ref back from a feed object field
sub _no_ref
{
    my ( $v ) = @_;

    return ref( $v ) ? undef : $v;
}

# some guids are not in fact unique.  return the guid if it looks valid or undef if the guid looks like
# it is not unique
sub _sanitize_guid
{
    my ( $guid ) = @_;

    return undef unless ( defined( $guid ) );

    # ignore it if it is a url without a number or a path
    if ( ( $guid !~ /\d/ ) && ( $guid =~ m~https?://[^/]+/?$~ ) )
    {
        return undef;
    }

    return $guid;
}

# parse the feed.  return a (non-db-backed) story hash for each story found in the feed.
sub _get_stories_from_feed_contents
{
    my ( $decoded_content, $media_id, $download_time ) = @_;

    my $feed = Feed::Scrape::MediaWords->parse_feed( $decoded_content );

    die( "Unable to parse feed" ) unless $feed;

    my $items = [ $feed->get_item ];

    my $ret = [];

  ITEM:
    for my $item ( @{ $items } )
    {
        my $guid = _sanitize_guid( _no_ref( $item->guid ) );

        my $url = _no_ref( $item->link() ) || _no_ref( $item->get( 'nnd:canonicalUrl' ) ) || $guid;
        $guid ||= $url;

        next ITEM unless ( $url );

        $url  = substr( $url,  0, 1024 );
        $guid = substr( $guid, 0, 1024 );

        $url =~ s/[\n\r\s]//g;

        my $publish_date;

        if ( my $date_string = _no_ref( $item->pubDate() ) )
        {
            # Date::Parse is more robust at parsing date than postgres
            eval {
                $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( Date::Parse::str2time( $date_string ) ); };
            if ( $@ )
            {
                $publish_date = $download_time;
                WARN "Error getting date from item pubDate ('" . $item->pubDate() . "') just using download time: $@";
            }
        }
        else
        {
            $publish_date = $download_time;
        }

        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $media_id,
            publish_date => $publish_date,
            title        => _no_ref( $item->title ) || '(no title)',
            description  => _no_ref( $item->description ),
        };

        push @{ $ret }, $story;
    }

    return $ret;
}

# if the story is new, add story to the database with the feed of the download as story feed
sub _add_story_using_parent_download
{
    my ( $db, $story, $parent_download ) = @_;

    $db->begin;
    $db->query( "lock table stories in row exclusive mode" );
    if ( !MediaWords::DBI::Stories::is_new( $db, $story ) )
    {
        $db->commit;
        return;
    }

    eval { $story = $db->create( "stories", $story ); };

    if ( $@ )
    {

        $db->rollback;

        if ( $@ =~ /unique constraint \"stories_guid/ )
        {
            WARN "Failed to add story for '." . $story->{ url } . "' to guid conflict ( guid =  '" . $story->{ guid } . "')";

            return;
        }
        else
        {
            die( "error adding story: $@\n" . Dumper( $story ) );
        }
    }

    MediaWords::DBI::Stories::update_rss_full_text_field( $db, $story );

    $db->find_or_create(
        'feeds_stories_map',
        {
            stories_id => $story->{ stories_id },
            feeds_id   => $parent_download->{ feeds_id }
        }
    );

    $db->commit;

    return $story;
}

# create a pending download for the story's url
sub _create_child_download_for_story
{
    my ( $db, $story, $parent_download ) = @_;

    my $download = {
        feeds_id   => $parent_download->{ feeds_id },
        stories_id => $story->{ stories_id },
        parent     => $parent_download->{ downloads_id },
        url        => $story->{ url },
        host       => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
        type       => 'content',
        sequence   => 1,
        state      => 'pending',
        priority   => $parent_download->{ priority },
        extracted  => 'f'
    };

    my ( $content_delay ) = $db->query( "select content_delay from media where media_id = ?", $story->{ media_id } )->flat;
    if ( $content_delay )
    {
        # delay download of content this many hours.  this is useful for sources that are likely to
        # significantly change content in the hours after it is first published.
        $download->{ download_time } = \"now() + interval '$content_delay hours'";
    }

    $db->create( 'downloads', $download );
}

# if the story is new, add it to the database and also add a pending download for the story content
sub _add_story_and_content_download
{
    my ( $db, $story, $parent_download ) = @_;

    $story = _add_story_using_parent_download( $db, $story, $parent_download );

    if ( defined( $story ) )
    {
        _create_child_download_for_story( $db, $story, $parent_download );
    }
}

# check whether the checksum of the concatenated urls of the stories in the feed matches the last such checksum for this
# feed.  If the checksums don't match, store the current checksum in the feed
sub _stories_checksum_matches_feed
{
    my ( $db, $feeds_id, $stories ) = @_;

    my $story_url_concat = join( '|', map { $_->{ url } } @{ $stories } );

    my $checksum = Digest::MD5::md5_hex( encode( 'utf8', $story_url_concat ) );

    my ( $matches ) = $db->query( <<END, $feeds_id, $checksum )->flat;
select 1 from feeds where feeds_id = ? and last_checksum = ?
END

    return 1 if ( $matches );

    $db->query( "update feeds set last_checksum = ? where feeds_id = ?", $checksum, $feeds_id );

    return 0;
}

=head2 import_external_feed( $db, $media_id, $feed_content )

Given the content of some feed, import all new stories from that content as if we had downloaded the content.
Associate any stories in the feed with a feed (created if needed) named $EXTERNAL_FEED_NAME in the given media source.
import stories from external feed into the given media source.

This is useful for scripts that need to import archived feed content from a non-http source or that need to create
a custom feed to import a list of stories from some archived source.

=cut

sub import_external_feed
{
    my ( $db, $media_id, $feed_content ) = @_;

    my $feed = $db->query( "select * from feeds where media_id = ? and name = ?", $media_id, $EXTERNAL_FEED_NAME )->hash;

    $feed ||= $db->create(
        'feeds',
        {
            media_id    => $media_id,
            name        => $EXTERNAL_FEED_NAME,
            url         => $EXTERNAL_FEED_URL,
            feed_status => 'inactive'
        }
    );

    my $download = $db->create(
        'downloads',
        {
            url           => $EXTERNAL_FEED_URL,
            feeds_id      => $feed->{ feeds_id },
            host          => 'external',
            download_time => \'now()',
            type          => 'feed',
            state         => 'fetching',
            priority      => 1,
            sequence      => 1
        }
    );

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );
    $handler->handle_download( $db, $download, $feed_content );
}

# parse the feed content; create a story hash for each parsed story; check for a new url since the last
# feed download; if there is a new url, check whether each story is new, and if so add it to the database and
# ad a pending download for it.
# return new stories that were found in the feed.
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $media_id = MediaWords::DBI::Downloads::get_media_id( $db, $download );
    my $download_time = $download->{ download_time };

    my $stories;
    eval { $stories = _get_stories_from_feed_contents( $decoded_content, $media_id, $download_time ); };
    if ( $@ )
    {
        die "Error processing feed for $download->{ url }: $@";
    }

    if ( _stories_checksum_matches_feed( $db, $download->{ feeds_id }, $stories ) )
    {
        return [];
    }

    my $new_stories = [ grep { MediaWords::DBI::Stories::is_new( $db, $_ ) } @{ $stories } ];

    my $story_ids = [];
    foreach my $story ( @{ $new_stories } )
    {
        _add_story_and_content_download( $db, $story, $download );
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
