#!/usr/bin/perl

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

use constant NUM_SPIDER_ITERATIONS => 10;

# these media sources use urls of referred stories for their
# rss item urls, making them confuse the link matching
use constant IGNORE_MEDIA_REFS => ( 6880, 5839 );

# cache of media by media id
my $_media_cache = {};
    
# cache of stories by url or redirect url
my $_story_lookup;

# list of downloads to precache downloads for
my $_link_downloads_list;

# precached link downloads
my $_link_downloads_cache;

# cache for spidered:sopa tag
my $_spidered_sopa_tag;

# query the stories and sopa_stories tables for list of sopa relevant stories
sub get_sopa_stories
{
    my ( $db ) = @_;
    
    my $stories = $db->query( 
        "select distinct s.*, ss.link_mined, ss.redirect_url " .
        "  from stories s, sopa_stories ss where s.stories_id = ss.stories_id order by s.publish_date" )->hashes;
        
    if ( !( grep { $_->{ redirect_url } } @{ $stories } ) )
    {
        add_redirect_links( $stories );
        for my $story ( grep { $_->{ redirect_url } } @{ $stories } )
        {
            $db->query( "update sopa_stories set redirect_url = ? where stories_id = ?", $story->{ redirect_url }, $story->{ stories_id } ); 
        }
    }
    
    return $stories;
}

# fetch each link and add a { redirect_url } field if the 
# { url } field redirects to another url
sub add_redirect_links
{
    my ( $links ) = @_;
    
    my $urls = [ map { $_->{ url } } @{ $links } ];
    
    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
    
    my $link_lookup = {};
    map { $link_lookup->{ $_->{ url } } = $_ } @{ $links };
    
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $final_url = $response->request->uri->as_string;
        if ( $original_url ne $final_url )
        {
            $link_lookup->{ $original_url }->{ redirect_url } = $final_url;
        }
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
    
    for my $more_link ( @{ $more_links } )
    {
        if ( !grep { sanitize_url( $more_link->{ url } ) eq sanitize_url( $_->{ url } ) } @{ $links } )
        {
            push( @{ $links }, $more_link );
        }
    }

    add_redirect_links( $links ) if ( @{ $links } );
    
    return $links;
}

# do some simple sanitization to try to make links match
sub sanitize_url
{
    my ( $url ) = @_;
    
    $url = lc( $url );
    
    $url =~ s/www.//g;
    
    $url =~ s/\#.*//;
    
    return $url;
}

# get a lookup table for stories by urls or redirect urls. cache after the first call.
sub get_story_lookup
{
    my ( $stories ) = @_;
    
    return $_story_lookup if ( $_story_lookup );
    
    for my $story ( @{ $stories } )
    {   
        next if ( grep { $story->{ media_id } == $_ } IGNORE_MEDIA_REFS );
        
        $_story_lookup->{ sanitize_url( $story->{ url } ) } = $story->{ stories_id };
        if ( $story->{ redirect_url } )
        {
            $_story_lookup->{ sanitize_url( $story->{ redirect_url } ) } = $story->{ stories_id };
        }
    }

    return $_story_lookup;
}

# for each link, find any stories from the given stories with the same url (slightly sanitized).
# for each link with a matching story add a 'ref_stories_id' field with the matching stories_id.
sub add_matching_stories_to_links
{
    my ( $links, $stories ) = @_;
    
    my $story_lookup = get_story_lookup( $stories );
    
    for my $link ( @{ $links } )
    {
        my $stories_id = $story_lookup->{ sanitize_url( $link->{ url } ) } || $story_lookup->{ sanitize_url( $link->{ redirect_url } ) };
        if ( $stories_id && ( $stories_id != $link->{ stories_id } ) ) 
        {
            $link->{ ref_stories_id } = $stories_id;
        }
    }
}

# for each story, return a list of the links found in either the extracted html or the story description
sub generate_sopa_links
{
    my ( $db, $stories ) = @_;
    
    for my $story ( grep { !$_->{ link_mined } } @{ $stories } )
    {
        my $links = get_links_from_story( $db, $story );
        add_matching_stories_to_links( $links, $stories );
        
        print Dumper( $links );
        
        for my $link ( @{ $links } )
        {
            $link->{ stories_id } = $story->{ stories_id };
            $db->create( "sopa_links", $link );
        }
        
        $db->query( "update sopa_stories set link_mined = true where stories_id = ?", $story->{ stories_id } );
    }
}

# using the existing entries in sopa_links, fix the the ref_stories_id fields
sub fix_ref_stories_ids
{
    my ( $db, $stories ) = @_;
    
    my $links = $db->query( "select * from sopa_links" )->hashes;

    add_matching_stories_to_links( $links, $stories );
    
    for my $link ( @{ $links } )
    {
        if ( $link->{ ref_stories_id } )
        {
            print STDERR "match: $link->{ url }\n";
            $db->query( 
                "update sopa_links set ref_stories_id = ? where sopa_links_id = ?",
                $link->{ ref_stories_id }, $link->{ sopa_links_id } );
        }
    }
}

# cache link downloads 10 at a time so that we can do them in parallel.
# this doesn't actually do any caching -- it just sets the list of
# links so that they can be done 10 at a time by get_cached_link_download.
sub cache_link_downloads 
{
    my ( $links ) = @_;
    
    $_link_downloads_list = $links;
}

# if the url has been precached, return it, otherwise download the current links and the next ten links
sub get_cached_link_download
{
    my ( $url, $link_num ) = @_;
    
    $url = URI->new( $url )->as_string;
    
    if ( my $content = $_link_downloads_cache->{ $url } )
    {
        return $content;
    }

    my $links = $_link_downloads_list;
    my $urls = []; 
    for ( my $i = 0; $urls->[ $link_num + $i ] && $i < 10; $i++ )
    {
        my $link = $links->[ $i ];
        push( @{ $urls }, URI->new( $link->{ redirect_url } || $link->{ url } )->as_string );
    }
    
    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
    
    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        if ( $response->is_success )
        {
            print STDERR "original_url: $original_url " . length( $response->decoded_content ) . "\n";
            $_link_downloads_cache->{ $original_url } = $response->decoded_content;
        }
        else {
            my $msg = "error retrieving content for $original_url: " . $response->status_line;
            warn( $msg );
            $_link_downloads_cache->{ $original_url } = $msg;
        }   
    }
            
    warn( "Unable to find cached download for '$url'" ) if ( !defined( $_link_downloads_cache->{ $url } ) );
     
    return $_link_downloads_cache->{ $url } || '';
}

# lookup or create the spidered:sopa tag
sub get_spidered_sopa_tag
{
    my ( $db ) = @_;
    
    return $_spidered_sopa_tag if ( $_spidered_sopa_tag );
    
    $_spidered_sopa_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'spidered:sopa' );
    
    return $_spidered_sopa_tag;
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
    
    $medium_name =~ s/^www.//;
    
    my $medium = $db->query( "select m.* from media m where m.url = ? or m.name = ?", $medium_url, $medium_name )->hash;
    return $medium if ( $medium );
    
    $medium = {
        name => $medium_name,
        url => $medium_url,
        moderated => 't',
        feeds_added => 't' };
        
    $medium = $db->create( 'media', $medium );
    
    print STDERR "add medium: " . Dumper( $medium ) . "\n";
    
    my $spidered_sopa_tag = get_spidered_sopa_tag( $db );
    
    $db->create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $spidered_sopa_tag->{ tags_id } } );
        
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
    
    eval {
        MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "sopa" );
    };
    warn "extract error processing download $download->{ downloads_id }" if ( $@ );
}

# add a new story and download corresponding to the given link
sub add_new_story
{
    my ( $db, $link, $link_num ) = @_;
    
    my $story_url = $link->{ redirect_url } || $link->{ url };
    if ( length( $story_url ) > 1024 )
    {
        $story_url = substr( $story_url, 0, 1024 );
    }
    
    my $story_content = get_cached_link_download( $story_url, $link_num );
    
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

    
    print STDERR "add story: " . Dumper( $story ) . "\n";
    
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
    my ( $db, $story ) = @_;
    
    my $keyword_pattern = 
        '[[:<:]]sopa[[:>:]]|stop[[:space:]]+online[[:space:]]+privacy[[:space:]]+act|' .
        '[[:<:]]acta[[:>:]]|anti-counterfeiting[[:space:]]+trade[[:space:]]+agreement|' .
        '[[:<:]]coica[[:>:]]|combating[[:space:]]+online[[:space:]]+infringement[[:space:]]+and[[:space:]]+counterfeits[[:space:]]+act|' . 
        '[[:<:]]pipa[[:>:]]|protect[[:space:]]+ip[[:space:]]+act';
    
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
        "insert into sopa_stories ( stories_id, iteration ) " .
        "  values ( ?, ? )", $story->{ stories_id }, $iteration );
        
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
    
    return $db->query( 
        "select * from stories s where s.url in ( ? , ? ) or s.guid in ( ?, ? )",
        $link->{ url }, $link->{ redirect_url }, $link->{ url }, $link->{ redirect_url } )->hash;
}

# return true if the story is already in sopa_stories
sub story_is_new
{
    my ( $db, $story ) = @_;
    
    my $is_new = $db->query( "select 1 from sopa_stories where stories_id = ?", $story->{ stories_id } )->list;
    
    print STDERR "EXISTING SOPA STORY\n" if ( !$is_new );
    
    return $is_new;
}

# download any unmatched link, add it as a story, extract it, add any links to the sopa links list
sub spider_new_links
{
    my ( $db, $iteration ) = @_;
    
    my $new_links = $db->query( 
        "select distinct ss.iteration, sl.* from sopa_links sl, sopa_stories ss " . 
        "  where sl.ref_stories_id is null and sl.stories_id = ss.stories_id and ss.iteration < ?", 
        $iteration )->hashes;
    
    cache_link_downloads( $new_links );
    
    for ( my $i = 0; $i < @{ $new_links }; $i++ )
    {
        my $link = $new_links->[ $i ];

        if ( !$link->{ ref_stories_id } )
        {
            print STDERR "spidering $link->{ url } ...\n";
            my $story = get_matching_story_from_db( $db, $link ) || add_new_story( $db, $link, $i );
            
            if ( !story_is_sopa_story( $db, $sopa ) && story_matches_sopa_keywords( $db, $story ) )
            {
                print STDERR "SOPA MATCH: $link->{ url }\n";
                add_to_sopa_stories_and_links( $db, $story, $link->{ iteration } + 1 );                
            }
            
            $db->query( "update sopa_links set ref_stories_id = ? where sopa_links_id = ?", $story->{ stories_id }, $link->{ sopa_links_id } ); 
        }
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
        "select count(*), stories_id, ref_stories_id from sopa_links "  .
        "  group by stories_id, ref_stories_id having count(*) > 1" )->hashes;
    
    for my $duplicate_link ( @{ $duplicate_links } ) 
    {
        my $ids = [ $db->query( 
            "select sopa_links_id from sopa_links where stories_id = ? and ref_stories_id = ?", 
            $duplicate_link->{ stories_id }, $duplicate_links->{ ref_stories_id } )->flat ];
            
        shift( @{ $ids } );
        map { $db->query( "delete from sopa_links where sopa_links_id = ?", $_ ) } @{ $ids };
    }
}

sub main
{
    my ( $option ) = @ARGV;
    
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    
    my $db = MediaWords::DB::connect_to_db;
    
    delete_duplicate_sopa_stories( $db );
    
    
    # if ( $option eq '-r' )
    # {
    #     $db->query( "truncate table sopa_links" );
    #     $db->query( "update sopa_stories set link_mined = 'f', redirect_url = null" );
    # }
    
    my $stories = get_sopa_stories( $db );
                
    print STDERR "stories: " . Dumper( map { "$_->{ title } / $_->{ url } / $_->{ redirect_url }" } @{ $stories } );
    
    #fix_ref_stories_ids( $db, $stories );
    
    generate_sopa_links( $db, $stories );
    
    run_spider( $db, NUM_SPIDER_ITERATIONS );
}

main();