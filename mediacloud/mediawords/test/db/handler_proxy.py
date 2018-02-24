"""Python defined functions for use in MediaWords/DB/t/HandlerProxy.t tests."""

from mediawords.db import DatabaseHandler


def get_single_row_hashes(db: DatabaseHandler) -> list:
    """Return a single row result from db.query().hashes().

    This is to test from perl the result of a python query call when called using a perl HandlerProxy object.
    """
    return db.query("select 'foo' as foo").hashes()
