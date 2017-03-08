import tempfile

from nose.tools import assert_raises

from mediawords.util.config import *


def test_get_config():
    config = get_config()
    assert 'database' in config
    assert 'mediawords' in config
    assert 'data_dir' in config['mediawords']


# FIXME unit test not really stateless
def test_set_config_file():
    root_path = mc_root_path()

    # Test with .yml.dist
    mediawords_yml_dist_path = os.path.join(root_path, 'mediawords.yml.dist')
    assert os.path.isfile(mediawords_yml_dist_path)
    old_config = get_config()
    set_config_file(mediawords_yml_dist_path)
    set_config(old_config)

    # Test with .yml
    mediawords_yml_path = os.path.join(root_path, 'mediawords.yml')
    assert os.path.isfile(mediawords_yml_path)
    old_config = get_config()
    set_config_file(mediawords_yml_path)
    set_config(old_config)


def test_set_config_file_nonexistent():
    old_config = get_config()
    tempdir = tempfile.mkdtemp()
    nonexistent_config = os.path.join(tempdir, 'nonexistent_configuration.yml')
    assert os.path.exists(nonexistent_config) is False
    assert_raises(McConfigException, set_config_file, nonexistent_config)
    set_config(old_config)
