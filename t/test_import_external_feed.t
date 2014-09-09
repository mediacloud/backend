#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::Crawler::FeedHandler::import_external_feed

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use Test::More tests => 7;
use Test::Deep;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::Test::DB' );
    use_ok( 'MediaWords::Crawler::FeedHandler' );
}

sub test_import
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $test_feed = <<END;
<rss version="2.0">
<channel>
<title>Test Feed</title>
<item>
<title>import 1 title</title>
<description>import 1 description</description>
<link>http://import.test/import/1</link>
<pubDate>Tue, 19 Oct 2004 11:09:11 -0400</pubDate>
</item>
<item>
<title>import 2 title</title>
<description>import 2 description</description>
<link>http://import.test/import/2</link>
<pubDate>Tue, 19 Oct 2004 11:09:11 -0400</pubDate>
</item>
</channel>
END

    my $import_medium = $media->{ A };

    MediaWords::Crawler::FeedHandler::import_external_feed( $db, $import_medium->{ media_id }, $test_feed );

    my $story_import_1 =
      $db->query( "select * from stories where title = 'import 1 title' and media_id = ?", $import_medium->{ media_id } )
      ->hash;
    my $download_import_1 = $db->query( "select * from downloads where url = 'http://import.test/import/1'" )->hash;
    my $story_import_2 =
      $db->query( "select * from stories where title = 'import 2 title' and media_id = ?", $import_medium->{ media_id } )
      ->hash;
    my $download_import_2 = $db->query( "select * from downloads where url = 'http://import.test/import/2'" )->hash;

    ok( $story_import_1,    "story import 1 found" );
    ok( $download_import_1, "download import 1 found" );
    ok( $story_import_2,    "story import 2 found" );
    ok( $download_import_2, "download import 2 found" );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            test_import( $db );
        }
    );
}

main();
