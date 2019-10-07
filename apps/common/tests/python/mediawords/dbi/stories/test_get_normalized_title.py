from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium


def test_get_normalized_title():
    db = connect_to_db()

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
    create_test_medium(db, medium_name)
    title = medium_name + ': foo bar'
    (got_title,) = db.query("select get_normalized_title(%(title)s, 1)", {'title': title}).flat()
    assert got_title == medium_name.lower() + 'SEPSEP foo bar'
