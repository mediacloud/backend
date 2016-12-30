import tarfile
import tempfile

from nose.tools import assert_raises

from mediawords.util.compress import *


def test_extract_tarball_to_directory():
    src_temp_dir = tempfile.mkdtemp()
    dst_temp_dir = tempfile.mkdtemp()

    # Nonexistent archive
    assert_raises(McExtractTarballToDirectoryException, extract_tarball_to_directory,
                  os.path.join(src_temp_dir, 'nonexistent-archive.tgz'), dst_temp_dir)

    # Unsupported archive
    unsupported_archive_path = os.path.join(src_temp_dir, 'unsupported-archive.tar.bz2')
    run_command_in_foreground(['touch', unsupported_archive_path])
    assert_raises(McExtractTarballToDirectoryException, extract_tarball_to_directory, unsupported_archive_path,
                  dst_temp_dir)

    # Faulty archive
    faulty_archive_path = os.path.join(src_temp_dir, 'faulty-archive.tgz')
    with open(faulty_archive_path, 'w') as fh:
        fh.write('Totally not valid Gzip data.')
    assert_raises(McExtractTarballToDirectoryException, extract_tarball_to_directory, faulty_archive_path, dst_temp_dir)

    # .tar.gz archive
    tar_archive_path = os.path.join(src_temp_dir, 'tar-gz-archive.tar.gz')
    tar_archive_contents_dir = os.path.join(src_temp_dir, 'test-contents')
    os.mkdir(tar_archive_contents_dir)
    with open(os.path.join(tar_archive_contents_dir, 'test.txt'), 'w') as fh:
        fh.write('Test contents')
    with tarfile.open(tar_archive_path, "w:gz") as tar:
        tar.add(tar_archive_contents_dir, arcname=os.path.basename(tar_archive_contents_dir))

    extract_tarball_to_directory(archive_file=tar_archive_path, dest_directory=dst_temp_dir)

    assert os.path.isdir(os.path.join(dst_temp_dir, 'test-contents'))
    assert os.path.isfile(os.path.join(dst_temp_dir, 'test-contents', 'test.txt'))

    # Strip root
    dst_strip_root_temp_dir = tempfile.mkdtemp()
    extract_tarball_to_directory(archive_file=tar_archive_path, dest_directory=dst_strip_root_temp_dir, strip_root=True)
    assert os.path.isdir(os.path.join(dst_strip_root_temp_dir, 'test-contents')) is False
    assert os.path.isfile(os.path.join(dst_strip_root_temp_dir, 'test.txt'))
