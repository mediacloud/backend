#!/usr/bin/perl

# takes a feed url as an argument and prints information about it

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

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;

use Data::Dumper;
use XML::RAI;
use XML::LibXML;
use Data::Feed;
use Feed::Scrape::MediaWords;
use XML::LibXML;
use List::MoreUtils qw(any all none notall true false firstidx first_index
  lastidx last_index insert_after insert_after_string
  apply after after_incl before before_incl indexes
  firstval first_value lastval last_value each_array
  each_arrayref pairwise natatime mesh zip uniq minmax);

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

my $glob = 0;

sub fix_atom_content_element_encoding
{
    my $xml_string = shift @_;

    my $parser      = XML::LibXML->new;
    my $doc         = $parser->parse_string( $xml_string );
    my $doc_element = $doc->documentElement() || die;

    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'x', 'http://www.w3.org/2005/Atom' );
    my @content_nodes = $xpc->findnodes( '//x:entry/x:content', $doc_element )->get_nodelist;

    #either the feed is RSS or there is no content
    return $xml_string if scalar( @content_nodes ) == 0;

    my $fixed_content_element = 0;

    foreach my $content_node ( @content_nodes )
    {
        next if ( !$content_node->hasChildNodes() );

        my $child_nodes = $content_node->childNodes();

        my $child_node_count = $child_nodes->size;

        if ( $child_node_count == 1 )
        {
            my $first_child = $content_node->firstChild();
            next if ( $first_child->nodeType == XML_CDATA_SECTION_NODE );
        }

        my @content_node_child_list = $child_nodes->get_nodelist();

        # allow white space before CDATA_SECTION
        if ( any { $_->nodeType == XML_CDATA_SECTION_NODE } @content_node_child_list )
        {
            my @non_cdata_children = grep { $_->nodeType != XML_CDATA_SECTION_NODE } @content_node_child_list;

            if ( all { $_->nodeType == XML_TEXT_NODE } @non_cdata_children )
            {
                if ( all { $_->data =~ /\s+/ } @non_cdata_children )
                {
                    say STDERR "Skipping CDATA and white space only description ";

                    #exit;
                    next;
                }
            }
        }

        $fixed_content_element = 1;

        say STDERR "fixing content_node: " . $content_node->toString;

        say Dumper ( [ $child_nodes->get_nodelist() ] );

        say Dumper ( [ map { $_->toString } $child_nodes->get_nodelist() ] );

        my $child_nodes_string = join '', ( map { $_->toString() } ( $child_nodes->get_nodelist() ) );

        $content_node->removeChildNodes();

        my $cdata_node = XML::LibXML::CDATASection->new( $child_nodes_string );
        $content_node->appendChild( $cdata_node );
        say STDERR "fixed content_node: " . $content_node->toString;

        say "Exiting";
        exit;
    }

    #just return the original string if we didn't need to find anything...
    return $xml_string if !$fixed_content_element;

    my $ret = $doc->toString;

    #say "Returning :'$ret'";

    #exit;
    return $ret;
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

    #exit;

    my $content_string = $response->decoded_content;

    my $content_string_new = fix_atom_content_element_encoding( $content_string );

    if ( $content_string_new eq $content_string )
    {
        say "Feed unchanged";
        exit;
    }
    say STDERR "single encoded string:\n$content_string";

    say;
    say;
    say;
    say;
    say "--------------------------------------------";
    say "--------------------------------------------";
    say "--------------------------------------------";
    say;
    say;
    say;
    say;

    my $content_string_double = fix_atom_content_element_encoding( $content_string );

    die unless $content_string_double == $content_string;

    #say STDERR "double encoded string:\n$content_string";

    #$exit;

    my $feed = Feed::Scrape::MediaWords->parse_feed( $response->decoded_content );

    #say Dumper($feed);

    #exit;

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

    if ( ref $description )
    {
        die;

        # say Dumper( $description );
        # use XML::TreePP;

        # my $tpp = XML::TreePP->new();

        # my $source = $tpp->write( $description );

        # say "Unparsed source:";
        # say $source;

    }
}

sub main
{
    my ( $url ) = @ARGV;

    _is_recently_updated( $url, $url );
}

main();

__END__
