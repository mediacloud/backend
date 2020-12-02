import mediawords.db
from topics_mine.mine import *

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_story_within_topic_date_range():
    topic = {'start_date': '2020-01-01', 'end_date': '2020-02-01'}
    
    assert story_within_topic_date_range(topic, {'publish_date': '2020-01-15'})
    assert story_within_topic_date_range(topic, {'publish_date': '2019-12-30'})
    assert story_within_topic_date_range(topic, {'publish_date': '2020-02-05'})
    assert not story_within_topic_date_range(topic, {'publish_date': '2021-01-15'})
    assert not story_within_topic_date_range(topic, {'publish_date': '2019-01-15'})
    assert story_within_topic_date_range(topic, {'publish_date': None})
