#!/usr/bin/env py.test

from mediawords.db import connect_to_db


def test_connect_to_db():
    # Default database
    db = connect_to_db()
    database_name = db.query('SELECT current_database()').hash()
    assert database_name['current_database'] == 'mediacloud'
