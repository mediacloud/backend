use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More tests => 2 + 1;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../../lib";
}

use_ok( 'MediaWords::Feed::Parse' );

use Data::Dumper;

sub main()
{
    my $feed_text = <<XML;
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet href="/css/rss20.xsl" type="text/xsl"?>
<rss version="2.0">
    <channel>
        <title>foo</title>
        <link>http://example.com</link>
        <description/>
        <language>en</language>
        <item xmlns:atom="http://www.w3.org/2005/Atom">
            <title><![CDATA[]]></title>
            <link/>
            <guid isPermaLink="false"/>
            <pubDate>Mon, 11 Apr 2011 13:13:48 EST</pubDate>
        </item>
    </channel>
</rss>
XML

    my $feed = MediaWords::Feed::Parse::parse_feed( $feed_text );

    die "Unable to parse feed " unless $feed;

    my $items = [ $feed->get_item ];

    my $num_new_stories = 0;

    for my $item ( @{ $items } )
    {
        my $url  = $item->link() || $item->guid();
        my $guid = $item->guid() || $item->link();

        ok( ( !$guid ) || !ref( $guid ), "GUID is nonscalar: " . Dumper( $item ) );

        next unless $url || $guid;
    }
}

main();
