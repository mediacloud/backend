import os
import tempfile

import mediawords.util.paths as mc_paths


def test_mkdir_p():
    temp_dir = tempfile.mkdtemp()

    test_dir = os.path.join(temp_dir, 'foo', 'bar', 'baz')
    assert os.path.isdir(test_dir) is False

    mc_paths.mkdir_p(test_dir)
    assert os.path.isdir(test_dir) is True

    # Try creating again
    mc_paths.mkdir_p(test_dir)
    assert os.path.isdir(test_dir) is True


def test_relative_symlink():
    temp_dir = tempfile.mkdtemp()

    source_dir = os.path.join(temp_dir, 'src', 'a', 'b', 'c')
    mc_paths.mkdir_p(source_dir)
    with open(os.path.join(source_dir, 'test.txt'), 'w') as fh:
        fh.write('foo')

    dest_dir = os.path.join(temp_dir, 'dst', 'd', 'e')
    mc_paths.mkdir_p(dest_dir)
    dest_symlink = os.path.join(dest_dir, 'f')

    mc_paths.relative_symlink(source=source_dir, link_name=dest_symlink)

    assert os.path.exists(dest_symlink)
    assert os.path.lexists(dest_symlink)
    assert os.path.islink(dest_symlink)
    assert os.path.exists(os.path.join(dest_symlink, 'test.txt'))


def test_file_extension():
    assert mc_paths.file_extension('') == ''
    assert mc_paths.file_extension('test') == ''
    assert mc_paths.file_extension('test.zip') == '.zip'
    assert mc_paths.file_extension('/var/lib/test.zip') == '.zip'
    assert mc_paths.file_extension('../../test.zip') == '.zip'
    assert mc_paths.file_extension('./../../test.zip') == '.zip'
    assert mc_paths.file_extension('TEST.ZIP') == '.zip'
    assert mc_paths.file_extension('test.tar.gz') == '.gz'
    assert mc_paths.file_extension('TEST.TAR.GZ') == '.gz'
