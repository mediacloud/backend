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


def test_resolve_absolute_path_under_mc_root():
    path = resolve_absolute_path_under_mc_root(path='.', must_exist=True)
    assert len(path) > 0

    # Path that exists
    path = resolve_absolute_path_under_mc_root(path='mediawords.yml', must_exist=True)
    assert len(path) > 0
    assert os.path.isfile(path) is True

    # Path that does not exist
    path = resolve_absolute_path_under_mc_root(path='TOTALLY_DOES_NOT_EXIST', must_exist=False)
    assert len(path) > 0
    assert os.path.isfile(path) is False
