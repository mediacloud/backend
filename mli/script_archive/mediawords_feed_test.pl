#!/usr/bin/perl

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Parse;
use HTTP::Request;
use LWP::UserAgent;
use Text::CSV_XS;
use Text::Trim;

use Test::More;
use Test::Differences;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;
use Perl6::Say;
use Data::Dumper;
use XML::RAI;
use Data::Feed;
use HTML::StripPP;

sub _feed_item_age
{
    my ( $item ) = @_;

    return ( time - Date::Parse::str2time( $item->pubDate ) );
}

sub use_xml_rai
{

    my ( $content ) = @_;

    my $rai = XML::RAI->parse_string( $content );

    my $item = $rai->items->[ 0 ];

    say 'Title: ' . $item->title;

    #say 'Content: ' . $item->content;
    exit;
}

sub use_data_feed
{

    my ( $content ) = @_;

    my $rai = Data::Feed->parse( \$content );

    my $item = [ $rai->entries ]->[ 0 ];

    say 'Title: ' . $item->title;

    #say 'Description: ' . $item->description;
    say 'Content: ' . $item->content->body;

    say;
    say;

    # exit;
}

sub _is_recently_updated
{
    my ( $medium_url, $feed_url ) = @_;

    my $medium;

    my $response = LWP::UserAgent->new->request( HTTP::Request->new( GET => $feed_url ) );

    if ( !$response->is_success )
    {
        print STDERR "Unable to fetch '$feed_url' ($medium_url): " . $response->status_line . "\n";
        return;
    }

    if ( !$response->decoded_content )
    {

        #say STDERR "No content in feed";
        return;
    }

    #use_data_feed($response->decoded_content );

    my $content = $response->decoded_content;

    my $feed = Feed::Scrape->parse_feed( $content );

    #say Dumper($feed);

    #exit;

    my $rai  = Data::Feed->parse( \$content );
    my $item = [ $rai->entries ]->[ 0 ];

    is( 0, 1, 'should fail' );

    is( scalar( $rai->entries ), scalar( $feed->get_item ), 'item count comparison' );

    my $item_counts = scalar( $feed->get_item );

    for ( my $i = 0 ; $i < $item_counts ; $i++ )
    {
        my $xml_feedpp_item = $feed->get_item( $i );
        my $data_feed_item  = [ $rai->entries ]->[ $i ];

        my $title       = $data_feed_item->title;
        my $description = $data_feed_item->content->body;

        utf8::encode( $title );
        utf8::encode( $description );
        is( $xml_feedpp_item->title, $title, 'title' );

        unified_diff;
        eq_or_diff(
            HTML::StripPP::strip( $xml_feedpp_item->description ),
            HTML::StripPP::strip( $description ),
            'description/content'
        );

        #say "Data::Feed:\n$description";
        #say "Xml_feedPP\n" . $xml_feedpp_item->description;
        exit;
    }

    exit;

    my $medium_name;
    if ( $feed )
    {
        $medium_name = $feed->title;
    }
    else
    {
        print STDERR "Unable to parse feed '$feed_url' ($medium_url)\n";
        $medium_name = $medium_url;
        return;
    }

    my $last_post_date = 0;

    my $days = 60;

    my $age_in_seconds = $days * 60 * 60 * 24;

    $DB::single = 1;
    my $recent_item = $feed->get_item( 0 );

    say "Item:";

    say Dumper( $recent_item );

    say "Title: " . $recent_item->title;

    say 'keys:' . ( join ',', keys %{ $recent_item } );
    $DB::single = 1;

    my $content = $recent_item->get( 'content:encoded' );

    say "Content: " . $content;

    my $description = $recent_item->description;

    say '------------------------';
    say 'Description: ' . $description;

}

sub main
{
    my ( $url ) = @ARGV;

    if ( _is_recently_updated( $url, $url ) )
    {
        print STDERR "Recent blog $url\n";
    }
    else
    {
        print STDERR "OLD blog $url\n";
    }
}

main();

__END__
