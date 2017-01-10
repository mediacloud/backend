import tempfile

from nose.tools import assert_raises

from mediawords.util.config import *


def test_get_config():
    config = get_config()
    assert 'database' in config
    assert 'mediawords' in config
    assert 'data_dir' in config['mediawords']


def test_set_config_file_nonexistent():
    tempdir = tempfile.mkdtemp()
    nonexistent_config = os.path.join(tempdir, 'nonexistent_configuration.yml')
    assert os.path.exists(nonexistent_config) is False
    assert_raises(McConfigException, set_config_file, nonexistent_config)


def test_set_config_no_database_connections():
    assert_raises(McConfigException, set_config, {'name': 'MediaWords'})
    assert_raises(McConfigException, set_config, {'name': 'MediaWords', 'database': None})
