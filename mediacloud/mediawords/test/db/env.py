import os

__TEST_DB_ENV_LABEL = 'MEDIAWORDS_FORCE_USING_TEST_DATABASE'


def force_using_test_database():
    """Set correct environment variable to use the test database."""
    os.environ[__TEST_DB_ENV_LABEL] = "1"


def using_test_database() -> bool:
    """Returns True if we are running within test_on_test_database."""
    if __TEST_DB_ENV_LABEL in os.environ and os.environ[__TEST_DB_ENV_LABEL] == "1":
        return True
    else:
        return False
