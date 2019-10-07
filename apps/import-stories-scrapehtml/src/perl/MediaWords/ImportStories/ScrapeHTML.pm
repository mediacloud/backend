package MediaWords::ImportStories::ScrapeHTML;

# scrape stories using MediaWords::ScrapeStories by scraping html
#
# in addition to ImportStories options, new accepts the following options:
#
# * start_url - the url to start scraping from
# * page_url_patern - regex for pages to add to the scraping queue
# * story_url_pattern - regex for pages to add as stories
#
# This scraper recursively downloads pages matching page_url_pattern.  For each such page, it finds all urls matching
# story_url_pattern and adds each as a story candidate.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::ImportStories';

use CHI;
use Data::Dumper;
use HTML::LinkExtractor;
use List::Util;
use List::MoreUtils qw/ uniq /;

use MediaWords::Util::URL;
use MediaWords::Util::Web;

# seconds to sleep between each page url fetch
Readonly my $THROTTLE_SLEEP_TIME => 10;

# keep track of last sleep time so that we can make sure we only fetch urls every $THROTTLE_SLEEP_TIME seconds
my $_next_fetch_time = 0;

has 'start_url'         => ( is => 'rw', isa => 'Str', required => 1 );
has 'page_url_pattern'  => ( is => 'rw', isa => 'Str', required => 1 );
has 'story_url_pattern' => ( is => 'rw', isa => 'Str', required => 1 );
has 'content_pattern'   => ( is => 'rw', isa => 'Str', required => 0 );

# return CHI 1 for word counts
sub _get_cache
{
    return CHI->new(
        driver           => 'File',
        expires_in       => '1 month',
        expires_variance => '0.1',
        root_dir         => "/var/cache/scrape_stories",
        cache_size       => '50g'
    );
}

# get the cached url
sub _get_cached_url
{
    my ( $self, $url ) = @_;

    return $self->_get_cache->get( $url );
}

# set the content of the cached url
sub _set_cached_url
{
    my ( $self, $url, $content ) = @_;

    return $self->_get_cache->set( $url, $content );
}

# fetch content from the url; print a warning and return '' if there is an error
sub _fetch_url
{
    my ( $self, $url ) = @_;

    DEBUG( "fetch_url: $url" );

    if ( my $content = $self->_get_cached_url( $url ) )
    {
        return $content;
    }

    my $sleep_time = $_next_fetch_time - time;
    if ( $sleep_time > 0 )
    {
        DEBUG( "sleeping $sleep_time seconds ..." );
        sleep( $sleep_time );
    }
    $_next_fetch_time = time + $THROTTLE_SLEEP_TIME;

    my $ua = MediaWords::Util::Web::UserAgent->new();

    my $response = $ua->get( $url );

    if ( !$response->is_success )
    {
        WARN "Unable to fetch url '$url': " . $response->status_line;
        return '';
    }

    my $content = $response->decoded_content;

    DEBUG( "content (" . length( $content ) . "): " . substr( $content, 0, 80 ) );

    $self->_set_cached_url( $url, $content );

    return $content;
}

# for each story, fetch the url and create a story object with title, date, etc by parsing
# the resulting html.  if we fail to download a given url, just skip it and print a warning.
sub _get_stories_from_story_urls
{
    my ( $self, $story_urls ) = @_;

    my $stories = [];

    $story_urls = [ uniq( @{ $story_urls } ) ];

    for my $url ( @{ $story_urls } )
    {
        my $content = $self->_fetch_url( $url );
        push( @{ $stories }, $self->generate_story( $content, $url ) ) if ( $content );
    }

    return $stories;
}

# return a list of all links that appear in the html
sub _get_links_from_html
{
    my ( $self, $html, $url ) = @_;

    my $link_extractor = new HTML::LinkExtractor( undef, $url );

    $link_extractor->parse( \$html );

    my $link_lookup = {};

    for my $link ( @{ $link_extractor->links } )
    {
        next if ( !$link->{ href } );

        next if ( $link->{ href } !~ /^http/i );

        $link =~ s/www[a-z0-9]+.nytimes/www.nytimes/i;

        $link_lookup->{ $link->{ href } } = 1;
    }

    return [ keys( %{ $link_lookup } ) ];
}

# given html content, search for all urls and return urls that match the story_urls_pattern and
# the page_urls_pattern, respectively
sub _parse_urls_from_content
{
    my ( $self, $url, $content ) = @_;

    my $urls = $self->_get_links_from_html( $content, $url );

    my $story_url_pattern = $self->story_url_pattern;
    my $page_url_pattern  = $self->page_url_pattern;

    my $story_urls = [];
    my $page_urls  = [];

    for my $url ( @{ $urls } )
    {
        my $nu = eval { MediaWords::Util::URL::normalize_url( $url ) } || $url;

        push( @{ $story_urls }, $nu ) if ( $nu =~ /$story_url_pattern/i );
        push( @{ $page_urls },  $nu ) if ( $nu =~ /$page_url_pattern/i );
    }

    DEBUG "page_urls: " . Dumper( $page_urls );
    DEBUG "story_urls: " . Dumper( $story_urls );
    DEBUG scalar( @{ $story_urls } ) . " story_urls found before dedup";

    return ( $story_urls, $page_urls );
}

# start with start_url; for each url, download that url, add any urls that match story_url_pattern to the
# story url list, add any urls that match page_url_pattern to the queue to repeat this process. once we have
# all of the story urls, download each story url and return the list of stories.  only return stories
# between start_date and end_date
sub get_new_stories
{
    my ( $self ) = @_;

    my $story_urls = [];

    my $i = 1;

    my $page_urls        = [ $self->start_url ];
    my $page_urls_lookup = {};
    while ( my $page_url = pop( @{ $page_urls } ) )
    {
        next if ( $page_urls_lookup->{ $page_url } );
        $page_urls_lookup->{ $page_url } = 1;

        last if ( $i++ > $self->max_pages );

        DEBUG "page_url: $page_url";
        my $content = $self->_fetch_url( $page_url );
        my ( $new_story_urls, $new_page_urls ) = $self->_parse_urls_from_content( $page_url, $content );

        push( @{ $page_urls },  @{ $new_page_urls } );
        push( @{ $story_urls }, @{ $new_story_urls } );
        sleep( $THROTTLE_SLEEP_TIME );
    }

    my $all_stories = $self->_get_stories_from_story_urls( $story_urls );

    my $dated_stories = $self->_get_stories_in_date_range( $all_stories );

    return $dated_stories;
}

1;
