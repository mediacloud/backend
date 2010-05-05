package MediaWords::Crawler::BlogSpiderHandler;

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::Strip;
use HTML::LinkExtractor;
use IO::Compress::Gzip;
use URI::Split;
use XML::Feed;
use Carp;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Feeds;
use MediaWords::Util::Config;
use MediaWords::Crawler::BlogPageProcessor;
use MediaWords::Crawler::BlogUrlCanonicalizer;

# METHODS

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine($engine);

    return $self;
}

sub _log_rejected_blog
{
    my ( $self, $download, $response, $reason ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $response->request->url );
    my $title = encode( 'utf-8', $response->title );

    $self->engine->dbs->create(
        'rejected_blogs',
        {
            url    => $url,
            title  => $title,
            reason => $reason,
        }
    );
}

sub _log_found_blog
{
    my ( $self, $download, $response, $blog_page ) = @_;

    my $url       = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $response->request->url );
    my $title     = encode( 'utf-8', $response->title );
    my @rss_feeds = $blog_page->get_rss_feeds( $download, $response );

    my $rss = @rss_feeds[0];

    $self->engine->dbs->create(
        'found_blogs',
        {
            url   => $url,
            title => $title,
            rss   => $rss,
        }
    );

    $self->_add_spider_rss_download( $download, $rss );
}

sub _add_spider_rss_download
{
    my ( $self, $download, $rss ) = @_;

    my $dbs = $self->engine->dbs;

    print "Add spider rss download";

    $dbs->create(
        'downloads',
        {
            url    => $rss,
            parent => $download->{downloads_id},
            host   => lc( ( URI::Split::uri_split($rss) )[1] ),

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
        || $self->_url_already_processed( MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($url) ) )
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
        $self->_log_found_blog( $download, $response, $blog_page );

        #$self->_process_links( $download, $response );
    }
    else
    {
        $self->_log_rejected_blog( $download, $response, $non_blog_reason );
        print "$url is not blog\n";
    }

    $self->engine->dbs->query( "update downloads set state = ?, path = 'foo' where downloads_id = ?",
        'success', $download->{downloads_id} );
}

sub _url_already_spidered
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $downloads = $dbs->query( "select * from downloads where type = 'spider' and url = ? ", $url )->hashes;

    if ( scalar(@$downloads) )
    {

        #print "Link '$url' already in downloads table not re-adding\n";
        return 1;
    }
    else
    {
        print "Link '$url' not in downloads table\n";
        return 0;
    }
}

sub _url_already_processed
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $rejected_blogs = $dbs->query( "select * from rejected_blogs where url = ? limit 1", $url )->hashes;

    if ( scalar(@$rejected_blogs) )
    {
        return 1;
    }

    my $found_blogs = $dbs->query( "select * from found_blogs where url = ? limit 1", $url )->hashes;

    if ( scalar(@$found_blogs) )
    {
        return 1;
    }

    return 0;
}

sub spidered_download_count
{
    my ($self) = @_;

    my $ret = $self->engine->dbs->query("SELECT count(*) from downloads where type = 'spider' ")->flat->[0];
    return $ret;
}

sub _is_url_black_listed_for_spider
{
    my ($url) = @_;

    print "Black list testing $url\n";

    #don't crawl the main pages for sites
    if ( $url eq 'http://livejournal.com' )
    {
        return 1;
    }

    if ( $url eq 'http://www.livejournal.com' )
    {
        return 1;
    }

    if ( $url =~ /doubleclick.net/ )
    {
        return 1;
    }

    if ( $url =~ /http:\/\/livejournalinc.com/ )
    {
        return 1;
    }

    #only spider LJ for now
    if ( $url !~ /livejournal.com/ )
    {

        #    return 1;
    }

    #only spider LJ for now
    if ( $url !~ /blogs\.mail\.ru\/mail\// )
    {

        #        return 1;
    }

    #only spider LJ for now
    if ( $url !~ /www\.liveinternet\.ru\/users/ )
    {

        #  return 1;
    }

    #only spider LJ for now
    if ( $url !~ /www\.diary\.ru\/~/ )
    {

        #print "blacklisted not diary.ru $url\n";
        #return 1;
    }

    #only spider LJ for now
    if ( $url !~ /www\.24open\.ru\/[^\/]*\/blog/ )
    {

        #        print "blacklisted not 24open.ru $url\n";
        #        return 1;
    }
    if ( $url eq 'http://my.ya.ru' )
    {
        return 1;
    }

    if ( $url !~ /ya\.ru/ )
    {
        print "blacklisted not ya.ru\n";
        return 1;
    }

    print "Not blacklisted $url\n";
    return 0;
}

sub _uri_should_be_spidered
{
    my ( $self, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($uri);

    return 0 if ( _is_url_black_listed_for_spider($url) );

    if ( $self->_url_already_processed($url) || $self->_url_already_spidered($url) )
    {
        return 0;
    }

    return 1;
}

sub _add_spider_download
{
    my ( $self, $download, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($uri);

    my $dbs = $self->engine->dbs;

    $dbs->create(
        'downloads',
        {
            url    => $url,
            parent => $download->{downloads_id},
            host   => lc( ( URI::Split::uri_split($url) )[1] ),

            #                stories_id    => 1,
            type          => 'spider_blog_home',
            sequence      => 0,
            state         => 'pending',
            priority      => 1,
            download_time => 'now()',
            extracted     => 'f'
        }
    );
}

sub _get_possible_blog_uris
{
    my ( $self, $download, $response ) = @_;

    my $url = $response->request->uri;

    my $p = HTML::LinkExtractor->new( undef, $url );
    $p->parse( \$response->content );

    #we only care about links to web pages
    #i.e. '<a href=..' we want to ignore other things such as <img & javascript links
    my $links = [ grep { $_->{tag} eq 'a' } @{ $p->links } ];

    $links = [ grep { $_->{href}->scheme eq 'http' } @{$links} ];

    return map { $_->{href} } @$links;
}

sub _process_links
{
    my ( $self, $download, $response ) = @_;

    my @uris = $self->_get_possible_blog_uris( $download, $response );

    for my $uri (@uris)
    {
        last if ( $self->spidered_download_count() > 300 );

        if ( $self->_uri_should_be_spidered($uri) )
        {
            $self->_add_spider_download( $download, $uri );
        }
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
