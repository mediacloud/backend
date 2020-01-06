use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More tests => 38;

use_ok( 'MediaWords::Feed::Parse' );

use Data::Dumper;
use MediaWords::Test::URLs;

sub _test_feed_contents($)
{
    my $feed_contents = shift;

    my $feed = MediaWords::Feed::Parse::parse_feed( $feed_contents );
    ok( $feed, "Unable to parse feed" );

    is( $feed->title(), 'Test feed' );

    my $items = $feed->items();
    is( scalar( @{ $items } ), 2 );

    my $first_item = $items->[ 0 ];
    is( $first_item->title(),   'First item' );
    is( $first_item->link(),    'http://www.example.com/first_item.html' );
    is( $first_item->publish_date(), '2016-12-14T04:04:01Z' );

    # publish_date_sql() is dependent on machine's timezone (which shouldn't be the case, but it is)
    like( $first_item->publish_date_sql(), qr/2016-12-1\d \d\d:\d\d:\d\d/ );

    is( $first_item->guid(),          'http://www.example.com/first_item.html' );
    is( $first_item->guid_if_valid(), 'http://www.example.com/first_item.html' );
    is( $first_item->description(),   'This is a first item.' );

    my $second_item = $items->[ 1 ];
    is( $second_item->title(),   'ɯǝʇı puoɔǝS' );
    is( $second_item->link(),    'http://www.example.com/second_item.html' );
    is( $second_item->publish_date(), '2016-12-14T04:05:01Z' );

    # publish_date_sql() is dependent on machine's timezone (which shouldn't be the case, but it is)
    like( $second_item->publish_date_sql(), qr/2016-12-1\d \d\d:\d\d:\d\d/ );

    is( $second_item->guid(),                    'http://www.example.com/second_item.html' );
    is( $second_item->guid_if_valid(),           'http://www.example.com/second_item.html' );
    is( $second_item->description(),             'This is a second item.' );
}

sub test_rss_feed()
{
    my $rss_feed = <<XML;
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
    <channel>
        <title>Test feed</title>
        <link>http://www.example.com/</link>
        <description>This is a test feed.</description>
        <lastBuildDate>Wed, 14 Dec 2016 04:00:00 GMT</lastBuildDate>
        <item>
            <title>First item</title>
            <author>foobar\@example.com</author>
            <link>http://www.example.com/first_item.html</link>
            <pubDate>Wed, 14 Dec 2016 04:04:01 GMT</pubDate>
            <guid isPermaLink="true">http://www.example.com/first_item.html</guid>
            <description>This is a first item.</description>
        </item>
        <item>
            <title>ɯǝʇı puoɔǝS</title>  <!-- UTF-8 test -->
            <author>foobar\@example.com</author>
            <link>http://www.example.com/second_item.html</link>
            <pubDate>Wed, 14 Dec 2016 04:05:01 GMT</pubDate>
            <guid isPermaLink="false">http://www.example.com/second_item.html</guid>    <!-- Even though it is a link -->
            <content:encoded><![CDATA[This is a second item.]]></content:encoded>   <!-- Instead of description -->
        </item>
    </channel>
</rss>
XML

    _test_feed_contents( $rss_feed );
}

sub test_atom_feed()
{
    my $atom_feed = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">

    <title>Test feed</title>
    <subtitle>This is a test feed.</subtitle>
    <link href="http://www.example.com/"/>
    <updated>2016-12-14T04:00:00Z</updated>
    <id>http://www.example.com/</id>
    <entry>
        <title>First item</title>
        <link href="http://www.example.com/first_item.html" />
        <id>http://www.example.com/first_item.html</id>
        <author>
            <name>Foo Bar</name>
        </author>
        <updated>2016-12-14T04:04:01Z</updated>
        <summary>This is a first item.</summary>
    </entry>
    <entry>
        <title>ɯǝʇı puoɔǝS</title>  <!-- UTF-8 test -->
        <link href="http://www.example.com/second_item.html" />
        <id>http://www.example.com/second_item.html</id>
        <author>
            <name>Foo Bar</name>
        </author>
        <updated>2016-12-14T04:05:01Z</updated>
        <summary><![CDATA[This is a second item.]]></summary>
    </entry>
</feed>
XML

    _test_feed_contents( $atom_feed );
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_empty_feed();
    test_rss_feed();
    test_atom_feed();
}

main();
