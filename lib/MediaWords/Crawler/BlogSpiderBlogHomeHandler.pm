package MediaWords::Crawler::BlogSpiderBlogHomeHandler;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::LinkExtractor;
use URI::Split;
use Carp;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use MediaWords::Crawler::BlogPageProcessor;
use MediaWords::Crawler::BlogUrlCanonicalizer;
use MediaWords::Crawler::BlogSpiderDbUtils;

# METHODS

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

    return $self;
}

sub _get_site_from_url
{
    my ( $url ) = @_;

    my $host = lc( ( URI::Split::uri_split( $url ) )[ 1 ] );

    ##strip out sub domains

    $host =~ s/.*\.([^.]*\.[^.]*)/$1/;

    return $host;
}

sub _log_rejected_blog
{
    my ( $self, $download, $response, $reason ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $response->request->url );
    my $title = encode( 'utf-8', $response->title );

    my $site = _get_site_from_url( $url );

    $self->engine->dbs->create(
        'rejected_blogs',
        {
            url    => $url,
            title  => $title,
            reason => $reason,
            site   => $site,
        }
    );
}

sub _log_found_blog_and_add_spider_rss_download
{
    my ( $self, $download, $response, $blog_page ) = @_;

    my $url       = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $response->request->url );
    my $title     = encode( 'utf-8', $response->title );
    my @rss_feeds = $blog_page->get_rss_feeds( $download, $response );

    my $rss = $rss_feeds[ 0 ];

    my $site = _get_site_from_url( $url );

    $self->engine->dbs->create(
        'found_blogs',
        {
            url   => $url,
            title => $title,
            rss   => $rss,
            site  => $site,
        }
    );

    MediaWords::Crawler::BlogSpiderDbUtils::add_friends_list_page( $self->engine->dbs, $download->{ url }, $download );

    $self->_add_spider_rss_download( $download, $rss );
}

sub _add_friends_list_page_download
{
    my ( $self, $download, $friends_list_page ) = @_;

    my $dbs = $self->engine->dbs;

    MediaWords::Crawler::BlogSpiderDbUtils::add_friends_list_page( $dbs, $friends_list_page, $download );

    return;
}

sub _add_spider_rss_download
{
    my ( $self, $download, $rss ) = @_;

    my $dbs = $self->engine->dbs;

    print "Add spider rss download '$rss'";

    die "Trying to add null $rss" unless $rss;
    $dbs->create(
        'downloads',
        {
            url    => $rss,
            parent => $download->{ downloads_id },
            host   => lc( ( URI::Split::uri_split( $rss ) )[ 1 ] ),

            #                stories_id    => 1,
            type          => 'spider_rss',
            sequence      => 0,
            state         => 'pending',
            priority      => 1,
            download_time => 'now()',
            extracted     => 'f'
        }
    );
}

sub _process_spidered_download
{
    my ( $self, $download, $response ) = @_;

    my $url = $response->request->uri;

    #hack to handle redirects or other weirdness
    if (   $self->_url_already_processed( $url->canonical )
        || $self->_url_already_processed( MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $url ) ) )
    {
        return;
    }

    my $blog_page = MediaWords::Crawler::BlogPageProcessor::create_blog_page_processor( $download, $response );

    my $non_blog_reason = $blog_page->is_download_known_non_blog();

    #todo grab rss feed
    #spidered_blog_post
    if ( !$non_blog_reason )
    {
        print "$url is blog\n";
        $self->_log_found_blog_and_add_spider_rss_download( $download, $response, $blog_page );
    }
    else
    {
        $self->_log_rejected_blog( $download, $response, $non_blog_reason );
        print "$url is not blog\n";
    }

    return;
}

sub _url_already_processed
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $rejected_blogs = $dbs->query( "select * from rejected_blogs where url = ? limit 1", $url )->hashes;

    if ( scalar( @$rejected_blogs ) )
    {
        return 1;
    }

    my $found_blogs = $dbs->query( "select * from found_blogs where url = ? limit 1", $url )->hashes;

    if ( scalar( @$found_blogs ) )
    {
        return 1;
    }

    return 0;
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
