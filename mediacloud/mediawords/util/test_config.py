from mediawords.util.config import *


def test_get_config():
    config = get_config()
    assert 'database' in config
    assert 'mediawords' in config
    assert 'data_dir' in config['mediawords']
