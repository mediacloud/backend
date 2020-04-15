import mediawords.db
from mediawords.db.handler import DatabaseHandler
from  mediawords.test.db.create import *
from topics_mine.fetch_topic_posts import (
        _get_query_sample_ratio, _reduce_posts_to_query_sample, _reduce_db_posts_to_query_sample)

import topics_mine.fetch_topic_posts

def test_reduce_posts_to_query_sample():
    db = mediawords.db.connect_to_db()

    topic = create_test_topic(db, 'foo')
    create_test_topic_stories(db, topic, 10, 10)

    num_posts_per_day = 10
    create_test_topic_posts(db=db, topic=topic, num_posts_per_day=num_posts_per_day)

    tsq = db.query("select * from topic_seed_queries limit 1").hash()

    got_sample_ratio = _get_query_sample_ratio(db, tsq['topic_seed_queries_id'])

    assert got_sample_ratio == 1

    half_num_posts = int(num_posts_per_day / 2)

    db.query(
        """
        update topic_post_days set num_posts_stored = %(a)s
            where topic_post_days_id in ( select topic_post_days_id from topic_post_days limit 1 )
        """,
        {'a': half_num_posts})

    assert _get_query_sample_ratio(db, tsq['topic_seed_queries_id']) == float(half_num_posts)/num_posts_per_day

    posts = list(range(num_posts_per_day))

    tpd = db.query("select * from topic_post_days limit 1").hash()

    got_posts = _reduce_posts_to_query_sample(db, tpd, posts)

    assert len(got_posts) == half_num_posts

    db.query("update topic_post_days set num_posts_stored = %(a)s", {'a': num_posts_per_day})

    all_num_topic_posts = db.query("select count(*) from topic_posts").flat()[0]

    _reduce_db_posts_to_query_sample(db=db, topic_seed_query=tsq, max_posts_per_day=half_num_posts)

    reduced_num_topic_posts = db.query("select count(*) from topic_posts").flat()[0]

    assert all_num_topic_posts == reduced_num_topic_posts * 2

    got_sum_num_posts_stored = db.query("select sum(num_posts_stored) from topic_post_days").flat()[0]

    assert got_sum_num_posts_stored == reduced_num_topic_posts



