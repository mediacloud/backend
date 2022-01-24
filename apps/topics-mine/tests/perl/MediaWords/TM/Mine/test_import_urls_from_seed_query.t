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

sub test_import_urls_from_seed_queries($)
{
    my ( $db ) = @_;

    my $label = "test_import";

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    $topic->{ start_date } = '2019-01-01';
    $topic->{ end_date }   = '2019-02-01';
    $topic->{ platform }   = 'generic_post';
    $topic->{ mode }       = 'web';
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
CSV

    my $posts_2_csv = <<CSV;
post_id,content,publish_date,url,author,channel
2,foo http://bar.com,2019-01-02,http://mock.post/2,author 2,channel 2
CSV

    my $topic_seed_query_data = {
        topics_id => $topic->{ topics_id },
        source => 'csv',
        platform => 'generic_post',
        query => $posts_csv
    };
    my $topic_seed_query = $db->create( 'topic_seed_queries', $topic_seed_query_data );

    $topic_seed_query_data->{ query } = $posts_2_csv;
    my $topic_seed_query_2 = $db->create( 'topic_seed_queries', $topic_seed_query_data );

    MediaWords::TM::Mine::import_urls_from_seed_queries( $db, $topic );

    my $topic_posts = $db->query( <<SQL,
        SELECT * 
        FROM topic_posts
            INNER JOIN topic_post_days ON
                topic_posts.topics_id = topic_post_days.topics_id AND
                topic_posts.topic_post_days_id = topic_post_days.topic_post_days_id
            INNER JOIN topic_seed_queries ON
                topic_post_days.topics_id = topic_seed_queries.topics_id AND
                topic_post_days.topic_seed_queries_id = topic_seed_queries.topic_seed_queries_id
        WHERE topic_posts.topics_id = ?
SQL
        $topic->{ topics_id }
    )->hashes();

    is ( scalar( @{ $topic_posts } ), 2, "number of topic posts" );

    my $tsus = $db->query( "SELECT * FROM topic_seed_urls WHERE topics_id = ?", $topic->{ topics_id } )->hashes();

    is( scalar( @{ $tsus } ), 2, "number of seed urls" );

}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_import_urls_from_seed_queries( $db );

    done_testing();
}

main();
