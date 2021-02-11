from mediawords.util.sql import (
    get_sql_date_from_epoch,
    sql_now,
    get_epoch_from_sql_date,
    increment_day,
)

import time
import datetime


def test_get_sql_date_from_epoch():
    assert get_sql_date_from_epoch(int(time.time())) == datetime.datetime.today().strftime('%Y-%m-%d %H:%M:%S')
    assert get_sql_date_from_epoch(0) == datetime.datetime.fromtimestamp(0).strftime('%Y-%m-%d %H:%M:%S')
    # noinspection PyTypeChecker
    assert get_sql_date_from_epoch('badger') == datetime.datetime.fromtimestamp(0).strftime('%Y-%m-%d %H:%M:%S')


def test_sql_now():
    assert sql_now() == datetime.datetime.today().strftime('%Y-%m-%d %H:%M:%S')


def test_get_epoch_from_sql_date():
    assert get_epoch_from_sql_date('2016-10-11 10:34:24.598883+03') == 1476171264


def test_increment_day():
    assert increment_day(date='2016-10-11', days=3) == '2016-10-14'
