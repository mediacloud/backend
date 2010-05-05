package MediaWords::Crawler::BlogSpiderPostingHandler;

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::Strip;
use HTML::LinkExtractor;
use IO::Compress::Gzip;
use List::MoreUtils qw (any);
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

sub process_spidered_posting_download
{
    my ( $self, $download, $response ) = @_;

    my $url = $response->request->uri;
    {
        print "$url is blog\n";
        $self->_process_links( $download, $response );
    }

    $self->engine->dbs->query( "update downloads set state = ?, path = 'foo' where downloads_id = ?",
        'success', $download->{downloads_id} );
}

sub _url_already_spidered
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $downloads = $dbs->query( "select * from downloads where type like 'spider%' and url = ? ", $url )->hashes;

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

    my $found_downloads = $dbs->query( "select * from downloads where url = ? limit 1", $url )->hashes;

    if ( scalar(@$found_downloads) )
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

sub list_contains
{
    ( my $value, my $list ) = @_;

    return any { $_ eq $value } @{$list};
}

my $spidered_hosts =
  [ 'livejournal.com', 'blogs.mail.ru', 'ya.ru', 'www.24open.ru', 'www.diary.ru', 'www.liveinternet.ru', ];

sub _is_url_black_listed_for_spider
{
    my ($url) = @_;

    if ( $url eq 'http://www.livejournal.com' )
    {
        return 1;
    }

    if ( $url =~ /www.livejournal.com/ )
    {
        return 1;
    }

    print "Black list testing '$url'\n";

    if ( !any { $url =~ /$_/ } @{$spidered_hosts} )
    {
        print "host not on spider list for $url\n";
        return 1;
    }

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

    if ( ( $url =~ /blogs\.mail\.ru/ ) && ( $url !~ /blogs\.mail\.ru\/mail\// ) )
    {
        return 1;
    }

    if ( ( $url =~ /^http:\/\/www\.liveinternet\.ru/ ) && ( $url !~ /^http:\/\/www\.liveinternet\.ru\/users/ ) )
    {
        return 1;
    }

    #only spider LJ for now
    if ( $url !~ /www\.diary\.ru\/~/ )
    {

        #print "blacklisted not diary.ru $url\n";
        #return 1;
    }

    if ( ( $url =~ /www\.24open\.ru/ ) && ( $url !~ /www\.24open\.ru\/[^\/]*\/blog/ ) )
    {

        print "blacklisted 24open.ru nonblog page '$url'\n";
        return 1;
    }
    if ( $url eq 'http://my.ya.ru' )
    {
        return 1;
    }

    if ( $url =~ /passport\.yandex\.ru.*/ )
    {
        return 1;
    }

    if ( $url !~ /ya\.ru/ )
    {

        #print "blacklisted not ya.ru\n";
        #return 1;
    }

    print "Not blacklisted $url\n";
    return 0;
}

sub _uri_should_be_spidered
{
    my ( $self, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($uri);

    return 0 if ( _is_url_black_listed_for_spider($url) );

    if ( $self->_url_already_processed($uri) || $self->_url_already_spidered($url) )
    {
        print "Already processed $url\n";
        return 0;
    }
    else
    {
        print "Not yet processed $url\n";
    }

    return 1;
}

sub _add_spider_download
{
    my ( $self, $download, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($uri);

    my $dbs = $self->engine->dbs;

    print "Adding spider blog home download for $url\n";

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

    die unless $self->_url_already_processed($url);

    #$dbs->commit;
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
