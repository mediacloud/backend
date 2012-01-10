package MediaWords::Crawler::FeedHandler;
use MediaWords::CommonLibs;

use strict;
use warnings;

# MODULES

use Data::Dumper;
use Date::Parse;
use DateTime;
use Encode;
use FindBin;
use IO::Compress::Gzip;
use URI::Split;
use Switch;
use Carp;
use Perl6::Say;
use List::Util qw (max maxstr);
use Try::Tiny;

use Feed::Scrape::MediaWords;
use MediaWords::Crawler::BlogSpiderBlogHomeHandler;
use MediaWords::Crawler::BlogSpiderPostingHandler;
use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::Config;
use MediaWords::DBI::Stories;

# CONSTANTS

# max number of pages the handler will download for a single story
use constant MAX_PAGES => 10;

# STATICS

my $_feed_media_ids     = {};
my $_added_xml_enc_path = 0;

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
        die( "Error processing feed for $download->{ url } " );
    };
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
        my $url  = $item->link() || $item->guid();
        my $guid = $item->guid() || $item->link();

        if ( !$url && !$guid )
        {
            next ITEM;
        }

        $url =~ s/[\n\r\s]//g;

        my $publish_date;

        if ( $item->pubDate() )
        {
            $publish_date = DateTime->from_epoch( epoch => Date::Parse::str2time( $item->pubDate() ) )->datetime;
        }
        else
        {
            $publish_date = $download_time;
        }

        # if ( !$story )
        $num_new_stories++;

        my $description = ref( $item->description ) ? ( '' ) : ( $item->description || '' );

        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $media_id,
            publish_date => $publish_date,
            collect_date => DateTime->now->datetime,
            title        => $item->title() || '(no title)',
            description  => $description,
        };

        push @{ $ret }, $story;

    }

    return $ret;
}

sub _story_is_new
{
    my ( $dbs, $story ) = @_;

    my $db_story =
      $dbs->query( "select * from stories where guid = ? and media_id = ?", $story->{ guid }, $story->{ media_id } )->hash;

    if ( !$db_story )
    {

        my $date = DateTime->from_epoch( epoch => Date::Parse::str2time( $story->{ publish_date } ) );

        my $start_date = $date->subtract( hours => 12 )->iso8601();
        my $end_date = $date->add( hours => 12 )->iso8601();

      # TODO -- DRL not sure if assuming UTF-8 is a good idea but will experiment with this code from the gsoc_dsheets branch
        my $title;

        # This unicode decode may not be necessary! XML::Feed appears to at least /sometimes/ return
        # character strings instead of byte strings. Decoding a character string is an error. This code now
        # only fails if a non-ASCII byte-string is returned from XML::Feed.

        # very misleadingly named function checks for unicode character string
        # in perl's internal representation -- not a byte-string that contains UTF-8
        # data

        if ( Encode::is_utf8( $story->{ title } ) )
        {
            $title = $story->{ title };
        }
        else
        {

            # TODO: A utf-8 byte string is only highly likely... we should actually examine the HTTP
            #   header or the XML pragma so this doesn't explode when given another encoding.
            $title = decode( 'utf-8', $story->{ title } );
        }

        #say STDERR "Searching for story by title";

        $db_story = $dbs->query(
            "select * from stories where title = ? and media_id = ? " .
              "and publish_date between date '$start_date' and date '$end_date' for update",
            $title,
            $story->{ media_id }
        )->hash;
    }

    if ( !$db_story )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub _add_story_and_content_download
{
    my ( $dbs, $story, $parent_download ) = @_;

    eval {

        $story = $dbs->create( "stories", $story );
        MediaWords::DBI::Stories::update_rss_full_text_field( $dbs, $story );

    };

    #TODO handle race conditions differently
    if ( $@ )
    {

        # if we hit a race condition with another process having just inserted this guid / media_id,
        # just put the download back in the queue.  this is a lot better than locking stories
        if ( $@ =~ /unique constraint "stories_guid"/ )
        {
            $dbs->rollback;
            $dbs->query( "update downloads set state = 'pending' where downloads_id = ?",
                $parent_download->{ downloads_id } );
            die( "requeue '$parent_download->{url}' due to guid conflict '$story->{ url }'" );
        }
        else
        {
            print Dumper( $story );
            die( $@ );
        }
    }

    $dbs->find_or_create(
        'feeds_stories_map',
        {
            stories_id => $story->{ stories_id },
            feeds_id   => $parent_download->{ feeds_id }
        }
    );

    $dbs->create(
        'downloads',
        {
            feeds_id      => $parent_download->{ feeds_id },
            stories_id    => $story->{ stories_id },
            parent        => $parent_download->{ downloads_id },
            url           => $story->{ url },
            host          => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
            type          => 'content',
            sequence      => 1,
            state         => 'pending',
            priority      => $parent_download->{ priority },
            download_time => DateTime->now->datetime,
            extracted     => 'f'
        }
    );

}

sub add_feed_stories_and_downloads
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $stories = _get_stories_from_feed_contents( $dbs, $download, $decoded_content );

    my $new_stories = [ grep { _story_is_new( $dbs, $_ ) } @{ $stories } ];

    foreach my $story ( @$new_stories )
    {
        _add_story_and_content_download( $dbs, $story, $download );
    }

    my $num_new_stories = scalar( @{ $new_stories } );

    return $num_new_stories;
}

sub handle_feed_content
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $num_new_stories = add_feed_stories_and_downloads( $dbs, $download, $decoded_content ) ; 

    my $content_ref;
    if ( $num_new_stories > 0 )
    {
        $content_ref = \$decoded_content;
    }
    else
    {

        #say STDERR "No stories found";
        $content_ref = \"(redundant feed)";
    }

    MediaWords::DBI::Downloads::store_content( $dbs, $download, $content_ref );

    return;
}

1;
