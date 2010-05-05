package MediaWords::Crawler::Handler;

# process the fetched response for the crawler:
# * store the download in the database,
# * store the response content in the fs,
# * parse the response content to generate more downloads (eg. story urls from a feed download)
# * parse the response content to add story text to the database

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use HTML::Strip;
use IO::Compress::Gzip;
use URI::Split;
use XML::Feed;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Feeds;
use MediaWords::Util::Config;
use MediaWords::DB::Downloads;

# CONSTANTS

# max number of pages the handler will download for a single story
use constant MAX_PAGES => 10;

# STATICS

my $_feed_media_ids = {};

# METHODS

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine($engine);

    return $self;
}

# call XML::Feed->parse to parse the feed and return the resulting entries.
# handled errors, including setting the appropriate error state on the download.
sub _get_feed_items
{
    my ( $self, $download, $xml_ref ) = @_;

    my $feed;
    eval { $feed = XML::Feed->parse($xml_ref); };

    my $err = $@;

    # try to reparse after munging the xml.  only do this when needed to avoid expensive regexes.
    if ($err)
    {
        $$xml_ref = encode( 'utf-8', $$xml_ref );
        $$xml_ref =~ s/[\s\n\r]+/ /g;
        $$xml_ref =~ s/<!--[^>]*-->//g;
        $$xml_ref =~ s/><rss/>\n<rss/;
        eval { $feed = XML::Feed->parse($xml_ref); };
        $err = $@;
    }

    if ( !$feed || $err )
    {
        my $error_msg = encode( 'utf-8', "Unable to parse feed " . $download->{url} . ": $@" );
        $download->{state}         = ('error');
        $download->{error_message} = ($error_msg);

        my $dbs = $self->engine->dbs;
        $dbs->update_by_id( "downloads", $download->{downloads_id}, $download );
        die($error_msg);
    }

    return [ $feed->entries ];
}

##TODO refactor!!!
### This methods lives in both Provider & Handler
sub _get_download_media_impl
{
    my ( $self, $feeds_id ) = @_;

    if ( $_feed_media_ids->{$feeds_id} )
    {
        return $_feed_media_ids->{$feeds_id};
    }

    my $dbs = $self->engine->dbs;

    my ($media_id) = $dbs->query( "SELECT media_id from feeds where feeds_id = ?", $feeds_id )->flat;

    $_feed_media_ids->{$feeds_id} = $media_id;

    return $media_id;
}

# parse the feed and add the resulting stories and content downloads to the database
sub _add_stories_and_content_downloads
{
    my ( $self, $download, $response ) = @_;

    my $items = $self->_get_feed_items( $download, \$response->content );

    my $num_new_stories = 0;
    for my $item ( @{$items} )
    {
        my $url  = $item->link() || $item->id();
        my $guid = $item->id()   || $item->link();

        if ( !$url && !$guid )
        {
            next;
        }

        $url =~ s/[\n\r\s]//g;

        my $date = $item->issued() || DateTime->now;

        my $media_id = $self->_get_download_media_impl( $download->{feeds_id} );

        my @stories = $self->engine->db->resultset('Stories')->search( { guid => $guid, media_id => $media_id } );
        my $story = $stories[0];

        if ( !$story )
        {
            my $start_date = $date->subtract( hours => 12 );
            my $end_date = $date->add( hours => 12 );
            @stories = $self->engine->db->resultset('Stories')->search(
                {
                    title    => encode( 'utf-8', $item->title ),
                    media_id => $media_id,
                    publish_date => { between => [ $start_date, $end_date ] }
                }
            );
            $story = $stories[0];
        }

        if ( !$story )
        {
            $num_new_stories++;
            my $media_id = MediaWords::DBI::Downloads::get_media_id( $self->engine->dbs, $download );
            my $dbs = $self->engine->dbs;

            $story = $dbs->create(
                "stories",
                {
                    url          => $url,
                    guid         => $guid,
                    media_id     => $media_id,
                    publish_date => $date->datetime,
                    collect_date => DateTime->now->datetime,
                    title        => encode( 'utf-8', $item->title() ) || '(no title)',
                    description => encode( 'utf-8', $item->content->body ),
                }
            );

            $self->engine->dbs->create(
                'downloads',
                {
                    feeds_id      => $download->{feeds_id},
                    stories_id    => $story->{stories_id},
                    parent        => $download->{downloads_id},
                    url           => $url,
                    host          => lc( ( URI::Split::uri_split($url) )[1] ),
                    type          => 'content',
                    sequence      => 1,
                    state         => 'pending',
                    priority      => $download->{priority},
                    download_time => 'now()',
                    extracted     => 'f'
                }
            );

        }
        $self->engine->dbs->find_or_create(
            'feeds_stories_map',
            {
                stories_id => $story->{stories_id},
                feeds_id   => $download->{feeds_id}
            }
        );

        #FIXME - add meta keywords
    }

    return $num_new_stories;
}

# chop out the content if we don't allow the content type
sub _restrict_content_type
{
    my ( $self, $response ) = @_;

    if ( $response->content_type =~ m~text|html|xml|rss|atom~i )
    {
        return;
    }

    #if ($response->content =~ m~<html|<xml|<rss|<atom~i) {
    #    return;
    #}

    print "unsupported content type: " . $response->content_type . "\n";
    $response->content('(unsupported content type)');
}

# call get_page_urls from the pager module for the download's feed
sub _call_pager
{
    my ( $self, $download, $response ) = @_;

    if ( $download->{sequence} > MAX_PAGES )
    {
        print "reached max pages (" . MAX_PAGES . ") for url " . $download->{url} . "\n";
        return;
    }

    if ( $self->engine->dbs->query( "SELECT * from downloads where parent = ? ", $download->{downloads_id} )->hash )
    {
        print "story already paged for url " . $download->{url} . "\n";
        return;
    }

    my $rs = $self->engine->db->resultset('Downloads');

    if ( my $next_page_url = MediaWords::Crawler::Pager->get_next_page_url( $rs, $download->{url}, $response->content ) )
    {

        print "next page: $next_page_url\n";
        print "prev page: " . $download->{url} . "\n";

        $self->engine->dbs->create(
            'downloads',
            {
                feeds_id      => $download->{feeds_id},
                stories_id    => $download->{stories_id},
                parent        => $download->{downloads_id},
                url           => $next_page_url,
                host          => lc( ( URI::Split::uri_split($next_page_url) )[1] ),
                type          => 'content',
                sequence      => $download->{sequence} + 1,
                state         => 'pending',
                priority      => $download->{priority} + 1,
                download_time => 'now()',
                extracted     => 'f'
            }
        );
    }
}

# call the content module to parse the text from the html and add pending downloads
# for any additional content
sub _process_content
{
    my ( $self, $download, $response ) = @_;

    $self->_call_pager( $download, $response );

    #MediaWords::Crawler::Parser->get_and_append_story_text
    #($self->engine->db, $download->feeds_id->parser_module,
    #$download->stories_id, $response->content);
}

sub convert_dbisimple_download_to_dbix
{
    my ( $self, $download_dbi_simple ) = @_;

    return $self->engine->db->resultset('Downloads')->find_or_create($download_dbi_simple);
}

# comment out until the rest of the file is refactored -hal
# # update the feeds.generator and feeds.comments_anchor fields if they have changed
# sub _update_feed_generator_and_comments
# {
#     my ( $self, $download, $response ) = @_;
#
#     my $feed = $self->engine->db->resultset('Feeds')->find( { feeds_id => $download->get_column('feeds_id') } );
#
#     if (my $generator = MediaWords::DBI::Feeds::get_generator_from_xml($response->content)) {
#         $feed->generator($generator);
#     }
#
#     if (my $comments_anchor = MediaWords::DBI::Feeds::get_comments_archive_from_xml($response->content)) {
#         $feed->comments_anchor($comments_anchor);
#     }
#
#     $feed->update();
# }

sub handle_response
{
    my ( $self, $download, $response ) = @_;

    #print "fetcher " . $self->engine->fetcher_number . " handle response: " . $download->{url} . "\n";

    my $dbs = $self->engine->dbs;

    if ( !$response->is_success )
    {
        $download->{state} = ('error');
        $download->{error_message} = ( encode( 'utf-8', $response->status_line . "\n" . $response->content ) );

        $dbs->update_by_id( "downloads", $download->{downloads_id}, $download );
        return;
    }

    $self->_restrict_content_type($response);

    # may need to reset download url to the last redirect url
    $download->{url} = ( $response->request->url );

    $dbs->update_by_id( "downloads", $download->{downloads_id}, $download );

    if ( $download->{type} eq 'feed' )
    {

        # $self->_update_feed_generator_and_comments( $download, $response );

        my $num_new_stories = $self->_add_stories_and_content_downloads( $download, $response );

        my $content_ref;
        if ( $num_new_stories > 0 )
        {
            $content_ref = \$response->content;
        }
        else
        {
            $content_ref = \"(redundant feed)";
        }

        MediaWords::DBI::Downloads::store_content( $dbs, $download, $content_ref );
    }
    elsif ( $download->{type} eq 'content' )
    {
        MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->content );
        $self->_process_content( $download, $response );
    }
}

# calling engine
sub engine
{
    if ( $_[1] )
    {
        $_[0]->{engine} = $_[1];
    }

    return $_[0]->{engine};
}

1;
