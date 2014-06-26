use strict;
use warnings;

# test feed checksumming in FeedHandler

use English '-no_match_vars';

use Test::More tests => 12;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::Crawler::FeedHandler' );
}

sub test_feed_checksums
{
    my ( $db ) = @_;

    my $medium = {
        name        => "test feed checksum $PROCESS_ID",
        url         => "url://test/feed/checksum/$PROCESS_ID",
        moderated   => 't',
        feeds_added => 't'
    };
    $medium = $db->create( 'media', $medium );

    my $feed = {
        name     => "feed",
        url      => $medium->{ url },
        media_id => $medium->{ media_id }
    };
    $feed = $db->create( 'feeds', $feed );

    my $urls_a = [
        "http://www.bzf.ro/rezultate-liga-a-v-a-zona-fagaras-20.html",
        "http://www.mehrnews.com/detail/News/2027821",
        "http://www.chip.de/news/Parallels-Zwei-Android-Systeme-auf-einem-Handy_61383826.html",
        "http://www.inn.co.il/News/Flash.aspx/401095",
        "http://www.moheet.com/2013/04/07/%d9%85%d8%ad%d8%b3%d9%88%d8%a8-" .
          "%d8%a3%d8%ad%d8%af%d8%a7%d8%ab-%d8%a7%d9%84%d9%83%d8%a7%d8%aa%d8%af%d8%b1%d8" .
          ".%a7%d8%a6%d9%8a%d8%a9-%d9%88%d8%a7%d8%ad%d8%af%d8%a9-%d9%85%d9%86-%d9%85%d9%88%d8%b1%d9%88/",
        "http://twitter.com/radiationn/statuses/320948496549154816",
        "http://news.chinatimes.com/realtime/110105/112013040700840.html",
        "http://www.northkoreannews.net/index.php/sid/213669147/scat/08aysdf7tga9s7f7",
        "http://twitter.com/NastyaaPatrick/statuses/320956956149948417",
        "http://life.chinatimes.com/life/11051801/112013040800054.html",
        "http://www.enet.gr/?i=news.el.article&id=355553",
"http://www.ibtimes.co.uk/articles/454410/20130407/portugal-government-sticks-to-bailout-goals-despite-court-ruling.htm",
        "http://www.egynews.net:80/wps/portal/news?params=223267",
"http://www.merkur-online.de:80/sport/fussball/hannover-trostlose-nullnummer-gegen-stuttgart-zr-2838522.html?cmp=defrss",
        "http://www.farsnews.com/newstext.php?nn=13920118001322"
    ];

    my $urls_b = [
        "http://www.guardian.co.uk/football/blog/2013/apr/07/sunderland-chelsea-tactics-match",
        "http://www.nicematin.com/monde/egypte-un-mort-dans-des-violences-apres-les-funerailles-de-coptes-tues.1206791.html",
"http://www.mercurynews.com/breaking-news/ci_22965002/immigration-talks-between-california-farm-groups-hit-impasse?source=rss_emailed",
        "http://www.belfasttelegraph.co.uk/sport/racing/cut-too-sharp-for-gladness-rivals-29179755.html",
        "http://www.vz.ru/news/2013/4/7/627732.html",
        "http://www.thehindu.com/sport/ipl2013/fleming-unhappy-with-csk-batsmen/article4591746.ece",
"http://www.dallasnews.com/entertainment/music/headlines/20130407-academy-of-country-music-awards-7-p.m.-burleson-s-kelly-clarkson-set-to-perform.ece",
        "http://feedproxy.google.com/~r/OTB/~3/TNKm_R0dEKo/",
"http://rss.feedsportal.com/c/266/f/3492/s/2a6f8876/l/0L0Sindependent0O0Cnews0Cworld0Cmiddle0Eeast0Cisraels0Enew0Estrategic0Eaffairs0Eminister0Ewest0Emust0Ethreaten0Eiran0Eover0Enuclear0Eplans0E85635150Bhtml/story01.htm",
        "http://news.chinatimes.com/focus/11050105/112013040800090.html",
        "http://blogi.newsweek.pl/Tekst/naluzie/669783,marzenie-przyziemne.html#comment-168169",
        "http://jamaica-gleaner.com/gleaner/20130407/ent/ent6.html",
        "http://www.wboc.com/story/21901967/timeline-of-the-whereabouts-of-suspected-strangler",
        "http://www.cadenaser.com/internacional/articulo/feminismo-islamico-femen/csrcsrpor/20130407csrcsrint_6/Tes",
        "http://thehimalayantimes.com/rssReference.php?id=MzcyMDQw",
"http://au.ibtimes.com/articles/454410/20130408/portugal-government-sticks-to-bailout-goals-despite-court-ruling.htm",
        "http://www.ziar.com/articol-din-ziar?id_syndic_article=5566035",
        "http://www.bellinghamherald.com/2013/04/07/2955579/hardwood-to-trading-floor-stocks.html#storylink=rss",
    ];

    my $stories_a = [ map { { url => $_ } } @{ $urls_a } ];
    my $stories_b = [ map { { url => $_ } } @{ $urls_b } ];

    # first check should fail since feed checksum should be empty
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_a ),
        0, "empty checksum" );

    # next check with same stories should be a match
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_a ),
        1, "match 1" );

    # and another match
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_a ),
        1, "match 2" );

    # and now try with different set of stories
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_b ),
        0, "fail 1" );

    # and now with the same b stories
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_b ),
        1, "match 3" );

    # and now add one story
    push( @{ $stories_b }, { url => 'http://foo.bar.com' } );
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_b ),
        0, "fail 2" );
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_b ),
        1, "match 4" );

    # and now with no stories
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, [] ), 0, "fail 3" );

    # and now with b again
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_a ),
        0, "fail 4" );
    is( MediaWords::Crawler::FeedHandler::stories_checksum_matches_feed( $db, $feed->{ feeds_id }, $stories_a ),
        1, "match 5" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    $db->begin;

    eval { test_feed_checksums( $db ); };

    die( $@ ) if ( $@ );

    $db->rollback;

}

main();
