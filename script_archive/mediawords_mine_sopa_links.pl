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
use HTML::LinkExtractor;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::Web;

my $_media_cache = {};

# query the stories and sopa_stories tables for list of sopa relevant stories
sub get_sopa_stories
{
    my ( $db ) = @_;
    
    my $stories = $db->query( 
        "select distinct s.* from stories s, sopa_stories ss where s.stories_id = ss.stories_id order by s.publish_date" )->hashes;
        
    add_redirect_links( $stories );
    
    return $stories;
}

# fetch each link and add a { redirect_url } field if the 
# url was redirected to another url
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
    
    print STDERR Dumper( $links );
    
    return $links;
}

# for each story, return a list of the links found in either the extracted html or the story description
sub get_links_from_stories
{
    my ( $db, $stories ) = @_;
    
    return [ map { @{ get_links_from_story( $db, $_ ) } } @{ $stories } ];
}

# do some simple sanitization to try to make links match
sub sanitize_url
{
    my ( $url ) = @_;
    
    $url = lc( $url );
    
    $url =~ s/www.//g;
    
    return $url;
}

# for each link, find any stories from the given stories with the same url (slightly sanitized).
# for each link with a matching story add a 'ref_stories_id' field with the matching stories_id.
sub add_matching_stories_to_links
{
    my ( $links, $stories ) = @_;
    
    my $story_lookup = {};
    
    for my $story ( @{ $stories } )
    {   
        $story_lookup->{ sanitize_url( $story->{ url } ) } = $story->{ stories_id };
        if ( $story->{ redirect_url } )
        {
            $story_lookup->{ sanitize_url( $story->{ redirect_url } ) } = $story->{ stories_id };
        }
    }
    
    for my $link ( @{ $links } )
    {
        my $stories_id = $story_lookup->{ sanitize_url( $link->{ url } ) };
        if ( $stories_id )
        {
            $link->{ ref_stories_id } = $stories_id;
        }
        elsif ( $stories_id = $story_lookup->{ sanitize_url( $link->{ redirect_url } ) } ) {
            $link->{ ref_stories_id } = $stories_id;
        }
    }
}

sub write_links_to_db 
{
    my ( $db, $links ) = @_;
        
    map { $db->create( 'sopa_links', $_ ) } @{ $links };
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    
    my $db = MediaWords::DB::connect_to_db;
    
    my $stories = get_sopa_stories( $db );
    
    print STDERR "stories: " . Dumper( map { $_->{ title } } @{ $stories } );
    
    my $links = get_links_from_stories( $db, $stories );
    
    print STDERR "all links: " . Dumper( $links );
    
    add_matching_stories_to_links( $links, $stories );
    
    print STDERR "matched links: " . Dumper( grep { $_->{ ref_stories_id } } @{ $links } );
    
    write_links_to_db( $db, $links );
}

main();