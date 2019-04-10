#!/usr/bin/env py.test

import os
import tarfile
import tempfile
import zipfile

import pytest

from mediawords.util.compress import (
    extract_tarball_to_directory,
    extract_zip_to_directory,
    run_command_in_foreground,
    McExtractTarballToDirectoryException,
    McExtractZipToDirectoryException,
    gzip,
    gunzip,
    bzip2,
    bunzip2,
    McBunzip2Exception, McGunzipException, McGzipException, McBzip2Exception)


def test_extract_tarball_to_directory():
    src_temp_dir = tempfile.mkdtemp()
    dst_temp_dir = tempfile.mkdtemp()

    # Nonexistent archive
    with pytest.raises(McExtractTarballToDirectoryException):
        extract_tarball_to_directory(os.path.join(src_temp_dir, 'nonexistent-archive.tgz'),
                                     dst_temp_dir)

    # Unsupported archive
    unsupported_archive_path = os.path.join(src_temp_dir, 'unsupported-archive.tar.bz2')
    run_command_in_foreground(['touch', unsupported_archive_path])
    with pytest.raises(McExtractTarballToDirectoryException):
        extract_tarball_to_directory(unsupported_archive_path, dst_temp_dir)

    # Faulty archive
    faulty_archive_path = os.path.join(src_temp_dir, 'faulty-archive.tgz')
    with open(faulty_archive_path, 'w') as fh:
        fh.write('Totally not valid Gzip data.')

    with pytest.raises(McExtractTarballToDirectoryException):
        extract_tarball_to_directory(faulty_archive_path, dst_temp_dir)

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


def test_extract_zip_to_directory():
    src_temp_dir = tempfile.mkdtemp()
    dst_temp_dir = tempfile.mkdtemp()

    # Nonexistent archive
    with pytest.raises(McExtractZipToDirectoryException):
        extract_zip_to_directory(os.path.join(src_temp_dir, 'nonexistent-archive.zip'),
                                 dst_temp_dir)

    # Unsupported archive
    unsupported_archive_path = os.path.join(src_temp_dir, 'unsupported-archive.rar')
    run_command_in_foreground(['touch', unsupported_archive_path])
    with pytest.raises(McExtractZipToDirectoryException):
        extract_zip_to_directory(unsupported_archive_path, dst_temp_dir)

    # Faulty archive
    faulty_archive_path = os.path.join(src_temp_dir, 'faulty-archive.zip')
    with open(faulty_archive_path, 'w') as fh:
        fh.write('Totally not valid Zip data.')

    with pytest.raises(McExtractZipToDirectoryException):
        extract_zip_to_directory(faulty_archive_path, dst_temp_dir)

    # .zip archive
    zip_archive_path = os.path.join(src_temp_dir, 'zip-archive.zip')
    zip_archive_contents_dir = os.path.join(src_temp_dir, 'test-contents')
    os.mkdir(zip_archive_contents_dir)
    with open(os.path.join(zip_archive_contents_dir, 'test.txt'), 'w') as fh:
        fh.write('Test contents')

    def __create_zip(src, dst):
        """Create ZIP file, strip root directory first."""
        zf = zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED)
        abs_src = os.path.abspath(src)
        for dirname, sub_dirs, files in os.walk(src):
            for filename in files:
                abs_name = os.path.abspath(os.path.join(dirname, filename))
                arc_name = abs_name[len(abs_src) + 1:]
                zf.write(abs_name, arc_name)
        zf.close()

    __create_zip(src=zip_archive_contents_dir, dst=zip_archive_path)

    extract_zip_to_directory(archive_file=zip_archive_path, dest_directory=dst_temp_dir)

    # 'test-contents/' gets auto-stripped in __create_zip()
    assert os.path.isfile(os.path.join(dst_temp_dir, 'test.txt'))


# Strings to try to compress / decompress
__COMPRESS_TEST_DATA = [
    # ASCII
    b"Media Cloud\r\nMedia Cloud\nMedia Cloud\r\n",

    # UTF-8
    "Media Cloud\r\nąčęėįšųūž\n您好\r\n".encode('utf-8'),

    # Empty string
    b"",

    # Invalid UTF-8 sequences
    b"\xc3\x28",
    b"\xa0\xa1",
    b"\xe2\x28\xa1",
    b"\xe2\x82\x28",
    b"\xf0\x28\x8c\xbc",
    b"\xf0\x90\x28\xbc",
    b"\xf0\x28\x8c\x28",
    b"\xf8\xa1\xa1\xa1\xa1",
    b"\xfc\xa1\xa1\xa1\xa1\xa1",
]


def test_gzip():
    def __inner_test_gzip(data_: bytes) -> None:
        gzipped_data = gzip(data_)
        assert len(gzipped_data) > 0
        assert isinstance(gzipped_data, bytes)
        assert gzipped_data != data_

        gunzipped_data = gunzip(gzipped_data)
        assert gunzipped_data == data_

    for data in __COMPRESS_TEST_DATA:
        __inner_test_gzip(data_=data)


def test_gzip_bad_input():
    with pytest.raises(McGzipException):
        # noinspection PyTypeChecker
        gzip(None)

    with pytest.raises(McGunzipException):
        # noinspection PyTypeChecker
        gunzip(None)

    with pytest.raises(McGunzipException):
        gunzip(b'')

    with pytest.raises(McGunzipException):
        gunzip(b'No way this is valid Gzip data')


def test_bzip2():
    def __inner_test_bzip2(data_: bytes) -> None:
        bzipped_data = bzip2(data_)
        assert len(bzipped_data) > 0
        assert isinstance(bzipped_data, bytes)
        assert bzipped_data != data_

        bunzipped_data = bunzip2(bzipped_data)
        assert bunzipped_data == data_

    for data in __COMPRESS_TEST_DATA:
        __inner_test_bzip2(data_=data)


def test_bzip2_bad_input():
    with pytest.raises(McBzip2Exception):
        # noinspection PyTypeChecker
        bzip2(None)

    with pytest.raises(McBunzip2Exception):
        # noinspection PyTypeChecker
        bunzip2(None)

    with pytest.raises(McBunzip2Exception):
        bunzip2(b'')

    with pytest.raises(McBunzip2Exception):
        bunzip2(b'No way this is valid Bzip2 data')


def test_wrong_algorithm():
    def __inner_test_wrong_algorithm(data_: bytes) -> None:
        with pytest.raises(McBunzip2Exception):
            bunzip2(gzip(data_))
        with pytest.raises(McGunzipException):
            gunzip(bzip2(data_))

    for data in __COMPRESS_TEST_DATA:
        __inner_test_wrong_algorithm(data_=data)
