#!/usr/bin/perl

# import html from http://beta.bloglines.com/topfeeds as media sources / feeds

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use HTTP::Request;
use LWP::UserAgent;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;

use constant COLLECTION_TAG => 'bloglines_top1000_20091012';

# create a media source from a media name and a feed url
sub create_media
{
    my ( $medium_name, $feed_url ) = @_;

    eval {

        my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

        my $ua = LWP::UserAgent->new;

        $ua->timeout( 10 );

        my $response = $ua->request( HTTP::Request->new( GET => $feed_url ) );

        my $feed;
        if ( !$response->is_success )
        {
            print STDERR "Unable to fetch '$feed_url': " . $response->status_line . "\n";
        }
        else
        {
            $feed = Feed::Scrape->parse_feed( $response->decoded_content );
        }

        my $medium_url;
        if ( $feed )
        {
            $medium_url = $feed->link;
        }
        else
        {
            $medium_url = $feed_url;
            print STDERR "Unable to parse feed '$feed_url'\n";
        }

        my $medium = $db->query( "select * from media where name = ? or url = ?", $medium_name, $medium_url )->hash;

        if ( !$medium )
        {
            if ( $feed )
            {
                $medium =
                  $db->create( 'media', { name => $medium_name, url => $medium_url, moderated => 't', feeds_added => 't' } );
                $db->create( 'feeds', { name => $medium_name, url => $feed_url, media_id => $medium->{ media_id } } );
            }
            else
            {
                $medium =
                  $db->create( 'media', { name => $medium_name, url => $medium_url, moderated => 'f', feeds_added => 'f' } );
            }
        }

        my $tag_set = $db->find_or_create( 'tag_sets', { name => 'collection' } );

        my $tag = $db->find_or_create( 'tags', { tag => COLLECTION_TAG, tag_sets_id => $tag_set->{ tag_sets_id } } );

        $db->find_or_create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $tag->{ tags_id } } );

        print STDERR "added $medium_name, $medium_url, $feed_url\n";
    };
    if ( $@ )
    {
        print STDERR "Error adding $medium_name: $feed_url: $@\n";
    }
}

sub main
{
    my $html;
    for my $i ( 1 .. 10 )
    {
        print STDERR "fetching page $i\n";
        my $response =
          LWP::UserAgent->new->request( HTTP::Request->new( GET => "http://beta.bloglines.com/topfeeds?page=$i" ) );

        if ( !$response->is_success )
        {
            my $response =
              LWP::UserAgent->new->request( HTTP::Request->new( GET => "http://beta.bloglines.com/topfeeds?page=$i" ) );
            die( "Unable to download page $i: " . $response->as_string );
        }

        if ( !$response->is_success )
        {
            die( "Unable to download page $i: " . $response->as_string );
        }

        $html .= $response->content;
    }

    my $lines = [ split( "\n", $html ) ];

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        if ( my ( $feed_url ) = ( $lines->[ $i ] =~ m~<a href="([^"]*)" title="Subscribe to Feed">~ ) )
        {
            while ( $lines->[ ++$i ] )
            {
                if ( $lines->[ $i ] =~ m~title="Preview">$~ )
                {
                    my $name = $lines->[ ++$i ];

                    $name = trim( $name );

                    create_media( $name, $feed_url );

                    last;
                }
            }
        }
    }

}

main();

__END__
  <div class="bl_subItem bl_preview">
  <a href="/b/preview?siteid=2655254" title="Preview">Preview</a>
  </div>

  <div class="bl_subItem bl_subscribe">
  <a href="/b/view?mode=addsubs&siteId=2655254" title="Subscribe with Bloglines">
  <img src="/c/images/r26982/favicon.ico">
  </a>
  <a href="http://rss.slashdot.org/slashdot/eqWf" title="Subscribe to Feed">
  <img src="/c/images/r26982/subscribe.png">
  </a>
  </div>
  <div 
class="bl_subItem bl_gain bl_change_unchanged">

  0
  </div>
  <div class="bl_subItem chart" isChart="true" id="chartContainer_1" datapoints="1,1,1,1,1,">
  </div>
  </div>
  <div class="bl_nameRankContainer">
  <div class="bl_nameRank" bl:siteId="2655254"
                      style="background:url(/c/images/r26982/icon_doc.gif) no-repeat;">
  1
  <a href="/b/preview?siteid=2655254" title="Preview">
  Slashdot
  </a>

