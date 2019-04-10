#!/usr/bin/env py.test

import os
import tempfile

import pytest

from mediawords.util.web import (download_file, download_file_to_temp_path,
                                 McDownloadFileException, McDownloadFileToTempPathException)


def test_download_file():
    dst_temp_dir = tempfile.mkdtemp()
    dst_path = os.path.join(dst_temp_dir, 'robots.txt')

    # Existent URL
    download_file(source_url='https://www.google.com/robots.txt', target_path=dst_path)
    assert os.path.isfile(dst_path)
    assert os.path.getsize(dst_path) > 0

    # Nonexistent URL
    with pytest.raises(McDownloadFileException):
        download_file('https://mediacloud.org/should-not-exist.txt', dst_path)


def test_download_file_to_temp_path():
    # Existent URL
    temp_file = download_file_to_temp_path(source_url='https://www.google.com/robots.txt')
    assert os.path.isfile(temp_file)
    assert os.path.getsize(temp_file) > 0

    # Nonexistent URL
    with pytest.raises(McDownloadFileToTempPathException):
        download_file_to_temp_path('https://mediacloud.org/should-not-exist.txt')
