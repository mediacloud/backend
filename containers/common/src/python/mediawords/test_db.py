import pytest

from mediawords.db import connect_to_db, McConnectToDBException


def test_connect_to_db():
    # Default database
    db = connect_to_db(do_not_check_schema_version=True)
    database_name = db.query('SELECT current_database()').hash()
    assert database_name['current_database'] == 'mediacloud'

    # Test database
    db = connect_to_db(label='test', do_not_check_schema_version=True)
    database_name = db.query('SELECT current_database()').hash()
    assert database_name['current_database'] == 'mediacloud_test'

    # Invalid label
    with pytest.raises(McConnectToDBException):
        connect_to_db('NONEXISTENT_LABEL')
