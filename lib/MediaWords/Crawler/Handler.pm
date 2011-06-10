package MediaWords::Crawler::Handler;

# process the fetched response for the crawler:
# * store the download in the database,
# * store the response content in the fs,
# * parse the response content to generate more downloads (eg. story urls from a feed download)
# * parse the response content to add story text to the database

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

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

    $self->{ blog_spider_handler }         = MediaWords::Crawler::BlogSpiderBlogHomeHandler->new( $self->engine );
    $self->{ blog_spider_posting_handler } = MediaWords::Crawler::BlogSpiderPostingHandler->new( $self->engine );
    return $self;
}

# parse the feed and add the resulting stories and content downloads to the database
sub _add_stories_and_content_downloads
{
    my ( $self, $dbs, $download, $decoded_content ) = @_;

    my $feed = Feed::Scrape::MediaWords->parse_feed( $decoded_content );

    die( "Unable to parse feed for $download->{ url }" ) unless $feed;

    my $items = [ $feed->get_item ];

    my $num_new_stories = 0;

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

        my $date = DateTime->from_epoch( epoch => Date::Parse::str2time( $item->pubDate() ) || time );

        my $media_id = MediaWords::DBI::Downloads::get_media_id( $dbs, $download );

        my $story = $dbs->query( "select * from stories where guid = ? and media_id = ?", $guid, $media_id )->hash;

        if ( !$story )
        {
            my $start_date = $date->subtract( hours => 12 )->iso8601();
            my $end_date = $date->add( hours => 12 )->iso8601();

      # TODO -- DRL not sure if assuming UTF-8 is a good idea but will experiment with this code form the gsoc_dsheets branch
            my $title;

            # This unicode decode may not be necessary! XML::Feed appears to at least /sometimes/ return
            # character strings instead of byte strings. Decoding a character string is an error. This code now
            # only fails if a non-ASCII byte-string is returned from XML::Feed.

            # very misleadingly named function checks for unicode character string
            # in perl's internal representation -- not a byte-string that contains UTF-8
            # data
            if ( Encode::is_utf8( $item->title ) )
            {
                $title = $item->title;
            }
            else
            {

                # TODO: A utf-8 byte string is only highly likely... we should actually examine the HTTP
                #   header or the XML pragma so this doesn't explode when given another encoding.
                $title = decode( 'utf-8', $item->title );
                if ( Encode::is_utf8( $item->title ) )
                {

                    # TODO: catch this
                    print STDERR "Feed " . $download->{ feeds_id } . " has inconsistent encoding for title:\n";
                    print STDERR "$title\n";
                }
            }
            $story = $dbs->query(
                "select * from stories where title = ? and media_id = ? " .
                  "and publish_date between date '$start_date' and date '$end_date' for update",
                $title, $media_id
            )->hash;
        }

        if ( !$story )
        {
            $num_new_stories++;
            my $dbs = $self->engine->dbs;

            eval {

                #Work around a bug in XML::FeedPP -
                #  Item description() will sometimes return a hash instead of text.
                # TODO fix XML::FeedPP
                my $description = ref( $item->description ) ? ( '' ) : ( $item->description || '' );

                $story = {
                    url          => $url,
                    guid         => $guid,
                    media_id     => $media_id,
                    publish_date => $date->datetime,
                    collect_date => DateTime->now->datetime,
                    title        => $item->title() || '(no title)',
                    description  => $description,
                };

                # say STDERR "create story: " . Dumper( $story );

                $story = $dbs->create( "stories", $story );
                MediaWords::DBI::Stories::update_rss_full_text_field( $dbs, $story );
            };

            if ( $@ )
            {

                # if we hit a race condition with another process having just inserted this guid / media_id,
                # just put the download back in the queue.  this is a lot better than locking stories
                if ( $@ =~ /unique constraint "stories_guid"/ )
                {
                    $dbs->rollback;
                    $dbs->query( "update downloads set state = 'pending' where downloads_id = ?",
                        $download->{ downloads_id } );
                    die( "requeue '$url' due to guid conflict" );
                }
                else
                {
                    print Dumper( $story );
                    die( $@ );
                }
            }
            else
            {
                $dbs->create(
                    'downloads',
                    {
                        feeds_id      => $download->{ feeds_id },
                        stories_id    => $story->{ stories_id },
                        parent        => $download->{ downloads_id },
                        url           => $url,
                        host          => lc( ( URI::Split::uri_split( $url ) )[ 1 ] ),
                        type          => 'content',
                        sequence      => 1,
                        state         => 'pending',
                        priority      => $download->{ priority },
                        download_time => DateTime->now->datetime,
                        extracted     => 'f'
                    }
                );
            }
        }

        if ( !$story ) { warn "skipping story"; next; }

        die "story undefined"                                       unless $story;
        confess "story id undefined for story: " . Dumper( $story ) unless defined( $story->{ stories_id } );
        die "feed undefined"                                        unless $download->{ feeds_id };

        $dbs->find_or_create(
            'feeds_stories_map',
            {
                stories_id => $story->{ stories_id },
                feeds_id   => $download->{ feeds_id }
            }
        );

        #FIXME - add meta keywords
    }

    return $num_new_stories;
}

sub _get_found_blogs_id
{
    my ( $self, $download ) = @_;

    my $blog_validation_downloads = $self->engine->dbs->query(
        'select * from blog_validation_downloads where downloads_id = ?',
        $download->{ downloads_id },
    );

    confess "no blog_validation_download for $download->{downloads_id} " unless $blog_validation_downloads;

    my $hash = $blog_validation_downloads->hash;

    #     say STDERR Dumper($blog_validation_downloads);
    #     say STDERR Dumper($download);
    #     say STDERR Dumper($hash);

    confess "no blog_validation_download hash for $download->{downloads_id} " . Dumper( $hash ) unless $hash;

    confess unless $hash->{ downloads_type } eq $download->{ type };

    return $hash->{ found_blogs_id };
}

# parse the feed and add the resulting stories and content downloads to the database
sub _store_last_rss_entry_time
{
    my ( $self, $download, $response ) = @_;

    my $items = $self->_get_feed_items( $download, \$response->content );

    return if scalar( @{ $items } ) == 0;

    my $entry_date = maxstr( map { $_->issued } @{ $items } );

    #say STDERR Dumper ( [ map { $_->issued . '' } @{$items} ] );
    #say STDERR "Max entry_date $entry_date";

    my $found_blogs_id = $self->_get_found_blogs_id( $download );

    $self->engine->dbs->query( "UPDATE found_blogs set last_entry = ? where found_blogs_id = ? ",
        $entry_date, $found_blogs_id );

}

# parse the feed and add the resulting stories and content downloads to the database
sub _add_spider_posting_downloads
{
    my ( $self, $download, $response ) = @_;

    my $items = $self->_get_feed_items( $download, \$response->decoded_content );

    $items = [ reverse @{ $items } ];

    my $added_posts = 0;
    my %post_urls;

    for my $item ( @{ $items } )
    {
        my $url = $item->link() || $item->guid();

        if ( !$url )
        {
            next;
        }

        $url =~ s/[\n\r\s]//g;

        next if ( $post_urls{ $url } );

        my $date = DateTime->from_epoch( epoch => Date::Parse::str2time( $item->pubDate() ) || time );

        $self->engine->dbs->create(
            'downloads',
            {
                feeds_id => $download->{ feeds_id },

                #stories_id    => $story->{stories_id},
                parent        => $download->{ downloads_id },
                url           => $url,
                host          => lc( ( URI::Split::uri_split( $url ) )[ 1 ] ),
                type          => 'spider_posting',
                sequence      => 1,
                state         => 'pending',
                priority      => 0,
                download_time => DateTime->now->datetime,
                extracted     => 'f'
            }
        );

        $post_urls{ $url } = 1;
        $added_posts++;

        last if $added_posts >= 10;
    }
}

# chop out the content if we don't allow the content type
sub _restrict_content_type
{
    my ( $self, $response ) = @_;

    if ( $response->content_type =~ m~text|html|xml|rss|atom~i )
    {
        return;
    }

    #if ($response->decoded_content =~ m~<html|<xml|<rss|<atom~i) {
    #    return;
    #}

    print "unsupported content type: " . $response->content_type . "\n";
    $response->content( '(unsupported content type)' );
}

# call get_page_urls from the pager module for the download's feed
sub _call_pager
{
    my ( $self, $dbs, $download, $response ) = @_;

    if ( $download->{ sequence } > MAX_PAGES )
    {
        print "reached max pages (" . MAX_PAGES . ") for url " . $download->{ url } . "\n";
        return;
    }

    # my $dbs = $self->engine->dbs;

    if ( $dbs->query( "SELECT * from downloads where parent = ? ", $download->{ downloads_id } )->hash )
    {
        print "story already paged for url " . $download->{ url } . "\n";
        return;
    }

    my $validate_url = sub { !$dbs->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    if ( my $next_page_url =
        MediaWords::Crawler::Pager->get_next_page_url( $validate_url, $download->{ url }, $response->decoded_content ) )
    {

        print "next page: $next_page_url\nprev page: " . $download->{ url } . "\n";

        $dbs->create(
            'downloads',
            {
                feeds_id      => $download->{ feeds_id },
                stories_id    => $download->{ stories_id },
                parent        => $download->{ downloads_id },
                url           => $next_page_url,
                host          => lc( ( URI::Split::uri_split( $next_page_url ) )[ 1 ] ),
                type          => 'content',
                sequence      => $download->{ sequence } + 1,
                state         => 'pending',
                priority      => $download->{ priority } + 1,
                download_time => DateTime->now->datetime,
                extracted     => 'f'
            }
        );
    }
}

sub _queue_author_extraction
{
    my ( $self, $download, $response ) = @_;

    if ( $download->{ sequence } > 1 )
    {

        #Only extractor author from the first page
        return;
    }

    my $dbs = $self->engine->dbs;

    my $download_media_source = MediaWords::DBI::Downloads::get_medium( $dbs, $download );

    if ( $download_media_source->{ extract_author } )
    {

        die Dumper( $download ) unless $download->{ state } eq 'success';

        $dbs->create(
            'authors_stories_queue',
            {
                stories_id => $download->{ stories_id },
                state      => 'queued',
            }
        );
    }

    say STDERR "queued story extraction";

    return;
}

# call the content module to parse the text from the html and add pending downloads
# for any additional content
sub _process_content
{
    my ( $self, $dbs, $download, $response ) = @_;

    $self->_call_pager( $dbs, $download, $response );

    $self->_queue_author_extraction( $download );

    #MediaWords::Crawler::Parser->get_and_append_story_text
    #($self->engine->db, $download->feeds_id->parser_module,
    #$download->stories_id, $response->decoded_content);
}

sub _set_spider_download_state_as_success
{
    my ( $self, $download ) = @_;

    print STDERR "setting state to success for download: " . $download->{ downloads_id } . " fetcher: " .
      $self->engine->fetcher_number . "\n";
    $self->engine->dbs->query( "update downloads set state = 'success', path = 'foo' where downloads_id = ?",
        $download->{ downloads_id } );

    return;
}

sub handle_feed_content
{
    my ( $self, $dbs, $download, $decoded_content ) = @_;

    my $num_new_stories = $self->_add_stories_and_content_downloads( $dbs, $download, $decoded_content );

    my $content_ref;
    if ( $num_new_stories > 0 )
    {
        $content_ref = \$decoded_content;
    }
    else
    {
        $content_ref = \"(redundant feed)";
    }

    MediaWords::DBI::Downloads::store_content( $dbs, $download, $content_ref );

    return;
}

sub handle_response
{
    my ( $self, $download, $response ) = @_;

    #say STDERR "fetcher " . $self->engine->fetcher_number . " handle response: " . $download->{url};

    my $dbs = $self->engine->dbs;

    if ( !$response->is_success )
    {
        $dbs->query(
            "update downloads set state = 'error', error_message = ? where downloads_id = ?",
            encode( 'utf-8', $response->status_line ),
            $download->{ downloads_id }
        );
        return;
    }

    # say STDERR "fetcher " . $self->engine->fetcher_number . " starting restrict content type";

    $self->_restrict_content_type( $response );

    # say STDERR "fetcher " . $self->engine->fetcher_number . " starting reset";

    # may need to reset download url to the last redirect url
    $download->{ url } = ( $response->request->url );

    $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );

    # say STDERR "switching on download type " . $download->{type};
    switch ( $download->{ type } )
    {
        case 'feed'
        {

            $self->handle_feed_content( $dbs, $download, $response->decoded_content );
        }
        case 'archival_only'
        {
            MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
        }
        case 'content'
        {
            MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
            $self->_process_content( $dbs, $download, $response );
        }
        case 'spider_blog_home'
        {
            $self->{ blog_spider_handler }->_process_spidered_download( $download, $response );
            $self->_set_spider_download_state_as_success( $download );
        }
        case 'spider_rss'
        {
            $self->_add_spider_posting_downloads( $download, $response );
            $self->_set_spider_download_state_as_success( $download );
        }
        case 'spider_posting'
        {
            $self->{ blog_spider_posting_handler } = MediaWords::Crawler::BlogSpiderPostingHandler->new( $self->engine );
            $self->{ blog_spider_posting_handler }->process_spidered_posting_download( $download, $response );
            $self->_set_spider_download_state_as_success( $download );
        }
        case 'spider_blog_friends_list'
        {
            $self->{ blog_friends_list_handler } = MediaWords::Crawler::BlogSpiderPostingHandler->new( $self->engine );
            $self->{ blog_friends_list_handler }->process_spidered_posting_download( $download, $response );
            $self->_set_spider_download_state_as_success( $download );
        }
        case 'spider_validation_blog_home'
        {
            print STDERR "starting spider_validation_blog_home\n";
            MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
            $self->_set_spider_download_state_as_success( $download );
            print STDERR "completed spider_validation_blog_home\n";
        }
        case 'spider_validation_rss'
        {
            print STDERR "starting spider_validation_rss\n";
            MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
            $self->_store_last_rss_entry_time( $download, $response );
            $self->_set_spider_download_state_as_success( $download );
            print STDERR "completed spider_validation_rss\n";

            #$self->_process_content( $download, $response );
        }
        else
        {
            die "Unknown download type " . $download->{ type }, "\n";
        }
    }
}

# calling engine
sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
