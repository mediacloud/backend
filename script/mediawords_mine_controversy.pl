#!/usr/bin/env perl

# Run through stories found for the given controversy and find all the links in each story.
# For each link, try to find whether it matches any given story.  If it doesn't, create a
# new story.  Add that story's links to the queue if it matches the pattern for the
# controversy.  Write the resulting stories and links to controversy_stories and controversy_links.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use DateTime;
use Encode;
use HTML::LinkExtractor;
use URI;
use URI::Escape;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::Tags;
use MediaWords::Util::Web;

# number of times to iterate through spider
use constant NUM_SPIDER_ITERATIONS => 500;

# number of times to run through the recursive link weight process
use constant LINK_WEIGHT_ITERATIONS => 3;

# number of links to prefetch at a time for the cache
use constant LINK_CACHE_SIZE => 100;

# tag that will be associate with all controversy_stories at the end of the script
use constant ALL_TAG => 'all';

# these media sources use urls of referred stories for their
# rss item urls, making them confuse the link matching
# this is hacker news, repulickid, and waxy.org links
use constant IGNORE_MEDIA_REFS => ( 6880, 5839, 5968, 5628, 6597 );

# cache of media by media id
my $_media_cache = {};

# list of downloads to precache downloads for
my $_link_downloads_list;

# precached link downloads
my $_link_downloads_cache;

# cache for spidered:spidered tag
my $_spidered_tag;

# cache of media by sanitized url
my $_media_url_lookup;

sub store_download_content
{
    my ( $db, $download, $story_content ) = @_;
    
    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );
    extract_download( $db, $download );    
}

# check to see whether the given download is broken
sub download_is_broken
{
    my ( $db, $download ) = @_;
    
    my $content_ref;
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $download ); };
    
    return 0 if ( $content_ref && ( length( $$content_ref ) > 0 ) );

    return 1;
}


# if there are multiple pages for the download, fix the remaining pages
# after the first one
sub fix_multiple_page_downloads
{
    my ( $db, $downloads ) = @_;
    
    my $broken_downloads = [ grep { download_is_broken( $_ ) } @{ $downloads } ];
    
    return unless ( @{ $broken_downloads } );
    
    my $downloads = $broken_downloads;    
    
    my $urls = [ map { URI->new( $_->{ url } )->as_string } @{ $downloads } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $download_lookup = {};
    map { $download_lookup->{ URI->new( $_->{ url } )->as_string } = $_ } @{ $downloads };

    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $final_url    = $response->request->uri->as_string;
        my $download = $download_lookup->{ $original_url };

        store_download_content( $db, $download, $response->decoded_content );
    }
}

# if this story is one of the ones for which we lost the download, store the given
# response as the download
sub fix_story_download_if_needed
{
    my ( $db, $story, $first_response ) = @_;

    my $downloads = $db->query( "select * from downloads where stories_id = ? order by downloads_id", $story->{ stories_id } )->hashes;
    
    my $first_download = shift( @{ $downloads } ) || return;
    
    if ( download_is_broken( $first_download ) )
    {
        store_download_content( $db, $first_download, $first_response->decoded_content );
    }
    
    return unless ( @{ $downloads } );

    fix_multiple_page_downloads( $db, $downloads );
}

# fetch each link and add a { redirect_url } field if the
# { url } field redirects to another url
sub add_redirect_links
{
    my ( $db, $links ) = @_;

    my $urls = [ map { URI->new( $_->{ url } )->as_string } @{ $links } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $link_lookup = {};
    map { $link_lookup->{ URI->new( $_->{ url } )->as_string } = $_ } @{ $links };

    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $final_url    = $response->request->uri->as_string;
        my $link = $link_lookup->{ $original_url };
        $link->{ redirect_url } = $final_url;
        
        fix_story_download_if_needed( $db, $link, $response );
    }
}

# return a list of all links that appear in the html
sub get_links_from_html
{
    my ( $html ) = @_;

    my $link_extractor = new HTML::LinkExtractor();

    $link_extractor->parse( \$html );

    my $links = [];
    for my $link ( @{ $link_extractor->links } )
    {
        next if ( !$link->{ href } );

        next if ( $link->{ href } !~ /^http/i );

        next if ( $link->{ href } =~ /(ads\.pheedo)|(www.dailykos.com\/user)/ );

        push( @{ $links }, { url => $link->{ href } } );
    }

    return $links;
}

# return true if the media the story belongs to has full_text_rss set to true
sub story_media_has_full_text_rss
{
    my ( $db, $story ) = @_;

    my $media_id = $story->{ media_id };

    my $medium = $_media_cache->{ $story->{ media_id } };
    if ( !$medium )
    {
        $medium = $db->query( "select * from media where media_id = ?", $story->{ media_id } )->hash;
        $_media_cache->{ $story->{ media_id } } = $medium;
    }

    return $medium->{ full_text_rss };
}

# get links at end of boingboing link
sub get_boingboing_links
{
    my ( $db, $story ) = @_;

    my $download = $db->query( "select * from downloads where stories_id = ?", $story->{ stories_id } )->hash;

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $download );

    my $content = ${ $content_ref };

    if ( !( $content =~ s/((<div class="previously2">)|(class="sharePost")).*//ms ) )
    {
        warn( "Unable to find end pattern" );
        return [];
    }

    if ( !( $content =~ s/.*<a href[^>]*>[^<]*<\/a> at\s+\d+\://ms ) )
    {
        warn( "Unable to find begin pattern" );
        return [];
    }

    return get_links_from_html( $content );
}

# find any links in the extracted html or the description of the story.
sub get_links_from_story
{
    my ( $db, $story ) = @_;

    print STDERR "mining $story->{ title } [$story->{ url }] ...\n";

    my $extracted_html;
    eval { $extracted_html = MediaWords::DBI::Stories::get_extracted_html_from_db( $db, $story ); };
    if ( $@ )
    {
        warn( "Unable to get extracted html" );
        return [];
    }

    my $links = get_links_from_html( $extracted_html );

    my $more_links = [];
    if ( story_media_has_full_text_rss( $db, $story ) )
    {
        $more_links = get_links_from_html( $story->{ description } );
    }
    elsif ( $story->{ media_id } == 1720 )
    {
        $more_links = get_boingboing_links( $db, $story );
    }

    return $links if ( !@{ $more_links } );

    my $link_lookup = {};
    map { $link_lookup->{ sanitize_url( $_->{ url } ) } = 1 } @{ $links };
    for my $more_link ( @{ $more_links } )
    {
        next if ( $link_lookup->{ sanitize_url( $more_link->{ url } ) } );
        push( @{ $links }, $more_link );
    }

    # add_redirect_links( $links ) if ( @{ $links } );

    return $links;
}

# do some simple sanitization to try to make links match
sub sanitize_url
{
    my ( $url ) = @_;
    $url = lc( $url );

    $url =~ s/www.//g;

    $url =~ s/\#.*//;

    $url =~ s/\/+$//;

    return URI->new( $url )->as_string;
}

# for each story, return a list of the links found in either the extracted html or the story description
sub generate_controversy_links
{
    my ( $db, $controversy, $stories ) = @_;

    for my $story ( @{ $stories } )
    {
        my $links = get_links_from_story( $db, $story );

        #print STDERR "links found:\n" . join( "\n", map { "  ->" . $_->{ url } } @{ $links } ) . "\n";
        # print Dumper( $links );

        for my $link ( @{ $links } )
        {
            my $link_exists = $db->query(
                "select * from controversy_links where stories_id = ? and url = ? and controversies_id = ?",
                $story->{ stories_id }, encode( 'utf8', $link->{ url } ), $controversy->{ controversies_id }
            )->hash;
            if ( $link_exists )
            {
                print STDERR "    -> dup: $link->{ url }\n";
            }
            else
            {
                print STDERR "    -> new: $link->{ url }\n";
                $db->create(
                    "controversy_links",
                    {
                        stories_id          => $story->{ stories_id },
                        url                 => encode( 'utf8', $link->{ url } ),
                        controversies_id    => $controversy->{ controversies_id }                        
                    }
                );
            }
        }

        $db->query( "update controversy_stories set link_mined = true where stories_id = ? and controversies_id = ?", 
            $story->{ stories_id }, $controversy->{ controversies_id } );
    }
}

# cache link downloads LINK_CACHE_SIZE at a time so that we can do them in parallel.
# this doesn't actually do any caching -- it just sets the list of
# links so that they can be done LINK_CACHE_SIZE at a time by get_cached_link_download.
sub cache_link_downloads
{
    my ( $links ) = @_;

    $_link_downloads_list = $links;

    my $i = 0;
    map { $_->{ _link_num } = $i++ } @{ $links };
}

# if the url has been precached, return it, otherwise download the current links and the next ten links
sub get_cached_link_download
{
    my ( $link ) = @_;

    die( "no { _link_num } field in $link } " ) if ( !defined( $link->{ _link_num } ) );

    my $link_num = $link->{ _link_num };

    # the url gets transformed like this in the ParallelGet below, so we have
    # to transform it here so that we can go back and find the request by the url
    # in the ParalleGet
    my $url = URI->new( $link->{ url } )->as_string;

    if ( my $response = $_link_downloads_cache->{ $url } )
    {
        return ( ref( $response ) ? $response->decoded_content : $response );
    }

    my $links = $_link_downloads_list;
    my $urls  = [];
    for ( my $i = 0 ; $links->[ $link_num + $i ] && $i < LINK_CACHE_SIZE ; $i++ )
    {
        my $link = $links->[ $link_num + $i ];
        push( @{ $urls }, URI->new( $link->{ url } )->as_string );
    }

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        if ( $response->is_success )
        {

            # print STDERR "original_url: $original_url " . length( $response->decoded_content ) . "\n";
            $_link_downloads_cache->{ $original_url } = $response;
        }
        else
        {
            my $msg = "error retrieving content for $original_url: " . $response->status_line;
            warn( $msg );
            $_link_downloads_cache->{ $original_url } = $msg;
        }
    }

    warn( "Unable to find cached download for '$url'" ) if ( !defined( $_link_downloads_cache->{ $url } ) );

    my $response = $_link_downloads_cache->{ $url };
    return ( ref( $response ) ? $response->decoded_content : ( $response || '' ) );
}

# get the redirected url from the cached download for the url.
# if no redirected url is found, just return the given url.
sub get_cached_link_download_redirect_url
{
    my ( $link ) = @_;

    my $url      = URI->new( $link->{ url } )->as_string;
    my $link_num = $link->{ link_num };

    # make sure the $_link_downloads_cache is setup correctly
    get_cached_link_download( $link );

    if ( my $response = $_link_downloads_cache->{ $url } )
    {
        if ( ref( $response ) )
        {
            return $response->request->uri->as_string;
        }
    }

    return $url;
}

# lookup or create the spidered:spidered tag
sub get_spidered_tag
{
    my ( $db ) = @_;

    return $_spidered_tag if ( $_spidered_tag );

    $_spidered_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'spidered:spidered' );

    return $_spidered_tag;
}

# lookup medium by a sanitized url
sub lookup_medium_by_url
{
    my ( $db, $url ) = @_;

    if ( !$_media_url_lookup )
    {
        my $media = $db->query( "select * from media" )->hashes;
        map { $_media_url_lookup->{ sanitize_url( $_->{ url } ) } } @{ $media };
    }

    return $_media_url_lookup->{ sanitize_url( $url ) };
}

# add medium to media_url_lookup
sub add_medium_to_url_lookup
{
    my ( $medium ) = @_;

    $_media_url_lookup->{ sanitize_url( $medium->{ url } ) } = $medium;
}

# return a spider specific media_id for each story.  create a new spider specific medium
# based on the domain of the story url
sub get_spider_medium
{
    my ( $db, $story_url ) = @_;

    if ( !( $story_url =~ m~(http.?://([^/]+))~ ) )
    {
        warn( "Unable to find host name in url: $story_url" );
    }

    my ( $medium_url, $medium_name ) = ( $1, $2 );

    $medium_name =~ s/^www\.//;

    my $medium = $db->query( "select m.* from media m where m.url = ? or m.name = ?", $medium_url, $medium_name )->hash
      || lookup_medium_by_url( $db, $medium_url );

    if ( $medium )
    {
        my $merged_medium = $db->query(
            "select m.* from media m, controversy_merged_media cmm " .
              "  where m.media_id = cmm.target_media_id and cmm.source_media_id = ?",
            $medium->{ media_id }
        )->hash;

        return $merged_medium ? $merged_medium : $medium;
    }

    $medium = {
        name => encode( 'utf8', substr( $medium_name || $story_url, 0, 128 ) ),
        url  => encode( 'utf8', substr( $medium_url  || $story_url, 0, 1024 ) ),
        moderated   => 't',
        feeds_added => 't'
    };

    $medium = $db->create( 'media', $medium );

    print STDERR "add medium: $medium_name / $medium_url / $medium->{ medium_id }\n";

    my $spidered_tag = get_spidered_tag( $db );

    $db->create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $spidered_tag->{ tags_id } } );

    add_medium_to_url_lookup( $medium );

    return $medium;
}

# get the first feed found for the given medium
sub get_spider_feed
{
    my ( $db, $medium ) = @_;

    my $feed_query = "select * from feeds where media_id = ? and url = ?";

    my $feed = $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;
    
    return $feed if ( $feed );

    $db->query(
        "insert into feeds ( media_id, url, last_download_time, name ) " .
          "  values ( ?, ?, now() + interval '10 years', 'Controversy Spider Feed' )",
        $medium->{ media_id },
        $medium->{ url }
    );

    return $db->query( $feed_query, $medium->{ media_id }, $medium->{ url } )->hash;
}

# parse the content for tags that might indicate the story's title
sub get_story_title_from_content
{
    # my ( $content, $url ) = @_;

    if ( $_[ 0 ] =~ m~<meta property=\"og:title\" content=\"([^\"]+)\"~si ) { return $1; }

    if ( $_[ 0 ] =~ m~<meta property=\"og:title\" content=\'([^\']+)\'~si ) { return $1; }

    if ( $_[ 0 ] =~ m~<title>([^<]+)</title>~si ) { return $1; }

    return $_[ 1 ];
}

# return true if the args are valid date arguments.  assume a date has to be between 2000 and 2040.
sub valid_date_parts
{
    my ( $year, $month, $day ) = @_;

    return 0 if ( ( $year < 2000 ) || ( $year > 2040 ) );

    return Date::Parse::str2time( "$year-$month-$day" );
}

# guess publish date from the story and content.  failsafe is to use the
# date of the linking story
sub guess_publish_date
{
    #my ( $db, $link, $html ) = @_;
    my ( $db, $link ) = @_;

    if ( $_[ 2 ] =~ m~<time \s+datetime=\"([^\"]+)\"\s+pubdate~is ) { return $1; }
    if ( $_[ 2 ] =~ m~<time \s+datetime=\'([^\']+)\'\s+pubdate~is ) { return $1; }

    if ( ( $link->{ url } =~ m~(20\d\d)/(\d\d)/(\d\d)~ ) || ( $link->{ redirect_url } =~ m~(20\d\d)/(\d\d)/(\d\d)~ ) )
    {
        return "$1-$2-$3" if ( valid_date_parts( $1, $2, $3 ) );
    }

    if ( ( $link->{ url } =~ m~/(20\d\d)(\d\d)(\d\d)/~ ) || ( $link->{ redirect_url } =~ m~(20\d\d)(\d\d)(\d\d)~ ) )
    {
        return "$1-$2-$3" if ( valid_date_parts( $1, $2, $3 ) );
    }

    return $db->find_by_id( 'stories', $link->{ stories_id } )->{ publish_date };
}

# extract the story for the given download
sub extract_download
{
    my ( $db, $download ) = @_;

    return if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4$/i );

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "controversy", 1 ); };
    warn "extract error processing download $download->{ downloads_id }" if ( $@ );
}

# add a new story and download corresponding to the given link
sub add_new_story
{
    my ( $db, $link ) = @_;

    my $story_url = $link->{ redirect_url } || $link->{ url };
    if ( length( $story_url ) > 1024 )
    {
        $story_url = substr( $story_url, 0, 1024 );
    }

    my $story_content = get_cached_link_download( $link );

    my $medium = get_spider_medium( $db, $story_url );
    my $feed = get_spider_feed( $db, $medium );

    my $title = get_story_title_from_content( $story_content, $story_url );

    my $publish_date = guess_publish_date( $db, $link, $story_content );

    my $story = {
        url          => $story_url,
        guid         => $story_url,
        media_id     => $medium->{ media_id },
        publish_date => $publish_date,
        collect_date => DateTime->now->datetime,
        title        => encode( 'utf8', $title ),
        description  => ''
    };

    $story = $db->create( 'stories', $story );

    my $spidered_tag = get_spidered_tag( $db );
    $db->create( 'stories_tags_map', { stories_id => $story->{ stories_id }, tags_id => $spidered_tag->{ tags_id } } );

    print STDERR "add story: $title / $story->{ url } / $publish_date / $story->{ stories_id }\n";

    #$db->create( 'feeds_stories_map', { feeds_id => $feed->{ feeds_id }, stories_id => $story->{ stories_id } } );

    my $download = {
        feeds_id      => $feed->{ feeds_id },
        stories_id    => $story->{ stories_id },
        url           => $story->{ url },
        host          => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
        type          => 'content',
        sequence      => 1,
        state         => 'success',
        path          => 'content:pending',
        priority      => 1,
        download_time => DateTime->now->datetime,
        extracted     => 't'
    };

    $download = $db->create( 'downloads', $download );

    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );

    ( $db, $download );

    return $story;
}

# return true if the story_sentences for the controversy search pattern
sub story_matches_controversy_pattern
{
    my ( $db, $controversy, $story, $metadata_only ) = @_;

    my $query_story_search = $db->find_by_id( 'query_story_searches', $controversy->{ query_story_searches_id } );

    my $perl_re = $query_story_search->{ pattern };
    $perl_re =~ s/\[\[\:[\<\>]\:\]\]/[^a-z]/g;
    if ( "$story->{ title } $story->{ description } $story->{ url } $story->{ redirect_url }" =~ /$perl_re/is )
    {
        return 1;
    }

    return 0 if ( $metadata_only );

    my $query =
      "select 1 from story_sentences ss where ss.stories_id = $story->{ stories_id } and " .
      "    lower( ss.sentence ) ~ ?";

    # print STDERR "match query: $query\n";

    my ( $matches_pattern ) = $db->query( $query, $query_story_search->{ pattern } )->flat;

    # print STDERR "MATCH\n" if ( $matches_pattern );

    return $matches_pattern;
}

# add story to controversy_stories table and mine for controversy_links
sub add_to_controversy_stories_and_links
{
    my ( $db, $controversy, $story, $iteration ) = @_;

    $db->query(
        "insert into controversy_stories ( controversies_id, stories_id, iteration, redirect_url ) " . "  values ( ?, ?, ?, ? )",
        $controversy->{ controversies_id }, $story->{ stories_id }, $iteration, $story->{ url }
    );

    generate_controversy_links( $db, $controversy, [ $story ] );
}

# look for any other links in the list of links that match the given story and
# assign ref_stories_id to them
sub update_other_matching_links
{
    my ( $db, $controversy, $story, $links ) = @_;

    my $su = sanitize_url( $story->{ url } );

    for my $link ( @{ $links } )
    {
        my $lu  = sanitize_url( $link->{ url } );
        my $lru = sanitize_url( $link->{ redirect_url } );

        if ( ( $lu eq $su ) || ( $lru eq $su ) )
        {
            $link->{ ref_stories_id } = $story->{ stories_id };
            $db->query(
                "update controversy_links set ref_stories_id = ? where controversy_links_id = ? and controversies_id = ?",
                $story->{ stories_id }, $link->{ controversy_links_id }, $controversy->{ controversies_id }
            );
        }
    }
}

# look for a story matching the link url in the db
sub get_matching_story_from_db
{
    my ( $db, $link ) = @_;

    my $u = substr( $link->{ url }, 0, 1024 );
    my $ru = substr( $link->{ redirect_url }, 0, 1024 ) || $u;

    my $ignore_media_list = join( ",", IGNORE_MEDIA_REFS );

    my $story =
      $db->query( "select s.* from stories s " .
          "  where ( s.url in ( ? , ? ) or s.guid in ( ?, ? ) ) and s.media_id not in ( $ignore_media_list )",
        $u, $ru, $u, $ru )->hash;

    if ( $story )
    {
        my $downloads = $db->query( "select * from downloads where stories_id = ? and extracted = 'f' order by downloads_id",
            $story->{ stories_id } )->hashes;
        map { extract_download( $db, $_ ) } @{ $downloads };
    }

    return $story;
}

# return true if the story is already in controversy_stories
sub story_is_controversy_story
{
    my ( $db, $controversy, $story ) = @_;

    my ( $is_old ) = $db->query( "select 1 from controversy_stories where stories_id = ? and controversies_id = ?", 
        $story->{ stories_id }, $controversy->{ controversies_id } )->flat;

    print STDERR "EXISTING CONTROVERSY STORY\n" if ( $is_old );

    return $is_old;
}

# get the redirect url for the link, add it to the hash, and save it in the db
sub add_redirect_url_to_link
{
    my ( $db, $link ) = @_;

    $link->{ redirect_url } = get_cached_link_download_redirect_url( $link );

    $db->query(
        "update controversy_links set redirect_url = ? where controversy_links_id = ?",
        encode( 'utf8', $link->{ redirect_url } ), $link->{ controversy_links_id }
    );
}

# if the story matches the controversy pattern, add it to controversy_stories and controversy_links
sub add_to_controversy_stories_and_links_if_match
{
    my ( $db, $controversy, $story, $link ) = @_;

    if ( !story_is_controversy_story( $db, $controversy, $story ) && story_matches_controversy_pattern( $db, $controversy, $story ) )
    {
        print STDERR "CONTROVERSY MATCH: $link->{ url }\n";
        add_to_controversy_stories_and_links( $db, $controversy, $story, $link->{ iteration } + 1 );
    }

    $db->query(
        "update controversy_links set ref_stories_id = ? where controversy_links_id = ?",
        $story->{ stories_id },
        $link->{ controversy_links_id }
    );
}

# download any unmatched link, add it as a story, extract it, add any links to the controversy_links list
sub spider_new_links
{
    my ( $db, $controversy, $iteration ) = @_;

    my $new_links = $db->query(
        "select distinct cs.iteration, cl.* from controversy_links cl, controversy_stories cs " .
          "  where cl.ref_stories_id is null and cl.stories_id = cs.stories_id and cs.iteration < ? and " . 
          "    cs.controversies_id = ? and cl.controversies_id = ? ",
        $iteration, $controversy->{ controversies_id }, $controversy->{ controversies_id }
    )->hashes;

    # find all the links that we can find existing stories for without having to fetch anything
    my $fetch_links = [];
    for my $link ( @{ $new_links } )
    {
        next if ( $link->{ ref_stories_id } );

        print STDERR "spidering $link->{ url } ...\n";

        if ( my $story = get_matching_story_from_db( $db, $link ) )
        {
            add_to_controversy_stories_and_links_if_match( $db, $controversy, $story, $link );
        }
        else
        {
            push( @{ $fetch_links }, $link );
        }

    }

    cache_link_downloads( $fetch_links );

    for my $link ( @{ $fetch_links } )
    {
        next if ( $link->{ ref_stories_id } );

        print STDERR "fetch spidering $link->{ url } ...\n";

        add_redirect_url_to_link( $db, $link );
        my $story = get_matching_story_from_db( $db, $link ) || add_new_story( $db, $link );

        add_to_controversy_stories_and_links_if_match( $db, $controversy, $story, $link );
    }
}

# run the spider over any new links, for $num_iterations iterations
sub run_spider
{
    my ( $db, $controversy, $num_iterations ) = @_;

    for my $i ( 1 .. $num_iterations )
    {
        spider_new_links( $db, $controversy, $i );
    }
}

# run through controversy_links and make sure there are no duplicate stories_id, ref_stories_id dups
sub delete_duplicate_controversy_links
{
    my ( $db, $controversy ) = @_;

    my $duplicate_links =
      $db->query( 
          "select count(*), stories_id, ref_stories_id from controversy_links " .
          "  where ref_stories_id is not null and controversies_id = ? " .
          "  group by stories_id, ref_stories_id having count(*) > 1",
          $controversy->{ controversies_id } )->hashes;

    for my $duplicate_link ( @{ $duplicate_links } )
    {
        # print STDERR "duplicate: " . Dumper( $duplicate_link );
        my $ids = [
            $db->query(
                "select controversy_links_id from controversy_links " .
                "  where stories_id = ? and ref_stories_id = ? and controversies_id = ?",
                $duplicate_link->{ stories_id },
                $duplicate_link->{ ref_stories_id },
                $controversy->{ controversies_id }
              )->flat
        ];

        shift( @{ $ids } );
        map { $db->query( "delete from controversy_links where controversy_links_id = ?", $_ ) } @{ $ids };
    }
}

# make sure every controversy story has a redirect url, even if it is just the original url
sub add_redirect_urls_to_controversy_stories
{
    my ( $db, $controversy ) = @_;

    my $stories = $db->query( 
        "select distinct s.* from stories s, controversy_stories cs " .
        "  where s.stories_id = cs.stories_id and cs.redirect_url is null and cs.controversies_id = ?",
        $controversy->{ controversies_id } )->hashes;

    add_redirect_links( $db, $stories );
    for my $story ( @{ $stories } )
    {
        $db->query(
            "update controversy_stories set redirect_url = ? where stories_id = ? and controversies_id = ?",
            $story->{ redirect_url },
            $story->{ stories_id },
            $controversy->{ controversies_id }
        );
    }
}

# mine for links any stories in controversy_stories for this controversy that have not already been mined
sub mine_controversy_stories
{
    my ( $db, $controversy ) = @_;

    my $stories =
      $db->query( 
          "select distinct s.*, cs.link_mined, cs.redirect_url from stories s, controversy_stories cs " . 
          "  where s.stories_id = cs.stories_id and cs.link_mined = 'f' and cs.controversies_id = ? " .
          "  order by s.publish_date",
          $controversy->{ controversies_id } )->hashes;

    generate_controversy_links( $db, $controversy, $stories );
}

# hit every pending controversy link.  this can be useful to get a caching proxy to cache 
# all of the links.
sub cache_all_link_urls
{
    my ( $db, $controversy ) = @_;

    my $links = $db->query( 
        "select url from controversy_links where ref_stories_id is null order by controversy_links_id",
        $controversy->{ controversies_id } )->hashes;

    my $urls = [ map { $_->{ url } } @{ $links } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
}

# reset the STORY_TAG tag to point to all stories in controversy_stories
sub update_controversy_tags
{
    my ( $db, $controversy ) = @_;

    my $tagset_name = "Controversy $controversy->{ name }";

    my $all_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$tagset_name:all" ) ||
        die( "Can't find or create all_tag" );

    $db->query(
        "delete from stories_tags_map where tags_id = ? and stories_id not in " . 
        "      ( select stories_id from controversy_stories where controversies_id = ? )",
        $all_tag->{ tags_id }, $controversy->{ controversies_id } );

    $db->query(
        "insert into stories_tags_map ( stories_id, tags_id ) " .
          "  select distinct stories_id, $all_tag->{ tags_id } from controversy_stories " .
          "    where controversies_id = ? and " . 
          "      stories_id not in ( select stories_id from stories_tags_map where tags_id = ? )",
          $controversy->{ controversies_id },
          $all_tag->{ tags_id }
    );

    my $q_tagset_name = $db->dbh->quote( $tagset_name );
    $db->query( 
        "delete from stories_tags_map using tags t, tag_sets ts " . 
        "  where stories_tags_map.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id and " .
        "    ts.name = $q_tagset_name and stories_tags_map.stories_id not in " . 
        "      ( select stories_id from controversy_stories where controversies_id = ? )",
        $controversy->{ controversies_id } );    
}

# increase the link_weight of each story to which this story links and recurse along links from those stories.
# the link_weight gets increment by ( 1 / path_depth ) so that stories further down along the link path
# get a smaller increment than more direct links.
sub add_link_weights
{
    my ( $story, $stories_lookup, $path_depth, $link_path_lookup ) = @_;

    $story->{ link_weight } += ( 1 / $path_depth ) if ( !$path_depth );

    return if ( !@{ $story->{ links } } );

    $link_path_lookup->{ $story->{ stories_id } } = 1;

    for my $link ( @{ $story->{ links } } )
    {
        next if ( $link_path_lookup->{ $link->{ ref_stories_id } } );

        my $linked_story = $stories_lookup->{ $link->{ ref_stories_id } };
        add_link_weights( $linked_story, $stories_lookup, $path_depth++, $link_path_lookup );
    }
}

# get stories with a { source_stories } field that is a list
# of links to stories linking to that story
sub get_stories_with_sources
{
    my ( $db, $controversy ) = @_;

    my $links   = $db->query( 
        "select * from controversy_links_cross_media where controversies_id = ?",
        $controversy->{ controversies_id } )->hashes;
    my $stories = $db->query( 
        "select s.* from controversy_stories cs, stories s " . 
        "  where s.stories_id = cs.stories_id and cs.controversies_id = ?", 
        $controversy->{ controversies_id } )->hashes;

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    for my $link ( @{ $links } )
    {
        my $ref_story = $stories_lookup->{ $link->{ ref_stories_id } };
        push( @{ $ref_story->{ source_stories } }, $stories_lookup->{ $link->{ stories_id } } );
    }

    return $stories;
}

# get the minimum publish date of all the source link stories for this story
sub get_min_source_publish_date
{
    my ( $min, $story, $story_path_lookup ) = @_;

    next if ( $story_path_lookup->{ $story->{ stories_id } } );

    $story_path_lookup->{ $story->{ stories_id } } = 1;

    for my $source_story ( @{ $story->{ source_stories } } )
    {
        next if ( $source_story->{ publish_date } !~ /^20/ );

        $min = $source_story->{ publish_date } if ( $source_story->{ publish_date } lt $min );

        $min = get_min_source_publish_date( $min, $source_story, $story_path_lookup );
    }

    return $min;
}

# for each cross media controversy link, add a text similarity score that is the cos sim 
# of the text of the source and ref stories.  assumes the $stories argument comes
# with each story with a { source_stories } field that includes all of the source
# stories for that ref story
sub generate_link_text_similarities
{
    my ( $db, $controversy, $stories ) = @_;
    
    for my $story ( @{ $stories } )
    {
        for my $source_story ( @{ $story->{ source_stories } } )
        {
            my $has_sim = $db->query( 
                "select 1 from controversy_links " . 
                "  where stories_id = ? and ref_stories_id = ? and text_similarity > 0 and controversies_id = ?", 
                $source_story->{ stories_id }, $story->{ stories_id }, $controversy->{ controversies_id } )->list;
            next if ( $has_sim );
            
            MediaWords::DBI::Stories::add_word_vectors( $db, [ $story, $source_story ], 1 );
            MediaWords::DBI::Stories::add_cos_similarities( $db, [ $story, $source_story ] );

            my $sim = $story->{ similarities }->[ 1 ];
            
            print STDERR "link sim:\n\t$story->{ title } [ $story->{ stories_id } ]\n" . 
                "\t$source_story->{ title } [ $source_story->{ stories_id } ]\n\t$sim\n\n";
            
            $db->query( 
                "update controversy_links set text_similarity = ? " . 
                "  where stories_id = ? and ref_stories_id = ? and controversies_id = ?",
                $sim, $source_story->{ stories_id }, $story->{ stories_id }, $controversy->{ controversies_id } );
                
            map { $_->{ similarities } = undef } ( $story, $source_story );
        }
    }
}

# generate a link weight score for each cross media controversy_link
# by adding a point for each incoming link, then adding the some of the
# link weights of each link source divided by the ( iteration * 10 ) of the recursive
# weighting (so the first reweighting run will add 1/10 the weight of the sources,
# the second 1/20 of the weight of the sources, and so on)
sub generate_link_weights
{
    my ( $db, $controversy, $stories ) = @_;

    map { $_->{ source_stories } ||= []; } @{ $stories };
    map { $_->{ link_weight } = @{ $_->{ source_stories } } } @{ $stories };

    for my $i ( 1 .. LINK_WEIGHT_ITERATIONS )
    {
        for my $story ( @{ $stories } )
        {
            map { $story->{ link_weight } += ( $_->{ link_weight } / ( $i * 10 ) ) } @{ $story->{ source_stories } };
        }
    }

    for my $story ( @{ $stories } )
    {
        $db->query(
            "update controversy_stories set link_weight = ? where stories_id = ? and controversies_id = ?",
            $story->{ link_weight } || 0,
            $story->{ stories_id },
            $controversy->{ controversies_id }
        );
    }
}

sub main
{
    my ( $controversies_id ) = @ARGV;

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    die( "usage: $0 < controversies_id >" ) unless ( $controversies_id );

    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) ||
        die( "Unable to find controversy '$controversies_id'" );
    
    # cache_all_link_urls( $db, $controversy );
    # return;

    print STDERR "deleting duplicate controversy links ...\n";
    delete_duplicate_controversy_links( $db, $controversy );

    print STDERR "adding redirect urls to controversy stories ...\n";
    add_redirect_urls_to_controversy_stories( $db, $controversy );

    print STDERR "mining controversy stories ...\n";
    mine_controversy_stories( $db, $controversy );

    print STDERR "running spider ...\n";
    run_spider( $db, $controversy, NUM_SPIDER_ITERATIONS );

    print STDERR "deleting duplicate controversy links ...\n";
    delete_duplicate_controversy_links( $db, $controversy );

    print STDERR "updating story_tags ...\n";
    update_controversy_tags( $db, $controversy );

    my $stories = get_stories_with_sources( $db, $controversy );        

    print STDERR "generating link weights ...\n";
    generate_link_weights( $db, $controversy, $stories );
    
    # print STDERR "generating link text similarities ...\n";
    # generate_link_text_similarities( $db, $stories );
}

main();
