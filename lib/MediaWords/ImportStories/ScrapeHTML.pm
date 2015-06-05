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

use Moose;
with 'MediaWords::ImportStories';

use CHI;
use Data::Dumper;
use HTML::LinkExtractor;
use List::MoreUtils;

use MediaWords::Util::Config;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

has 'start_url'         => ( is => 'rw', isa => 'Str', required => 1 );
has 'page_url_pattern'  => ( is => 'rw', isa => 'Str', required => 1 );
has 'story_url_pattern' => ( is => 'rw', isa => 'Str', required => 1 );
has 'content_pattern'   => ( is => 'rw', isa => 'Str', required => 0 );

# return CHI 1 for word counts
sub _get_cache
{
    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 month',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/scrape_stories",
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
    my ( $self, $original_url ) = @_;

    if ( my $content = $self->_get_cached_url( $original_url ) )
    {
        return $content;
    }

    my $ua = MediaWords::Util::Web::UserAgent;

    my $content;
    my $refresh_loops = 0;
    my $url           = $original_url;
    while ( !$content )
    {
        say STDERR "fetch_url: $url" if ( $self->debug );
        my $response = $ua->get( $url );

        if ( !$response->is_success )
        {
            warn( "Unable to fetch url '$url': " . $response->status_line );
            return '';
        }

        $content = $response->decoded_content;

        if (   ( $refresh_loops++ < 10 )
            && ( my $refresh_url = MediaWords::Util::URL::meta_refresh_url_from_html( $content, $url ) ) )
        {
            $url     = $refresh_url;
            $content = '';
        }
    }

    $self->_set_cached_url( $original_url, $content );

    return $content;
}

# for each story, fetch the url and create a story object with title, date, etc by parsing
# the resulting html.  if we fail to download a given url, just skip it and print a warning.
sub _get_stories_from_story_urls
{
    my ( $self, $story_urls ) = @_;

    my $stories = [];

    $story_urls = [ List::MoreUtils::uniq( @{ $story_urls } ) ];

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
        my $nu = MediaWords::Util::URL::normalize_url( $url );

        push( @{ $story_urls }, $nu ) if ( $nu =~ /$story_url_pattern/i );
        push( @{ $page_urls },  $nu ) if ( $nu =~ /$page_url_pattern/i );
    }

    say STDERR "page_urls: " . Dumper( $page_urls )                          if ( $self->debug );
    say STDERR "story_urls: " . Dumper( $story_urls )                        if ( $self->debug );
    say STDERR scalar( @{ $story_urls } ) . " story_urls found before dedup" if ( $self->debug );

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

        say STDERR "page_url: $page_url" if ( $self->debug );

        my $content = $self->_fetch_url( $page_url );
        my ( $new_story_urls, $new_page_urls ) = $self->_parse_urls_from_content( $page_url, $content );

        push( @{ $page_urls },  @{ $new_page_urls } );
        push( @{ $story_urls }, @{ $new_story_urls } );
    }

    my $all_stories = $self->_get_stories_from_story_urls( $story_urls );

    my $dated_stories = $self->_get_stories_in_date_range( $all_stories );

    return $dated_stories;
}

1;
