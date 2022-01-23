from topics_mine.mine import _import_month_within_respider_date

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_import_month_with_respider_date():
    topic = {
        'start_date': '2019-01-01',
        'end_date': '2019-06-01',
        'respider_stories': 'f',
        'respider_start_date': None,
        'respider_end_date': None}

    # if none of the respider setting are correct, we should always return true
    assert _import_month_within_respider_date(topic, 0)
    assert _import_month_within_respider_date(topic, 1)
    assert _import_month_within_respider_date(topic, 100)

    # if respider_stories is true but neither respider date is set, always return true
    topic['respider_stories'] = 1
    assert _import_month_within_respider_date(topic, 0)
    assert _import_month_within_respider_date(topic, 1)
    assert _import_month_within_respider_date(topic, 100)

    # should only import the dates after the respider end date
    topic['respider_end_date'] = '2019-05-01'
    assert not _import_month_within_respider_date(topic,  0)
    assert not _import_month_within_respider_date(topic, 3)
    assert _import_month_within_respider_date(topic, 4)

    # make sure we capture the whole previous month if the end date is within a month
    topic['respider_end_date'] = '2019-04-02'
    assert _import_month_within_respider_date(topic,  3)

    # should only import the dates before the repsider start date
    topic['respider_start_date'] = '2019-02-01'
    assert _import_month_within_respider_date(topic,  0)
    assert not _import_month_within_respider_date(topic,  1)
