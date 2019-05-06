import mediawords.test.db.create
import mediawords.test.test_database
from mediawords.util.sql import (get_sql_date_from_epoch, sql_now, get_epoch_from_sql_date,
                                 increment_day)

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

class TestUtilSQLDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_get_normalized_title(self) -> None:
        """Test plpgsql get_normalized_title() function."""
        db = self.db()


        # simple title
        (got_title,) = db.query("select get_normalized_title('foo bar', 0)").flat()
        assert got_title == 'foo bar'

        # simple title part
        title_part = "foo barfoo barfoo barfoo barfoo bar"
        title = title_part + ': bat baz'
        (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': title}).flat()
        assert got_title == title_part

        title_part = "foo barfoo barfoo barfoo barfoo bar"
        title = 'bat baz: ' + title_part 
        (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': title}).flat()
        assert got_title == title_part

        title_part = "foo barfoo barfoo barfoo barfoo bar"
        title = 'bat baz - ' + title_part 
        (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': title}).flat()
        assert got_title == title_part

        # strip punctuation
        (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': 'foo!@#bar&*('}).flat()
        assert got_title == 'foobar'

        # require 32 character length
        (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': 'foo bar: bat'}).flat()
        assert got_title == 'foo barSEPSEP bat'

        # don't allow medium name as title part
        medium_name = 'A' * 64
        medium = mediawords.test.db.create.create_test_medium(db, medium_name)
        title = medium_name + ': foo bar'
        (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': title}).flat()
        assert got_title == medium_name.lower() + 'SEPSEP foo bar'

        
        

