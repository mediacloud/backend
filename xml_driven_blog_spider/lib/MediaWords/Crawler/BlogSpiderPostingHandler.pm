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
use MediaWords::Crawler::BlogUrlProcessor;

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

    print "processing blog post '$url'\n";
    $self->_process_links( $download, $response );

    $self->engine->dbs->query( "update downloads set state = ?, path = 'foo' where downloads_id = ?",
        'success', $download->{downloads_id} );
}

sub _url_already_spidered
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $downloads = $dbs->query(
"select * from downloads where (type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss') and url = ? ",
        $url
    )->hashes;

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

    my $ret = $self->engine->dbs->query(
"SELECT count(*) from downloads where (type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss')  "
    )->flat->[0];
    return $ret;
}

sub list_contains
{
    ( my $value, my $list ) = @_;

    return any { $_ eq $value } @{$list};
}

sub _is_url_non_spidered_host
{
    my ($url) = @_;

    return !MediaWords::Crawler::BlogUrlProcessor::is_spidered_host($url);
}

sub _is_url_black_listed_for_spider
{
    my ($url) = @_;

    my $ret = !MediaWords::Crawler::BlogUrlProcessor::is_blog_home_page_url($url);

    if ($ret)
    {
        print "XXX Blacklisted url: $url\n";
    }
    else
    {
        print "XXX Not blacklisted url: $url\n";
    }

    return $ret;
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
            priority      => 0,
            download_time => 'now()',
            extracted     => 'f'
        }
    );

    die unless $self->_url_already_processed($url);

    #$dbs->commit;
}

sub _log_non_spidered_host
{
    my ( $self, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($uri);

    my $host = lc( ( URI::Split::uri_split($url) )[1] );

    my $dbs = $self->engine->dbs;

    print "Logging non spidered_host link for '$host' from '$url'\n";

    $dbs->commit;
    $dbs->begin_work();

    my $non_spidered_host_hash = $dbs->find_or_create( 'non_spidered_hosts', { host => $host } );

    $non_spidered_host_hash->{linked_to_count}++;

    $dbs->update_by_id( 'non_spidered_hosts', $non_spidered_host_hash->{non_spidered_hosts_id}, $non_spidered_host_hash );

    $dbs->commit;
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

    my $uris_spidered           = 0;
    my $uris_non_blog_host_uris = 0;
    for my $uri (@uris)
    {
        if ( $self->_uri_should_be_spidered($uri) )
        {

            #print STDERR "XXX Not spidering non-blog host url '$uri' \n";
            $self->_add_spider_download( $download, $uri );
            $uris_spidered++;
        }
        elsif ( _is_url_non_spidered_host( MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url($uri) ) )
        {

            #print STDERR "XXX Not spidering non-blog host url '$uri' \n";
            $self->_log_non_spidered_host($uri);
            $uris_non_blog_host_uris++;
        }
        else
        {

            #print STDERR "XXX Not spidering blog host url '$uri' \n";
        }
    }

#print STDERR "XXX $uris_spidered spidered urls; $uris_non_blog_host_uris non-blog host uris; " . scalar(@uris). " total uris\n";
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
