package MediaWords::Crawler::BlogPageProcessor;

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
use MediaWords::Crawler::BlogPageProcessor_LiveJournal;

# METHODS

sub get_rss_feeds
{
    my ($self) = @_;

    my $response = $self->{response};

    my $url = $response->request->uri;
    my @feeds = Feed::Find->find_in_html( \$response->content, $url );

    return @feeds;
}

sub _has_rss_feeds
{
    my ($self) = @_;

    my @feeds = $self->get_rss_feeds();

    return scalar(@feeds) > 0;
}

sub get_host_name
{
    my ($self) = @_;
    my $url = $self->{response}->request->uri;

    return lc( ( URI::Split::uri_split($url) )[1] );
}

sub is_russian
{
    my ($self) = @_;
    my $url = $self->{response}->request->uri;

    my $host = $self->get_host_name;

    return 0 if ( $host !~ /\.ru$/ );

    return 1;
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
    $url = lc( ( URI::Split::uri_split($url) )[1] );

    if ( $url =~ /\.livejournal.com/ )
    {
        return MediaWords::Crawler::BlogPageProcessor_LiveJournal->new( $download, $response );
    }
    else
    {
        return MediaWords::Crawler::BlogPageProcessor->new( $download, $response );
    }
}

sub new
{
    my ( $class, $download, $response ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{download} = $download;
    $self->{response} = $response;

    return $self;
}

1;
