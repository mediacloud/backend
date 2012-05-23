#!/usr/bin/env perl

# Run through stories found for sopa study and find all the links in each story.
# For each link, try to find whether it matches any given story.  Write the 
# resulting links to sopa_stories.

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
use constant NUM_SPIDER_ITERATIONS => 100;

# number of times to run through the recursive link weight process
use constant LINK_WEIGHT_ITERATIONS => 3;

# number of links to prefetch at a time for the cache
use constant LINK_CACHE_SIZE => 100;

# tag that will be associate with all sopa_stories at the end of the script
use constant SOPA_ALL_TAG => 'sopa:all';

# tagset that is used for tags that represent keyword searches within the 
# sopa_stories.  all stories_tags_maps entires pointing to these tags will
# be cleared of all stories not in sopa_stories at the end of the script.
use constant SOPA_KEYWORD_TAGSET => 'sopa';

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

# cache for spidered:sopa tag
my $_spidered_sopa_tag;

# cache of media by sanitized url
my $_media_url_lookup;

# fetch each link and add a { redirect_url } field if the 
# { url } field redirects to another url
sub add_redirect_links
{
    my ( $links ) = @_;
    
    my $urls = [ map { URI->new( $_->{ url } )->as_string } @{ $links } ];
    
    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
    
    my $link_lookup = {};
    map { $link_lookup->{ URI->new( $_->{ url } )->as_string } = $_ } @{ $links };
    
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $final_url = $response->request->uri->as_string;
        $link_lookup->{ $original_url }->{ redirect_url } = $final_url;
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
        
    my $extracted_html = MediaWords::DBI::Stories::get_extracted_html_from_db( $db, $story );
        
    my $links = get_links_from_html( $extracted_html );
    
    my $more_links = [];
    if ( story_media_has_full_text_rss( $db, $story ) )
    {
        $more_links = get_links_from_html( $story->{ description } );
    } 
    elsif ( $story->{ media_id } == 1720 ) {        
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
sub generate_sopa_links
{
    my ( $db, $stories ) = @_;
    
    for my $story ( @{ $stories } )
    {
        my $links = get_links_from_story( $db, $story );
        
        #print STDERR "links found:\n" . join( "\n", map { "  ->" . $_->{ url } } @{ $links } ) . "\n";
        # print Dumper( $links );
        
        #$db->query( "delete from sopa_links where stories_id = ?", $story->{ stories_id } );
        
        for my $link ( @{ $links } )
        {
            my $link_exists = $db->query( 
                "select * from sopa_links where stories_id = ? and url = ?",
                $story->{ stories_id }, encode( 'utf8', $link->{ url } ) )->hash;
            if ( $link_exists )
            {
                print STDERR "    -> dup: $link->{ url }\n";
            }
            else {
                print STDERR "    -> new: $link->{ url }\n";
                $db->create( "sopa_links", { 
                    stories_id => $story->{ stories_id },
                    url => encode( 'utf8', $link->{ url } ) } );
            }
        }
        
        $db->query( "update sopa_stories set link_mined = true where stories_id = ?", $story->{ stories_id } );
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
    
    die ( "no { _link_num } field in $link } " ) if ( !defined( $link->{ _link_num } ) );

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
    my $urls = []; 
    for ( my $i = 0; $links->[ $link_num + $i ] && $i < LINK_CACHE_SIZE; $i++ )
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
        else {
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
    
    my $url = URI->new( $link->{ url } )->as_string;
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

# lookup or create the spidered:sopa tag
sub get_spidered_sopa_tag
{
    my ( $db ) = @_;
    
    return $_spidered_sopa_tag if ( $_spidered_sopa_tag );
    
    $_spidered_sopa_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'spidered:sopa' );
    
    return $_spidered_sopa_tag;
}


# lookup medium by a sanitized url
sub lookup_medium_by_url
{
    my ( $db, $url) = @_;
    
    if ( !$_media_url_lookup )
    {
        my $media = $db->query( "select * from media" );
        map { $_media_url_lookup->{ sanitize_url( $_->{ url } ) } } @{ $media };
    }
    
    return $_media_url_lookup->{ sanitize_url( $url ) };
}

# add medium to media_url_lookup
sub add_medium_to_url_lookup
{
    my ( $medium ) = @_;
    
    $_media_url_lookup->{ sanitize_url->{ $medium->{ url } } } = $medium;
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
    
    my $medium = $db->query( "select m.* from media m where m.url = ? or m.name = ?", $medium_url, $medium_name )->hash ||
        lookup_medium_by_url( $db, $medium_url );    
    
    if ( $medium )
    {
        my $merged_medium = $db->query( 
            "select m.* from media m, sopa_merged_media smm " . 
            "  where m.media_id = smm.target_media_id and smm.source_media_id = ?",
            $medium->{ media_id } )->hash;
            
        return $merged_medium ? $merged_medium : $medium;
    }

    $medium = {
        name => encode( 'utf8', substr( $medium_name || $story_url, 0, 128) ),
        url => encode( 'utf8', substr( $medium_url || $story_url, 0, 1024) ),
        moderated => 't',
        feeds_added => 't' };
        
    $medium = $db->create( 'media', $medium );
    
    print STDERR "add medium: $medium_name / $medium_url / $medium->{ medium_id }\n";
    
    my $spidered_sopa_tag = get_spidered_sopa_tag( $db );
    
    $db->create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $spidered_sopa_tag->{ tags_id } } );
    
    add_medium_to_url_lookup( $medium );
        
    return $medium;
}

# get the first feed found for the given medium
sub get_spider_feed
{
    my ( $db, $medium ) = @_;
    
    my $feed_query = "select * from feeds where media_id = ? and name = 'Sopa Spider Feed'" ;
    
    my $feed = $db->query( $feed_query, $medium->{ media_id } )->hash;
    return $feed if ( $feed );
    
    $db->query( 
        "insert into feeds ( media_id, url, last_download_time, name ) " . 
        "  values ( ?, ?, now() + interval '10 years', 'Sopa Spider Feed' )",
        $medium->{ media_id }, $medium->{ url } );
        
    return $db->query( $feed_query, $medium->{ media_id } )->hash;
    
}

# parse the content for tags that might indicate the story's title
sub get_story_title_from_content
{
    # my ( $content, $url ) = @_;
    
    if ( $_[0] =~ m~<meta property=\"og:title\" content=\"([^\"]+)\"~si ) { return $1; }

    if ( $_[0] =~ m~<meta property=\"og:title\" content=\'([^\']+)\'~si ) { return $1; }

    if ( $_[0] =~ m~<title>([^<]+)</title>~si ) { return $1; }
    
    return $_[1];
}

# return true if the args are valid date arguments.  assume a date has to be between 2000 and 2020.
sub valid_date_parts
{
    my ( $year, $month, $day ) = @_;
    
    return 0 if ( ( $year < 2000 ) || ( $year > 2020 ) );
    
    return Date::Parse::str2time( "$year-$month-$day" );
}


# guess publish date from the story and content.  failsafe is to use the
# date of the linking story
sub guess_publish_date
{
    my ( $db, $link ) = @_;
    
    if ( $_[2] =~ m~<time \s+datetime=\"([^\"]+)\"\s+pubdate~is ) { return $1; }
    if ( $_[2] =~ m~<time \s+datetime=\'([^\']+)\'\s+pubdate~is ) { return $1; }

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
    
    eval {
        MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "sopa" );
    };
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

    my $spidered_sopa_tag = get_spidered_sopa_tag( $db );
    $db->create( 'stories_tags_map', { stories_id => $story->{ stories_id }, tags_id => $spidered_sopa_tag->{ tags_id } } );
 
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
        extracted     => 't' };
    
    $download = $db->create( 'downloads', $download );
    
    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );
    
    extract_download( $db, $download );

    return $story;
}

# return true if the story_sentences for the story match any of the sopa patterns
sub story_matches_sopa_keywords
{
    my ( $db, $story, $metadata_only ) = @_;
    
    my $keyword_pattern = 
        '[[:<:]]sopa[[:>:]]|stop[[:space:]]+online[[:space:]]+privacy[[:space:]]+act|' .
        '[[:<:]]acta[[:>:]]|anti-counterfeiting[[:space:]]+trade[[:space:]]+agreement|' .
        '[[:<:]]coica[[:>:]]|combating[[:space:]]+online[[:space:]]+infringement[[:space:]]+and[[:space:]]+counterfeits[[:space:]]+act|' . 
        '[[:<:]]pipa[[:>:]]|protect[[:space:]]+ip[[:space:]]+act';
    
    my $perl_re = $keyword_pattern;
    $perl_re =~ s/\[\[\:[\<\>]\:\]\]/[^a-z]/g;
    if ( "$story->{ title } $story->{ description } $story->{ url } $story->{ redirect_url }" =~ /$perl_re/is )
    {
        return 1;
    }
    
    return 0 if ( $metadata_only );
    
    my $query =
        "select 1 from story_sentences ss where ss.stories_id = $story->{ stories_id } and " . 
        "    lower( ss.sentence ) ~ '$keyword_pattern'";

    # print STDERR "match query: $query\n";
    
    my ( $matches_sopa ) = $db->query( $query )->flat;
    
    # print STDERR "MATCH\n" if ( $matches_sopa );
        
    return $matches_sopa;
}

# add story to sopa_stories table and mine for sopa_links
sub add_to_sopa_stories_and_links
{
    my ( $db, $story, $iteration ) = @_;
 
    $db->query( 
        "insert into sopa_stories ( stories_id, iteration, redirect_url ) " .
        "  values ( ?, ?, ? )", $story->{ stories_id }, $iteration, $story->{ url } );
        
    generate_sopa_links( $db, [ $story ] );
}

# look for any other links in the list of links that match the given story and 
# assign ref_stories_id to them
sub update_other_matching_links
{
    my ( $db, $story, $links ) = @_;
    
    my $su = sanitize_url( $story->{ url } );
    
    for my $link ( @{ $links } )
    {
        my $lu = sanitize_url( $link->{ url } );
        my $lru = sanitize_url( $link->{ redirect_url } );
    
        if ( ( $lu eq $su ) || ( $lru eq $su ) )
        {
            $link->{ ref_stories_id } = $story->{ stories_id };        
            $db->query( "update sopa_links set ref_stories_id = ? where sopa_links_id = ?", $story->{ stories_id }, $link->{ sopa_links_id } );
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
    
    my $story = $db->query( 
        "select s.* from stories s " . 
        "  where ( s.url in ( ? , ? ) or s.guid in ( ?, ? ) ) and s.media_id not in ( $ignore_media_list )" , 
        $u, $ru, $u, $ru )->hash;
    
    if ( $story )
    {
        my $downloads = $db->query( 
            "select * from downloads where stories_id = ? and extracted = 'f' order by downloads_id",  
            $story->{ stories_id } )->hashes;
        map { extract_download( $db, $_ ) } @{ $downloads };
    }             
    
    return $story;   
}

# return true if the story is already in sopa_stories
sub story_is_sopa_story
{
    my ( $db, $story ) = @_;
    
    my ( $is_old ) = $db->query( "select 1 from sopa_stories where stories_id = ?", $story->{ stories_id } )->flat;
    
    print STDERR "EXISTING SOPA STORY\n" if ( $is_old );
    
    return $is_old;
}

# get the redirect url for the link, add it to the hash, and save it in the db
sub add_redirect_url_to_link
{
    my ( $db, $link ) = @_;
    
    $link->{ redirect_url } = get_cached_link_download_redirect_url( $link );
    
    $db->query( 
        "update sopa_links set redirect_url = ? where sopa_links_id = ?", 
        encode( 'utf8', $link->{ redirect_url } ), $link->{ sopa_links_id } );
}

# if the story matches the sopa keywords, add it to sopa_stories and sopa_links
sub add_to_sopa_stories_and_links_if_match
{
    my ( $db, $story, $link ) = @_;
    
    if ( !story_is_sopa_story( $db, $story ) && story_matches_sopa_keywords( $db, $story ) )
    {
        print STDERR "SOPA MATCH: $link->{ url }\n";
        add_to_sopa_stories_and_links( $db, $story, $link->{ iteration } + 1 );                
    }

    $db->query( "update sopa_links set ref_stories_id = ? where sopa_links_id = ?", $story->{ stories_id }, $link->{ sopa_links_id } ); 
}

# download any unmatched link, add it as a story, extract it, add any links to the sopa links list
sub spider_new_links
{
    my ( $db, $iteration ) = @_;
    
    my $new_links = $db->query( 
        "select distinct ss.iteration, sl.* from sopa_links sl, sopa_stories ss " . 
        "  where sl.ref_stories_id is null and sl.stories_id = ss.stories_id and ss.iteration < ?", 
        $iteration )->hashes;
    
    # find all the links that we can find existing stories for without having to fetch anything
    my $fetch_links = [];
    for my $link ( @{ $new_links } )
    {
        next if ( $link->{ ref_stories_id } );
        
        print STDERR "spidering $link->{ url } ...\n";

        if ( my $story = get_matching_story_from_db( $db, $link ) )
        {
            add_to_sopa_stories_and_links_if_match( $db, $story, $link );            
        }
        else {
            push( @{ $fetch_links }, $link );
        }
        
    }
    
    cache_link_downloads( $fetch_links );
    
    for my $link ( @{ $fetch_links } )
    {
        next if ( $link->{ ref_stories_id } );
        
        print STDERR "fetch spidering $link->{ url } ...\n";

        add_redirect_url_to_link( $db, $link );
        my $story = get_matching_story_from_db( $db, $link ) || add_new_story( $db, $link  );
        
        add_to_sopa_stories_and_links_if_match( $db, $story, $link );
    }
}

# run the spider over any new links, for $num_iterations iterations
sub run_spider
{
    my ( $db, $num_iterations ) = @_;
    
    for my $i ( 1 .. $num_iterations )
    {
        spider_new_links( $db, $i );
    }
}

# run through sopa_links and make sure there are no duplicate stories_id, ref_stories_id dups
sub delete_duplicate_sopa_links
{
    my ( $db ) = @_;
    
    my $duplicate_links = $db->query( 
        "select count(*), stories_id, ref_stories_id from sopa_links where ref_stories_id is not null "  .
        "  group by stories_id, ref_stories_id having count(*) > 1" )->hashes;
    
    for my $duplicate_link ( @{ $duplicate_links } ) 
    {
        # print STDERR "duplicate: " . Dumper( $duplicate_link );
        my $ids = [ $db->query( 
            "select sopa_links_id from sopa_links where stories_id = ? and ref_stories_id = ?", 
            $duplicate_link->{ stories_id }, $duplicate_link->{ ref_stories_id } )->flat ];
            
        shift( @{ $ids } );
        map { $db->query( "delete from sopa_links where sopa_links_id = ?", $_ ) } @{ $ids };
    }
}

# make sure every sopa story has a redirect url, even if it is just the original url
sub add_redirect_urls_to_sopa_stories
{
    my ( $db ) = @_;
    
    my $stories = $db->query( 
        "select distinct s.* from stories s, sopa_stories ss " .
        "  where s.stories_id = ss.stories_id and ss.redirect_url is null " )->hashes;
    
    add_redirect_links( $stories );
    for my $story ( @{ $stories } )
    {
        $db->query( "update sopa_stories set redirect_url = ? where stories_id = ?", $story->{ redirect_url }, $story->{ stories_id } ); 
    }
}

# mine for links any stories in sopa_stories that have not already been mined
sub mine_sopa_stories
{
    my ( $db ) = @_;
    
    my $stories = $db->query( 
        "select distinct s.*, ss.link_mined, ss.redirect_url " .
        "  from stories s, sopa_stories ss where s.stories_id = ss.stories_id and ss.link_mined = 'f'" . 
        "  order by s.publish_date" )->hashes;
    
    generate_sopa_links( $db, $stories );
}

# fix broken links after I stupidly deleted them
sub relink_broken_stories
{
    my ( $db ) = @_;
    
    my $stories = $db->query( 
        "select distinct s.*, ss.link_mined, ss.redirect_url " . 
        "  from stories s, sopa_stories ss, sopa_links sl "  .
        "  where s.stories_id = ss.stories_id and ss.stories_id = sl.stories_id and sl.ref_stories_id is null" . 
        "  order by sl.sopa_links_id" )->hashes;

    generate_sopa_links( $db, $stories );
}

# rerun all stories in sopa_links.ref_stories_id that were not already sopa matched
# to test against new title / description / url matching
sub rematch_sopa_stories
{
    my ( $db ) = @_;
    
    print STDERR "rematching sopa stories\n";
    
    my $stories = $db->query( 
        "select distinct s.* from stories s, sopa_links sl "  .
        "  where s.stories_id = sl.ref_stories_id and  " . 
        "    sl.ref_stories_id not in ( select stories_id from sopa_stories ) " .
        "  order by s.publish_date" )->hashes;

    print STDERR "found " . @{ $stories } . " stories to rematch\n";
        
    for my $story ( @{ $stories } ) 
    {
        print STDERR ".";
        if ( story_matches_sopa_keywords( $db, $story, 1 ) )
        {
            print STDERR "\n";
            # print STDERR "\nmatch: $story->{ title } [ $story->{ url } ] [ $story->{ stories_id } ]\n";
            add_to_sopa_stories_and_links( $db, $story, 1 );
        }
    }
    print STDERR "\n";
}

# hit every pending sopa link to get polipo to cache it
sub cache_all_link_urls
{
    my ( $db ) = @_;
    
    my $links = $db->query( "select url from sopa_links where ref_stories_id is null order by sopa_links_id" )->hashes;
    
    my $urls = [ map { $_->{ url } } @{ $links } ];
    
    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
}

# test url fetcher
sub test_url_fetch
{
    my ( $db ) = @_;
    
    my $links = $db->query( "select url from sopa_links where ref_stories_id is null order by sopa_links_id limit 100" )->hashes;
    
    my $urls = [ map { $_->{ url } } @{ $links } ];
    
    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
    
    print STDERR @{ $urls } . " urls, " . @{ $responses } . " responses\n";
    
    my $lookup = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        $lookup->{ $original_url } = $response;
    }        
    
    for my $url ( @{ $urls } )
    {
        $url = URI->new( $url )->as_string;
        my $r = $lookup->{ $url };
        
        if ( !$r )
        {
            "not found: $url\n";
        } 
        elsif ( $r->is_success ) {
            print STDERR "success: " . length( $r->decoded_content ) . " for $url\n";
        }
        else {
            print STDERR "error: " . $r->status_line . " for $url\n";
        }
    }

}

# reset the STORY_TAG tag to point to all stories in sopa_stories
sub update_story_tags
{
    my ( $db ) = @_;

    my $all_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, SOPA_ALL_TAG );
    
    $db->query( 
        "delete from stories_tags_map where tags_id = ? and stories_id not in ( select stories_id from sopa_stories )", 
        $all_tag->{ tags_id } );
        
    $db->query( 
        "insert into stories_tags_map ( stories_id, tags_id ) " .
        "  select distinct stories_id, $all_tag->{ tags_id } from sopa_stories " .
        "    where stories_id not in ( select stories_id from stories_tags_map where tags_id = ? )",
        $all_tag->{ tags_id } );

    $db->query( 
        "delete from stories_tags_map using tags t, tag_sets ts " . 
        "  where stories_tags_map.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id and " .
        "    ts.name = ? and stories_tags_map.stories_id not in ( select stories_id from sopa_stories )",
        SOPA_KEYWORD_TAGSET );
    
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

# get sopa stories with a { source_stories } field that is a list
# of links to stories linking to that story
sub get_stories_with_sources
{
    my ( $db ) = @_;
    
    my $links = $db->query( "select * from sopa_links_cross_media" )->hashes;
    my $stories = $db->query( "select s.* from sopa_stories ss, stories s where s.stories_id = ss.stories_id" )->hashes;
    
    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    for my $link ( @{ $links } )
    {        
        my $ref_story = $stories_lookup->{ $link->{ ref_stories_id } };
        push( @{ $ref_story->{ source_stories } }, $stories_lookup->{ $link->{ stories_id } } );
    }
    
    return $stories;
}

# get the minimum publish date of all the source link stories
# for this story
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

# set the date of each story to be the earliest publish date of the 
# stories that link to it
sub fix_publish_dates
{
    my ( $db, $stories ) = @_;
        
    my $dates_changed = 1;
    my $max_iterations = 100;

    for my $story ( @{ $stories } )
    {        
        my $min = get_min_source_publish_date( $story->{ publish_date }, $story );
    
        if ( $min lt $story->{ publish_date } )
        {
            $dates_changed++;
            $db->query( "update stories set publish_date = ? where stories_id = ?", $min, $story->{ stories_id } );
            print STDERR "$story->{ publish_date } -> $min: $story->{ title } [ $story->{ url } ] [ $story->{ stories_id } ]\n";
        }
    }
        
}

# generate a link weight score for each cross media sopa_link
# by adding a point for each incoming link, then adding the some of the 
# link weights of each link source divided by the ( iteration * 10 ) of the recursive 
# weighting (so the first reweighting run will add 1/10 the weight of the sources,
# the second 1/20 of the weight of the sources, and so on)
sub generate_link_weights
{
    my ( $db, $stories ) = @_;        
            
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
            "update sopa_stories set link_weight = ? where stories_id = ?", 
            $story->{ link_weight } || 0, $story->{ stories_id } );
    }
}

sub main
{
    my ( $option ) = @ARGV;
    
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    
    my $db = MediaWords::DB::connect_to_db;
    
    # test_url_fetch( $db );
    # return;
    
    # cache_all_link_urls( $db );
    # return;
    
    # rematch_sopa_stories( $db );    
    # return;
        
    print STDERR "deleting duplicate sopa links ...\n";    
    delete_duplicate_sopa_links( $db );
        
    print STDERR "adding redirect urls to sopa stories ...\n";
    add_redirect_urls_to_sopa_stories( $db );
    
    print STDERR "mining sopa stories ...\n";
    mine_sopa_stories( $db );
    
    print STDERR "running spider ...\n";
    run_spider( $db, NUM_SPIDER_ITERATIONS );
    
    print STDERR "deleting duplicate sopa links ...\n";    
    delete_duplicate_sopa_links( $db );

    print STDERR "updating story_tags ...\n";
    update_story_tags( $db );
    
    print STDERR "generating link weights ...\n";
    my $stories = get_stories_with_sources( $db );        
    generate_link_weights( $db, $stories );

    # print STDERR "fix publish dates ...\n";
    # fix_publish_dates( $db, $stories );
}

main();