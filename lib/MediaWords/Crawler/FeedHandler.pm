package MediaWords::Crawler::FeedHandler;
use Modern::Perl "2012";
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
use Carp;

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
        die( "Error processing feed for $download->{ url }: $_ " );
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
            try
            {
                my $date_string = $item->pubDate();

                $date_string =~ s/(\d\d\d\d-\d\d-\d\dT\d\d\:\d\d\:\d\d)-\d\d\d\:\d\d/$1/;

                $publish_date = DateTime->from_epoch( epoch => Date::Parse::str2time( $date_string ) )->datetime;
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

sub _add_story_using_parent_download
{
    my ( $dbs, $story, $parent_download ) = @_;

    #say STDERR "starting _add_story_using_parent_download ";
    #say STDERR Dumper( $story );

    try
    {
        $story = $dbs->create( "stories", $story );
    }
    catch
    {

        #TODO handle race conditions differently
        if ( $_ =~ /unique constraint "stories_guid"/ )
        {
            warn "failed to add story for '." . $story->{ url } . "' to guid conflict ( guid =  '" . $story->{ guid } . "')";

            return;
        }
        else
        {
            say STDERR 'error adding story dying';
            say STDERR Dumper( $story );
            die( $_ );
        }
    };

    MediaWords::DBI::Stories::update_rss_full_text_field( $dbs, $story );

    $dbs->find_or_create(
        'feeds_stories_map',
        {
            stories_id => $story->{ stories_id },
            feeds_id   => $parent_download->{ feeds_id }
        }
    );

    return $story;
}

sub _create_child_download_for_story
{
    my ( $dbs, $story, $parent_download ) = @_;

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

sub _add_story_and_content_download
{
    my ( $dbs, $story, $parent_download ) = @_;

    $story = _add_story_using_parent_download( $dbs, $story, $parent_download );

    if ( defined( $story ) )
    {
        _create_child_download_for_story( $dbs, $story, $parent_download );
    }
}

sub add_feed_stories_and_downloads
{
    my ( $dbs, $download, $decoded_content ) = @_;

    my $stories = _get_stories_from_feed_contents( $dbs, $download, $decoded_content );

    my $new_stories = [ grep { MediaWords::DBI::Stories::is_new( $dbs, $_ ) } @{ $stories } ];

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

    my $num_new_stories = add_feed_stories_and_downloads( $dbs, $download, $decoded_content );

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
