use strict;
use warnings;

use Test::Deep;
use Test::More; 

use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Test::DB::Create;
use MediaWords::TM::Mine;

use FindBin;
use lib $FindBin::Bin;

sub test_import_urls_from_seed_query($)
{
    my ( $db ) = @_;

    my $label = "test_import";

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    $topic->{ start_date } = '2019-01-01';
    $topic->{ end_date }   = '2019-02-01';
    $topic->{ platform }   = 'generic_post';
    $topic->{ mode }       = 'url_sharing';
    $topic->{ pattern }    = 'foo';

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, $topic );

        # posts.append({
        #     'post_id': post_id,
        #     'content': "sample post for id id %s" % test_url,
        #     'publish_date': publish_date,
        #     'url': test_url,
        #     'author': 'user-%s' % user_id,
        #     'channel': 'channel-%s' % user_id,
        # })
    my $posts_csv = <<CSV;
post_id,content,publish_date,url,author,channel
1,foo http://foo.com,2019-01-02,http://mock.post/1,author 1,channel 1
2,foo http://bar.com,2019-01-02,http://mock.post/2,author 2,channel 2
CSV

    my $topic_seed_query_data = {
        topics_id => $topic->{ topics_id },
        source => 'csv',
        platform => 'generic_post',
        query => $posts_csv
    };
    my $topic_seed_query = $db->create( 'topic_seed_queries', $topic_seed_query_data );

    my $topic_seed_query_2 = $db->create( 'topic_seed_queries', $topic_seed_query_data );

    eval { MediaWords::TM::Mine::import_urls_from_seed_query( $db, $topic ) };
    my $error = $@;
    ok( $error, "error on more than one seed query" );
    ok( $error =~ /only one topic seed query/, "correct error on more than one seed query" );

    $db->delete_by_id( 'topic_seed_queries', $topic_seed_query_2->{ topic_seed_queries_id } );

    MediaWords::TM::Mine::import_urls_from_seed_query( $db, $topic );

    my $topic_posts = $db->query( <<SQL, $topic->{ topics_id } )->hashes();
select * from topic_posts tp join topic_post_days tpd using ( topic_post_days_id ) where topics_id = ?
SQL

    is ( scalar( @{ $topic_posts } ), 2, "number of topic posts" );

    my $tsus = $db->query( "select * from topic_seed_urls where topics_id = ?", $topic->{ topics_id } )->hashes();

    is( scalar( @{ $tsus } ), 2, "number of seed urls" );

}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_import_urls_from_seed_query( $db );

    done_testing();
}

main();
