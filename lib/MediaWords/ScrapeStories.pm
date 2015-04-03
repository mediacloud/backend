package MediaWords::ScrapeStories;

# Scrapes an html page for new stories to add to the given media source.
#
# The scrape interface is oo and includes the following parameters to new()
# * db - db handle
# * start_url - the url to start scraping from
# * page_url_patern - regex for pages to add to the scraping queue
# * story_url_pattern - regex for pages to add as stories
# * media_id - media source to which to add stories
# * max_pages (optional) - max num of pages to scrape by recursively finding urls matching page_url_pattern
# * start_date (optional) - start date of stories to scrape and dedup
# * end_date (optional) - end date of stories to scrape and dedup
# * debug (optional) - print debug messages urls crawled and stories created
# * dry_run (optional) - do everything but actually insert stories into db
#
# The scraper recursively downloads pages matching page_url_pattern.  For each such page, it finds all urls matching
# story_url_pattern and adds each as a story candidate.  After identying all story candidates, it looks for any
# duplicates among the story candidates and the existing stories in the media sources and only adds as stories
# the candidates with out existing duplicate stories.  The duplication check looks for matching normalized urls
# as well as matching title parts (see MediaWords::DBI::Stories::get_medium_dup_stories_by_<title|url>.

use Moose;

use CHI;
use Carp;
use Data::Dumper;
use Encode;
use Getopt::Long;
use HTML::LinkExtractor;
use List::MoreUtils;
use Params::Validate qw(:all);
use URI::Split;

use MediaWords::CM::GuessDate;
use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

has 'db'                => ( is => 'rw', isa => 'Ref', required => 1 );
has 'start_url'         => ( is => 'rw', isa => 'Str', required => 1 );
has 'page_url_pattern'  => ( is => 'rw', isa => 'Str', required => 1 );
has 'story_url_pattern' => ( is => 'rw', isa => 'Str', required => 1 );
has 'media_id'          => ( is => 'rw', isa => 'Int', required => 1 );

has 'debug'   => ( is => 'rw', isa => 'Int', required => 0 );
has 'dry_run' => ( is => 'rw', isa => 'Int', required => 0 );

has 'max_pages'  => ( is => 'rw', isa => 'Int', required => 0, default => 10_000 );
has 'start_date' => ( is => 'rw', isa => 'Str', required => 0, default => '1000-01-01' );
has 'end_date'   => ( is => 'rw', isa => 'Str', required => 0, default => '3000-01-01' );
has 'scrape_feed' => ( is => 'rw', isa => 'Ref', required => 0 );

# return CHI cache for word counts
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

        if ( ( $refresh_loops++ < 10 ) && ( my $refresh_url = MediaWords::Util::URL::meta_refresh_url_from_html( $content, $url ) )
        {
            $url     = $refresh_url;
            $content = '';
        }
    }

    $self->_set_cached_url( $original_url, $content );

    return $content;
}

# given the content, generate a story hash
sub _generate_story
{
    my ( $self, $content, $url ) = @_;

    my $db = $self->db;

    my $title = MediaWords::DBI::Stories::get_story_title_from_content( $content, $url );

    my $story = {
        url          => $url,
        guid         => $url,
        media_id     => $self->media_id,
        collect_date => MediaWords::Util::SQL::sql_now,
        title        => encode( 'utf8', $title ),
        description  => '',
        content      => $content
    };

    my $date_guess = MediaWords::CM::GuessDate::guess_date( $db, $story, $content, 1 );
    if ( $date_guess->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
    {
        $story->{ publish_date } = $date_guess->{ date };
    }
    else
    {
        $story->{ publish_date } = MediaWords::Util::SQL::sql_now();
    }

    return $story;
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
        push( @{ $stories }, $self->_generate_story( $content, $url ) );
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

sub _get_stories_in_date_range
{
    my ( $self, $stories ) = @_;

    my $dated_stories = [];
    for my $story ( @{ $stories } )
    {
        if ( ( $self->start_date le $story->{ publish_date } ) && ( $self->end_date ge $story->{ publish_date } ) )
        {
            push( @{ $dated_stories }, $story );
        }
    }

    say STDERR "kept " . scalar( @{ $dated_stories } ) . " / " . scalar( @{ $stories } ) . " after date restriction";

    return $dated_stories;
}

# start with start_url; for each url, download that url, add any urls that match story_url_pattern to the
# story url list, add any urls that match page_url_pattern to the queue to repeat this process. once we have
# all of the story urls, download each story url and return the list of stories.  only return stories
# between start_date and end_date
sub _scrape_new_stories
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

# get all stories belonging to the media source between the given dates
sub _get_existing_stories
{
    my ( $self ) = @_;

    my $stories = $self->db->query( <<SQL, $self->media_id, $self->start_date, $self->end_date )->hashes;
select
        stories_id, media_id, publish_date, url, guid, title
    from
        stories
    where
        media_id = ? and
        publish_date between ? and ?
SQL

    say STDERR "found " . scalar( @{ $stories } ) . " existing stories" if ( $self->debug );

    return $stories;
}

# return a list of just the new stories that don't have a duplicate in the existing stories
sub _dedup_new_stories
{
    my ( $self, $new_stories ) = @_;

    my $existing_stories = $self->_get_existing_stories();

    my $all_stories = [ @{ $new_stories }, @{ $existing_stories } ];

    my $url_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_url( $self->db, $all_stories );
    my $title_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_title( $self->db, $all_stories );

    my $all_dup_stories = [ @{ $url_dup_stories }, @{ $title_dup_stories } ];

    my $new_stories_lookup = {};
    map { $new_stories_lookup->{ $_->{ url } } = $_ } @{ $new_stories };

    my $dup_new_stories_lookup = {};
    for my $dup_stories ( @{ $all_dup_stories } )
    {
        for my $ds ( @{ $dup_stories } )
        {
            if ( $new_stories_lookup->{ $ds->{ url } } )
            {
                delete( $new_stories_lookup->{ $ds->{ url } } );
                $dup_new_stories_lookup->{ $ds->{ url } } = $ds;
            }
        }

    }

    return ( [ values( %{ $new_stories_lookup } ) ], [ values( %{ $dup_new_stories_lookup } ) ] );
}

# get a dummy feed just to hold the scraped stories because we have to give a feed to each new download
sub _get_scrape_feed
{
    my ( $self ) = @_;

    return $self->scrape_feed if ( $self->scrape_feed );

    my $db = $self->db;

    my $medium = $db->find_by_id( 'media', $self->media_id );

    my $feed_name = 'Scrape Feed';

    my $feed = $db->query( <<SQL, $medium->{ media_id }, $medium->{ url }, $feed_name )->hash;
select * from feeds where media_id = ? and url = ? order by ( name = ? )
SQL

    $feed ||= $db->query( <<SQL, $medium->{ media_id }, $medium->{ url }, $feed_name )->hash;
insert into feeds ( media_id, url, name, feed_status ) values ( ?, ?, ? )
SQL

    $self->scrape_feed( $feed );

    return $feed;
}

# add story to a special 'scrape' feed
sub _add_story_to_scrape_feed
{
    my ( $self, $story ) = @_;

    $self->db->create( 'feeds_stories_map',
        { feeds_id => $self->_get_scrape_feed->{ feeds_id }, stories_id => $story->{ stories_id } } );
}

# add and extract download for story
sub _add_story_download
{
    my ( $self, $story ) = @_;

    my $db = $self->db;

    my $download = {
        feeds_id   => $self->_get_scrape_feed->{ feeds_id },
        stories_id => $story->{ stories_id },
        url        => $story->{ url },
        host       => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
        type       => 'content',
        sequence   => 1,
        state      => 'success',
        path       => 'content:pending',
        priority   => 1,
        extracted  => 't'
    };

    $download = $db->create( 'downloads', $download );

    MediaWords::DBI::Downloads::store_content_determinedly( $db, $download, $self->content );

    eval {
        MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "mediawords_scrape_stories.pl", 0, 1 );
    };

    warn "extract error processing download $download->{ downloads_id }: $@" if ( $@ );
}

# add the stories to the database, including downloads
sub _add_new_stories
{
    my ( $self, $stories ) = @_;

    say STDERR "adding new stories to db ..." if ( $self->debug );

    my $added_stories = [];
    for my $story ( @{ $stories } )
    {
        my $content = $story->{ content };
        delete( $story->{ content } );
        delete( $story->{ normalized_url } );

        eval { $story = $self->db->create( 'stories', $story ) };
        carp( $@ . " - " . Dumper( $story ) ) if ( $@ );

        my $feed = $self->_add_story_to_scrape_feed( $story );

        $self->_add_story_download( $story, $feed );

        push( @{ $added_stories }, $story );
    }
}

# print stories
sub _print_stories
{
    my ( $self, $stories ) = @_;

    for my $s ( sort { $a->{ publish_date } cmp $b->{ publish_date } } @{ $stories } )
    {
        print STDERR <<END;
$s->{ publish_date } - $s->{ title } [$s->{ url }]
END
    }

}

# print list of deduped stories and dup stories
sub _print_story_diffs
{
    my ( $self, $deduped_stories, $dup_stories ) = @_;

    say STDERR "dup stories:" if ( $self->debug );
    $self->_print_stories( $dup_stories ) if ( $self->debug );

    say STDERR "deduped stories:" if ( $self->debug );
    $self->_print_stories( $deduped_stories ) if ( $self->debug );

}

# recursively downoad urls matching page_url_pattern and add any urls that match story_url_pattern to the
# given media source if there are not already duplicates in the media source
sub scrape_stories
{
    my ( $self ) = @_;

    my $new_stories = $self->_scrape_new_stories();

    my ( $deduped_new_stories, $dup_new_stories ) = $self->_dedup_new_stories( $new_stories );

    $self->_print_story_diffs( $deduped_new_stories, $dup_new_stories ) if ( $self->debug );

    my $added_stories = $self->_add_new_stories( $deduped_new_stories ) unless ( $self->dry_run );

    return $added_stories;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
