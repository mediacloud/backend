from mediawords.util.paths import *


def test_mc_root_path():
    root_path = mc_root_path()
    assert os.path.exists(root_path)
    assert os.path.isdir(root_path)


def test_mc_script_path():
    script_path = mc_script_path()
    assert os.path.exists(script_path)
    assert os.path.isdir(script_path)
