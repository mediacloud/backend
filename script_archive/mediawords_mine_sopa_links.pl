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
use HTML::LinkExtractor;
use URI;

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

# current position of precaching on $_link_downloads_list
my $_link_downloads_pos;

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
    $_link_downloads_pos = 0;
}

# if the url has been precached, return it, otherwise download the current links and the next ten links
sub get_cached_link_download
{
    my ( $url ) = @_;
    
    if ( my $content = $_link_downloads_cache->{ $url } )
    {
        return $content;
    }

    my $links = $_link_downloads_list;
    my $pos = $_link_downloads_pos;
    
    my $urls = [ map { $_->{ redirect_url } || $_->{ url } } { @{ $links } }[ $pos .. $pos+9 ] ];
    
    my $responses = MediaWords::Util::Web::ParallelGet( $urls );
    
    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web::get_original_request( $response )->uri->as_string;
        $_links_downloads_cache->{ $original_url } = $response->decoded_content;
    }
    
    $_link_downloads_pos += 10;
    
    return $_link_downloads_cache->{ $url };
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
    
    my $spidered_sopa_tag = get_spidered_sopa_tag( $db );
    
    my $medium = $db->query( 
        "select m.* from media m, media_tags_map mtm " .
        "  where m.media_id = mtm.media_id and mtm.tags_id = ? and m.url = ? and m.name = ?",
        $spidered_sopa_tag, $medium_url, $medium_name )->hash;
    return $medium if ( $medium );
    
    $medium = {
        name => $medium_name,
        url => $medium_url,
        moderated = 't',
        feeds_added = 't' };
        
    $medium = $db->create( 'media', $medium );
    
    $db->query( 
        "insert into media_tags_map ( media_id, tags_id ) values ( ?, ? )",
        $medium->{ media_id }, $spidered_sopa_tag->{ tags_id } );
        
    return $medium;
}

# get the first feed found for the given medium
sub get_spider_feed
{
    my ( $db, $medium ) = @_;
    
    my $feed = $db->query( "select * from feeds where media_id = ? limit 1", $medium->{ media_id } )->hash;
    return $feed if ( $feed );
    
    $db->query( 
        "insert into feeds ( media_id, url, last_download_time, name ) " . 
        "  values ( ?, ?, now() + interval '10 years', 'Feed' )",
        $medium->{ media_id }, $medium->{ url } );
        
    return $db->query( "select * from feeds where media_id = ? limit 1", $medium->{ media_id } )->hash;
}

# parse the content for tags that might indicate the story's title
sub get_story_title_from_content
{
    # my ( $content ) = @_;
    
    if ( $_[0] =~ m~<meta property=\"og:title\" content=\"([^\"]+)\"~si ) return $1;

    if ( $_[0] =~ m~<meta property=\"og:title\" content=\'([^\']+)\'~si ) return $1;

    if ( $_[0] =~ m~<title>([^<]+)</title>~si ) return $1;
    
    return '(no title)';
}

# guess publish date from the story and content.  failsafe is to use the
# date of the linking story
sub guess_publish_date
{
    my ( $db, $link, $story ) = @_;
#    my ( $db, $link, $story ) = @_;
    my ( $content_ref ) = \$_[3];
    
    if ( $_[3] =~ m~<time \s+datetime=\"([^\"]+)\"\s+pubdate~is ) return $1;
    if ( $_[3] =~ m~<time \s+datetime=\'([^\']+)\'\s+pubdate~is ) return $1;

    if ( $story->{ url } =~ m~(\d\d\d\d/\d\d/\d\d) )
    {
        my $publish_date = $1;
        $publish_date =~ s~/~-~g;
        return $publish_date;
    }
    
    return $db->find_by_id( 'stories', $link->{ stories_id } )->{ publish_date };
}

# add a new story and download corresponding to the given link
sub add_new_story_and_download
{
    my ( $db, $link ) = @_;
    
    my $story_url = $link->{ redirect_url } || $link->{ url };
    
    my $story_content = get_cached_link_download( $story_url );
    
    my $medium = get_spider_medium( $db, $story_url );
    my $feed = get_spider_feed( $db, $medium );
    
    my $title = get_story_title_from_content( $story_content );
    
    my $pubish_date = guess_publish_date( $db, $link, $story, $story_content );
    
    my $story = {
        url          => $story_url,
        guid         => $story_url,
        media_id     => $media_id,
        publish_date => $publish_date,
        collect_date => DateTime->now->datetime,
        title        => $title,
        description  => ''
    };
    
    $story = $db->create( 'stories', $story );
    
    $db->query( 
        "insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )", 
        $feed->{ feeds_id }, $story->{ stories_id } );
    
    my $download = {
        feeds_id      => $feed->{ feeds_id },
        stories_id    => $story->{ stories_id },
        url           => $story->{ url },
        host          => lc( ( URI::Split::uri_split( $story->{ url } ) )[ 1 ] ),
        type          => 'content',
        sequence      => 1,
        state         => 'success',
        priority      => 1,
        download_time => DateTime->now->datetime,
        extracted     => 't' };
    
    $download = $db->create( 'downloads', $download );
    
    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );

    return ( $story, $download );
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

# return true if the story_sentences for the story match any of the sopa patterns
sub story_matches_sopa_keywords
{
    my ( $db, $story ) = @_;
    
    my $keyword_pattern = 
        '[[:<:]]sopa[[:>:]]|stop\s+online\s+privacy\s+act|' .
        '[[:<:]]acta[[:>:]]|anti-counterfeiting\s+trade\s+agreement|' ..
        '[[:<:]]coica[[:>:]]|combating\s+online\s+infringement\s+and\s+counterfeits\s+act|' . 
        '[[:<:]]pipa[[:>:]]|protect\s+ip\s+act';
    
    my $matches_sopa = $db->query( 
        "select 1 from story_sentences ss where ss.stories_id = ? and " . 
        "    lower( ss.sentence ) ~ '$keyword_pattern'", $story->{ stories_id } )->list;
        
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
            $db->query( 
                "update sopa_links set link_spidered = 't', ref_stories_id = ? where sopa_links_id = ?",
                $link->{ ref_stories_id }, $link->{ sopa_links_id } );
        }
    }    
}

# download any unmatched link, add it as a story, extract it, add any links to the sopa links list
sub spider_new_links
{
    my ( $db, $iteration ) = @_;
    
    my $new_links = $db->query( "select * from sopa_links where ref_stories_id is null and link_spidered = 'f'" );
    
    cache_link_downloads( $new_links );
    
    for my $link ( @{ $new_links } ) 
    {
        if ( !$link->{ ref_stories_id } )
        {
            my ( $story, $download ) = add_new_story_and_download( $db, $link );
            
            extract_download( $db, $download );
            
            if ( story_matches_sopa_keywords( $db, $story ) )
            {
                add_to_sopa_stories_and_links( $db, $story, $iteration );                
            }
            
            $db->query( "update sopa_links set link_spidered = 't' where sopa_links_id = ?", $link->{ sopa_links_id } );
            
            update_other_matching_links( $db, $story, $links );
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

sub main
{
    my ( $option ) = @ARGV;
    
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    
    my $db = MediaWords::DB::connect_to_db;
    
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