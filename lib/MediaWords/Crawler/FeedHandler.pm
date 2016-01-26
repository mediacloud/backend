package MediaWords::Crawler::FeedHandler;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

# MODULES

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

# METHODS

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

sub _get_stories_from_feed_contents_impl
{
    my ( $decoded_content, $media_id, $download_time ) = @_;

    my $feed = Feed::Scrape::MediaWords->parse_feed( $decoded_content );

    die( "Unable to parse feed" ) unless $feed;

    my $items = [ $feed->get_item ];

    my $num_new_stories = 0;

    my $ret = [];

  ITEM:
    for my $item ( @{ $items } )
    {

        my $url = _no_ref( $item->link() ) || _no_ref( $item->get( 'nnd:canonicalUrl' ) ) || _no_ref( $item->guid() );
        my $guid = _no_ref( $item->guid() ) || $url;

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

        # if ( !$story )
        $num_new_stories++;

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

sub _add_story_using_parent_download
{
    my ( $dbs, $story, $parent_download ) = @_;

    #say STDERR "starting _add_story_using_parent_download ";
    #say STDERR Dumper( $story );

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

sub _add_story_and_content_download
{
    my ( $dbs, $story, $parent_download ) = @_;

    $story = _add_story_using_parent_download( $dbs, $story, $parent_download );

    if ( defined( $story ) )
    {
        _create_child_download_for_story( $dbs, $story, $parent_download );
    }
}

# check whether the checksum of the concatenated urls of the stories in the feed matches
# the last such checksum for this feed.  If the checksums don't match, store the current
# checksum in the feed
sub stories_checksum_matches_feed
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

sub add_feed_stories_and_downloads
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $stories = _get_stories_from_feed_contents( $dbs, $download, $decoded_content );

    return 0 if ( stories_checksum_matches_feed( $dbs, $download->{ feeds_id }, $stories ) );

    my $new_stories = [ grep { MediaWords::DBI::Stories::is_new( $dbs, $_ ) } @{ $stories } ];

    foreach my $story ( @$new_stories )
    {
        _add_story_and_content_download( $dbs, $story, $download );
    }

    my $num_new_stories = scalar( @{ $new_stories } );

    return $num_new_stories;
}

# handle feeds of type 'web_page' by just creating a story to associate
# with the content
sub handle_web_page_content
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

# import stories from external feed into the given media source
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

    handle_syndicated_content( $db, $download, $feed_content );
}

# handle feeds of type 'syndicated', which are rss / atom / rdf feeds
sub handle_syndicated_content
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $num_new_stories = add_feed_stories_and_downloads( $dbs, $download, $decoded_content );

    if ( $num_new_stories > 0 )
    {
        $dbs->query( "UPDATE feeds set last_new_story_time = last_attempted_download_time where feeds_id = ? ",
            $download->{ feeds_id } );
    }

    return ( $num_new_stories > 0 ) ? \$decoded_content : \"(redundant feed)";
}

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
            $content_ref = handle_syndicated_content( $dbs, $download, $decoded_content );

        }
        elsif ( $feed_type eq 'web_page' )
        {
            $content_ref = handle_web_page_content( $dbs, $download, $decoded_content, $feed );

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
        say STDERR $error_message;
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
