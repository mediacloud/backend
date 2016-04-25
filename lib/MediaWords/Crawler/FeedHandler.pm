package MediaWords::Crawler::FeedHandler;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::FeedHandler - implementation details of the feed handling called from MediaWords::Crawler::Handler

=head1 DESCRIPTION

The feed handler parses the feed and looks for the urls of any new stories.  A story is considered new if the url or
guid is not already in the database for the given media source and if the story title is unique for the media source for
the calendar week.  If the story is new, a story is added to the stories table and a download with a type of 'pending'
is added to the downloads table.

After parsing the feed but before checking for new stories, we generate a checksum of the sorted urls of the feed.  We
check that checksum against the last_checksum value of the feed, and if the value is the same, we store '(redundant
feed)' as the content of the feed and do not check for new stories.  This check prevents frequent storage of redundant
feed content and also avoids the considerable processing time required to check individual urls for new stories.

=cut

use strict;
use warnings;

use Carp;
use Data::Dumper;
use Date::Parse;
use DateTime;
use Encode;
use FindBin;
use Readonly;
use URI::Split;

use List::Util qw (max maxstr);
use Try::Tiny;

use Feed::Scrape::MediaWords;
use MediaWords::Crawler::Pager;
use MediaWords::GearmanFunction::ExtractAndVector;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::Util::SQL;

# CONSTANTS

Readonly my $EXTERNAL_FEED_URL  => 'http://external/feed/url';
Readonly my $EXTERNAL_FEED_NAME => 'EXTERNAL FEED';

=head1 METHODS

=cut

# try/catch wrapper for _get_stories_from_feed_content_impl
sub _get_stories_from_feed_contents
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $media_id = MediaWords::DBI::Downloads::get_media_id( $dbs, $download );
    my $download_time = $download->{ download_time };

    return try
    {
        return _get_stories_from_feed_contents_impl( $decoded_content, $media_id, $download_time );
    }
    catch
    {
        die( "Error processing feed for $download->{ url }: $_ " );
    };
}

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
sub _get_stories_from_feed_contents_impl
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
            try
            {
                $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( Date::Parse::str2time( $date_string ) );
            }
            catch
            {
                $publish_date = $download_time;
                warn "Error getting date from item pubDate ('" . $item->pubDate() . "') just using download time:$_";
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
    my ( $dbs, $story, $parent_download ) = @_;

    $dbs->begin;
    $dbs->query( "lock table stories in row exclusive mode" );
    if ( !MediaWords::DBI::Stories::is_new( $dbs, $story ) )
    {
        $dbs->commit;
        return;
    }

    eval { $story = $dbs->create( "stories", $story ); };

    if ( $@ )
    {

        $dbs->rollback;

        if ( $@ =~ /unique constraint \"stories_guid/ )
        {
            warn "failed to add story for '." . $story->{ url } . "' to guid conflict ( guid =  '" . $story->{ guid } . "')";

            return;
        }
        else
        {
            die( "error adding story: $@\n" . Dumper( $story ) );
        }
    }

    MediaWords::DBI::Stories::update_rss_full_text_field( $dbs, $story );

    $dbs->find_or_create(
        'feeds_stories_map',
        {
            stories_id => $story->{ stories_id },
            feeds_id   => $parent_download->{ feeds_id }
        }
    );

    $dbs->commit;

    return $story;
}

# create a pending download for the story's url
sub _create_child_download_for_story
{
    my ( $dbs, $story, $parent_download ) = @_;

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

    my ( $content_delay ) = $dbs->query( "select content_delay from media where media_id = ?", $story->{ media_id } )->flat;
    if ( $content_delay )
    {
        # delay download of content this many hours.  this is useful for sources that are likely to
        # significantly change content in the hours after it is first published.
        $download->{ download_time } = \"now() + interval '$content_delay hours'";
    }

    $dbs->create( 'downloads', $download );
}

# if the story is new, add it to the database and also add a pending download for the story content
sub _add_story_and_content_download
{
    my ( $dbs, $story, $parent_download ) = @_;

    $story = _add_story_using_parent_download( $dbs, $story, $parent_download );

    if ( defined( $story ) )
    {
        _create_child_download_for_story( $dbs, $story, $parent_download );
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

# parse the feed content; create a story hash for each parsed story; check for a new url since the last
# feed download; if there is a new url, check whether each story is new, and if so add it to the database and
# ad a pending download for it.  return the number of new stories added.
sub _add_feed_stories_and_downloads
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $stories = _get_stories_from_feed_contents( $dbs, $download, $decoded_content );

    return 0 if ( _stories_checksum_matches_feed( $dbs, $download->{ feeds_id }, $stories ) );

    my $new_stories = [ grep { MediaWords::DBI::Stories::is_new( $dbs, $_ ) } @{ $stories } ];

    foreach my $story ( @$new_stories )
    {
        _add_story_and_content_download( $dbs, $story, $download );
    }

    my $num_new_stories = scalar( @{ $new_stories } );

    return $num_new_stories;
}

# handle feeds of type 'web_page' by just creating a story to associate with the content.  web page feeds are feeds
# that consist of a web page that we download once a week and add as a story.
sub _handle_web_page_content
{
    my ( $dbs, $download, $decoded_content, $feed ) = @_;

    my $title = MediaWords::Util::HTML::html_title( $decoded_content, '(no title)' );
    my $guid = substr( time . ":" . $download->{ url }, 0, 1024 );

    my $story = $dbs->create(
        'stories',
        {
            url          => $download->{ url },
            guid         => $guid,
            media_id     => $feed->{ media_id },
            publish_date => MediaWords::Util::SQL::sql_now,
            title        => $title
        }
    );

    $dbs->query(
        "insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )",
        $feed->{ feeds_id },
        $story->{ stories_id }
    );

    $dbs->query(
        "update downloads set stories_id = ?, type = 'content' where downloads_id = ?",
        $story->{ stories_id },
        $download->{ downloads_id }
    );

    $download->{ stories_id } = $story->{ stories_id };

    return \$decoded_content;
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

    MediaWords::DBI::Downloads::store_content( $db, $download, \$feed_content );

    _handle_syndicated_content( $db, $download, $feed_content );
}

# handle feeds of type 'syndicated', which are rss / atom / rdf feeds
sub _handle_syndicated_content
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $num_new_stories = _add_feed_stories_and_downloads( $dbs, $download, $decoded_content );

    if ( $num_new_stories > 0 )
    {
        $dbs->query( "UPDATE feeds set last_new_story_time = last_attempted_download_time where feeds_id = ? ",
            $download->{ feeds_id } );
    }

    return ( $num_new_stories > 0 ) ? \$decoded_content : \"(redundant feed)";
}

=head2 handle_feed_content( $db, $download, $decoded_content )

For web page feeds, just store the downloaded content as a story and queue the story for extraction.  For syndicated
feeds, create new stories for any new story urls in the feed content.  More details in the DESCRIPTION above.

Also store the content of the feed for the download and set the feed.last_successful_download_time to now.

=cut

sub handle_feed_content
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $content_ref = \$decoded_content;

    my $feed = $dbs->find_by_id( 'feeds', $download->{ feeds_id } );
    my $feed_type = $feed->{ feed_type };

    try
    {
        if ( $feed_type eq 'syndicated' )
        {
            $content_ref = _handle_syndicated_content( $dbs, $download, $decoded_content );

        }
        elsif ( $feed_type eq 'web_page' )
        {
            $content_ref = _handle_web_page_content( $dbs, $download, $decoded_content, $feed );

        }
        else
        {
            die( "Unknown feed type '$feed_type'" );

        }

    }
    catch
    {
        $download->{ state } = 'feed_error';
        my $error_message = "Error processing feed: $_";
        ERROR $error_message;
        $download->{ error_message } = $error_message;
    }
    finally
    {
        if ( $download->{ state } ne 'feed_error' )
        {
            $dbs->query(
"UPDATE feeds SET last_successful_download_time = greatest( last_successful_download_time, ? ) WHERE feeds_id = ?",
                $download->{ download_time },
                $download->{ feeds_id }
            );
        }

        MediaWords::DBI::Downloads::store_content( $dbs, $download, $content_ref );

        if ( $feed_type eq 'web_page' )
        {
            MediaWords::GearmanFunction::ExtractAndVector->extract_for_crawler( $dbs,
                { downloads_id => $download->{ downloads_id } }, 0 );
        }
    };

    return;
}

1;
