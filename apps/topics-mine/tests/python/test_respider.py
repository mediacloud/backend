import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
import mediawords.util.sql
import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_social_media_data():
    db = mediawords.db.connect_to_db()

    topic = create_test_topic(db, 'foo')

    topic['start_date'] = '2017-01-01'
    topic['end_date'] = '2018-01-01'

    topic = db.update_by_id(
        'topics',
        topic['topics_id'],
        { 'max_stories': 0, 'start_date': '2017-01-01', 'end_date': '2018-01-01' }
    )

    num_stories = 101
    create_test_topic_stories(db, topic, 1, num_stories)

    # no respidering without respider_stories
    db.query("update topic_stories set link_mined = 't'")

    topics_mine.mine.set_stories_respidering(db, topic, None)

    got_num_respider_stories = db.query( "select count(*) from topic_stories where not link_mined" ).flat()[0]
    assert got_num_respider_stories == 0

    # respider everything with respider_stories but no dates
    topic['respider_stories'] = 1

    db.query("update topic_stories set link_mined = 't'")

    topics_mine.mine.set_stories_respidering(db, topic, None)

    got_num_respider_stories = db.query( "select count(*) from topic_stories where not link_mined" ).flat()[0]
    assert got_num_respider_stories == num_stories

    # respider stories within the range of changed dates
    topic_update = {
        'respider_stories': 't',
        'respider_end_date': topic['end_date'],
        'respider_start_date': topic['start_date'],
        'end_date': '2019-01-01',
        'start_date': '2016-01-01'
    }

    topic = db.update_by_id('topics', topic['topics_id'], topic_update)

    db.query("update topic_stories set link_mined = 't'")

    num_date_changes = 10
    db.query("update stories set publish_date = '2017-06-01'")
    db.query(
        """
        update stories set publish_date = %(a)s where stories_id in 
            (select stories_id from stories order by stories_id limit %(b)s)
        """,
        {'a': '2018-06-01', 'b': num_date_changes})
    db.query(
        """
        update stories set publish_date = %(a)s where stories_id in 
            (select stories_id from stories order by stories_id desc limit %(b)s)
        """,
        {'a': '2016-06-01', 'b': num_date_changes})

    snapshot = {
        'topics_id': topic['topics_id'],
        'snapshot_date': mediawords.util.sql.sql_now(),
        'start_date': topic['start_date'],
        'end_date': topic['end_date']}

    snapshot = db.create('snapshots', snapshot)

    timespan_dates = [['2017-01-01', '2017-01-31'], ['2017-12-20', '2018-01-20'], ['2016-12-20', '2017-01-20']]

    for dates in timespan_dates:
        (start_date, end_date) = dates
        timespan = {
            'snapshots_id': snapshot['snapshots_id'],
            'start_date': start_date,
            'end_date': end_date,
            'period': 'monthly',
            'story_count': 0,
            'story_link_count': 0,
            'medium_count': 0,
            'medium_link_count': 0,
            'post_count': 0}

        timespan = db.create('timespans', timespan)

    topics_mine.mine.set_stories_respidering(db, topic, snapshot['snapshots_id'])

    got_num_respider_stories = db.query("select count(*) from topic_stories where not link_mined").flat()[0]
    assert got_num_respider_stories == 2 * num_date_changes

    got_num_archived_timespans = db.query(
        "select count(*) from timespans where archive_snapshots_id = %(a)s",
        {'a': snapshot['snapshots_id']}).flat()[0]
    assert got_num_archived_timespans == 2
