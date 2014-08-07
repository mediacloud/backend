package MediaWords::Crawler::Handler;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

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
use URI::Split;
use if $] < 5.014, Switch => 'Perl6';
use if $] >= 5.014, feature => 'switch';
use Carp;

use List::Util qw (max maxstr);

use Feed::Scrape::MediaWords;
use MediaWords::Crawler::BlogSpiderBlogHomeHandler;
use MediaWords::Crawler::BlogSpiderPostingHandler;
use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::Config;
use MediaWords::DBI::Stories;
use MediaWords::Crawler::FeedHandler;
use MediaWords::GearmanFunction::ExtractAndVector;

# CONSTANTS

# max number of pages the handler will download for a single story
use constant MAX_PAGES => 10;

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

# chop out the content if we don't allow the content type
sub _restrict_content_type
{
    my ( $self, $response ) = @_;

    if ( $response->content_type =~ m~text|html|xml|rss|atom~i )
    {
        return;
    }

    $response->content( '(unsupported content type)' );
}

# return 1 if medium->{ use_pager } is null or true and 0 otherwise
sub use_pager
{
    my ( $medium ) = @_;

    return 1 if ( !defined( $medium->{ use_pager } ) || $medium->{ use_pager } );

    return 0;
}

# if use_pager is already set, do nothing.  Otherwise, if next_page_url is true,
# set use_pager to true.  Otherwise, if there are less than 100 unpaged_stories,
# increment unpaged_stories.  If there are at least 100 unpaged_stories, set
# use_pager to false.
sub set_use_pager
{
    my ( $dbs, $medium, $next_page_url ) = @_;

    return if ( defined( $medium->{ use_pager } ) );

    if ( $next_page_url )
    {
        $dbs->query( "update media set use_pager = 't' where media_id = ?", $medium->{ media_id } );
    }
    elsif ( !defined( $medium->{ unpaged_stories } ) )
    {
        $dbs->query( "update media set unpaged_stories = 1 where media_id = ?", $medium->{ media_id } );
    }
    elsif ( $medium->{ unpaged_stories } < 100 )
    {
        $dbs->query( "update media set unpaged_stories = unpaged_stories + 1 where media_id = ?", $medium->{ media_id } );
    }
    else
    {
        $dbs->query( "update media set use_pager = 'f' where media_id = ?", $medium->{ media_id } );
    }
}

# call get_page_urls from the pager module for the download's feed
sub call_pager
{
    my ( $self, $dbs, $download ) = @_;
    my $content = \$_[ 3 ];

    my $medium = $dbs->query( <<END, $download->{ feeds_id } )->hash;
select * from media m where media_id in ( select media_id from feeds where feeds_id = ? );
END

    return unless ( use_pager( $medium ) );

    if ( $download->{ sequence } > MAX_PAGES )
    {
        print STDERR "reached max pages (" . MAX_PAGES . ") for url '$download->{ url }'\n";
        return;
    }

    if ( $dbs->query( "SELECT * from downloads where parent = ? ", $download->{ downloads_id } )->hash )
    {
        return;
    }

    my $validate_url = sub { !$dbs->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    my $next_page_url = MediaWords::Crawler::Pager->get_next_page_url( $validate_url, $download->{ url }, $content );

    if ( $next_page_url )
    {
        print STDERR "next page: $next_page_url\nprev page: $download->{ url }\n";

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

    set_use_pager( $dbs, $medium, $next_page_url );
}

sub _queue_extraction($$)
{
    my ( $self, $download ) = @_;

    my $db             = $self->engine->dbs;
    my $fetcher_number = $self->engine->fetcher_number;

    say STDERR "fetcher $fetcher_number starting extraction for download " . $download->{ downloads_id };

    MediaWords::GearmanFunction::ExtractAndVector->extract_for_crawler( $db, $download, $fetcher_number );
}

sub _queue_author_extraction($$;$)
{
    my ( $self, $download, $response ) = @_;

    say STDERR "fetcher " .
      $self->engine->fetcher_number . " starting _queue_author_extraction for download " . $download->{ downloads_id };

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
}

# call the content module to parse the text from the html and add pending downloads
# for any additional content
sub _process_content
{
    my ( $self, $dbs, $download, $response ) = @_;

    say STDERR "fetcher " . $self->engine->fetcher_number . " starting _process_content for  " . $download->{ downloads_id };

    $self->call_pager( $dbs, $download, $response->decoded_content );

    $self->_queue_extraction( $download );

    $self->_queue_author_extraction( $download );

    say STDERR "fetcher " . $self->engine->fetcher_number . " finished _process_content for  " . $download->{ downloads_id };
}

sub handle_response
{
    my ( $self, $download, $response ) = @_;

    say STDERR "fetcher " . $self->engine->fetcher_number . " starting handle response: " . $download->{ url };

    my $dbs = $self->engine->dbs;

    unless ( $response->is_success )
    {
        $dbs->query(
            <<EOF,
            UPDATE downloads
            SET state = 'error',
                error_message = ?,
                -- reset the file status in case it's one of the "missing" downloads:
                file_status = DEFAULT
            WHERE downloads_id = ?
EOF
            encode( 'utf-8', $response->status_line ),
            $download->{ downloads_id }
        );

        # TODO uncomment $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );
        return;
    }

    $self->_restrict_content_type( $response );

    $dbs->query( <<END, $download->{ url }, $download->{ downloads_id } );
update downloads set url = ? where downloads_id = ?
END

    my $download_type = $download->{ type };

    if ( $download_type eq 'feed' )
    {
        my $config = MediaWords::Util::Config::get_config;
        if (   ( $config->{ mediawords }->{ do_not_process_feeds } )
            && ( $config->{ mediawords }->{ do_not_process_feeds } eq 'yes' ) )
        {
            MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
        }
        else
        {
            MediaWords::Crawler::FeedHandler::handle_feed_content( $dbs, $download, $response->decoded_content );
        }

    }
    elsif ( $download_type eq 'archival_only' )
    {
        MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );

    }
    elsif ( $download_type eq 'content' )
    {
        MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
        $self->_process_content( $dbs, $download, $response );

    }
    elsif ( $download_type eq 'spider_blog_home' )
    {
        $self->{ blog_spider_handler }->_process_spidered_download( $download, $response );
        $self->_set_spider_download_state_as_success( $download );

    }
    elsif ( $download_type eq 'spider_rss' )
    {
        $self->_add_spider_posting_downloads( $download, $response );
        $self->_set_spider_download_state_as_success( $download );

    }
    elsif ( $download_type eq 'spider_posting' )
    {
        $self->{ blog_spider_posting_handler } = MediaWords::Crawler::BlogSpiderPostingHandler->new( $self->engine );
        $self->{ blog_spider_posting_handler }->process_spidered_posting_download( $download, $response );
        $self->_set_spider_download_state_as_success( $download );

    }
    elsif ( $download_type eq 'spider_blog_friends_list' )
    {
        $self->{ blog_friends_list_handler } = MediaWords::Crawler::BlogSpiderPostingHandler->new( $self->engine );
        $self->{ blog_friends_list_handler }->process_spidered_posting_download( $download, $response );
        $self->_set_spider_download_state_as_success( $download );

    }
    elsif ( $download_type eq 'spider_validation_blog_home' )
    {
        print STDERR "starting spider_validation_blog_home\n";
        MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
        $self->_set_spider_download_state_as_success( $download );
        print STDERR "completed spider_validation_blog_home\n";

    }
    elsif ( $download_type eq 'spider_validation_rss' )
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

    say STDERR "fetcher " . $self->engine->fetcher_number . " completed handle response: " . $download->{ url };
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
