package MediaWords::Crawler::BlogPageProcessor;
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
use if $] < 5.014, Switch => 'Perl6';
use if $] >= 5.014, feature => 'switch';

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use MediaWords::Crawler::BlogPageProcessor_LiveJournal;
use MediaWords::Crawler::BlogUrlProcessor;
use Feed::Scrape;

# METHODS

sub new
{
    my ( $class, $download, $response ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{ download } = $download;
    $self->{ response } = $response;

    return $self;
}

sub get_rss_feeds
{
    my ( $self ) = @_;

    my $response = $self->{ response };

    my $url = $response->request->uri;

    my @feeds;

    my $rss_detection_method = MediaWords::Crawler::BlogUrlProcessor::get_rss_detection_method( $url );

    if ( !$rss_detection_method )
    {
        $rss_detection_method = 'default';
    }

    if ( $rss_detection_method eq 'feed::scrape-validate' )
    {

        #print "Using   'feed::scrape-validate' \n";
        my $xml_feeds = Feed::Scrape->get_valid_feeds_from_html( $url, $response->content );

        #print Dumper($xml_feeds);
        @feeds = map { $_->{ url } } @{ $xml_feeds };

    }
    elsif ( $rss_detection_method eq 'feed::scrape-no-validate' )
    {

        #print "Using   'feed::scrape-no-validate' \n";
        my $xml_feeds = Feed::Scrape->get_feed_urls_from_html( $url, $response->content );

        #print Dumper($xml_feeds);
        @feeds = @{ $xml_feeds };

    }
    elsif ( $rss_detection_method eq 'default' )
    {

        #print "using default feed parsing\n";
        @feeds = Feed::Find->find_in_html( \$response->content, $url );

    }
    else
    {
        die "invalid rss detection method " . MediaWords::Crawler::BlogUrlProcessor::get_rss_detection_method;

    }

    #filter out empty string and undefined URLs
    @feeds = grep { $_ } @feeds;

    return @feeds;
}

sub _has_rss_feeds
{
    my ( $self ) = @_;

    my @feeds = $self->get_rss_feeds();

    return scalar( @feeds ) > 0;
}

sub get_host_name
{
    my ( $self ) = @_;
    my $url = $self->{ response }->request->uri;

    return lc( ( URI::Split::uri_split( $url ) )[ 1 ] );
}

sub is_russian
{
    my ( $self ) = @_;
    my $url = $self->{ response }->request->uri;

    my $host = $self->get_host_name;

    return 1 if ( $host =~ /\.ru$/ );

    #For now assume anything that we explicitly spider is Russian
    #Note that for livejournal.com we override this method and use a different test

    return 1 if MediaWords::Crawler::BlogUrlProcessor::is_spidered_host( $url );

    return 0;
}

sub is_download_known_non_blog
{
    my ( $self, $download, $response ) = @_;

    if ( !$self->_has_rss_feeds( $download, $response ) )
    {

        return "NO RSS";
    }

    if ( !$self->is_russian() )
    {
        return "NON RUSSIAN";
    }

    return;
}

sub create_blog_page_processor
{
    my ( $download, $response ) = @_;

    my $url = $response->request->uri;
    $url = lc( ( URI::Split::uri_split( $url ) )[ 1 ] );

    if ( $url =~ /\.livejournal.com/ )
    {
        return MediaWords::Crawler::BlogPageProcessor_LiveJournal->new( $download, $response );
    }
    else
    {
        return MediaWords::Crawler::BlogPageProcessor->new( $download, $response );
    }
}

1;
