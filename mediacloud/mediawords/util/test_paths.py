import tempfile

from mediawords.util.paths import *


def test_mc_root_path():
    root_path = mc_root_path()
    assert os.path.exists(root_path)
    assert os.path.isdir(root_path)


def test_mc_script_path():
    script_path = mc_script_path()
    assert os.path.exists(script_path)
    assert os.path.isdir(script_path)


def test_mkdir_p():
    temp_dir = tempfile.mkdtemp()

    test_dir = os.path.join(temp_dir, 'foo', 'bar', 'baz')
    assert os.path.isdir(test_dir) is False

    mkdir_p(test_dir)
    assert os.path.isdir(test_dir) is True

    # Try creating again
    mkdir_p(test_dir)
    assert os.path.isdir(test_dir) is True
