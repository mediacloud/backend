#!/usr/bin/env python3

"""
Makes sure all the required models are downloaded and extracted
"""

import os
import subprocess


def __download_file(url: str, dest_path: str) -> None:
    """
    Download file to target path.
    :param url: URL to download.
    :param dest_path: Target path and filename to download to.
    :return:
    """

    # System cURL is way faster than Python's requests at downloading huge files
    args = [
        "curl",
        # "--silent",
        "--continue-at", "-",
        "--show-error",
        "--fail",
        "--retry", "3",
        "--retry-delay", "5",
        "--output", dest_path,
        url
    ]
    subprocess.check_call(args)


def __decompress_file(brotli_file: str) -> None:
    """
    Decompress Brotli file to destination directory.
    :param brotli_file: Brotli file to decompress.
    """
    args = ["brotli", "-d", brotli_file]
    subprocess.check_call(args)


def download_model(url: str, dest_dir: str, expected_size: int):
    """
    Download model from URL to a specified destination directory, check if the size is correct, decompress.
    :param url: URL to download from.
    :param dest_dir: Directory to save the file to.
    :param expected_size: Size in bytes that the compressed file is expected to be.
    """

    if not os.path.isdir(dest_dir):
        os.mkdir(dest_dir)

    filename = os.path.basename(url)
    dest_path = os.path.join(dest_dir, filename)

    # File that gets created for every model when its downloaded and extracted successfully
    downloaded_marker_file = ".%s.downloaded" % (filename,)
    downloaded_marker_path = os.path.join(dest_dir, downloaded_marker_file)

    if os.path.exists(downloaded_marker_path):
        print("Model %s already exists." % (dest_path,))

    else:

        need_to_download = True
        if os.path.isfile(dest_path):
            if os.path.getsize(dest_path) != expected_size:
                print("Found a partial download, will continue it at %s..." % (dest_path,))
            else:
                need_to_download = False
        else:
            print("Model %s was not found, will start download from %s..." % (dest_path, url,))

        if need_to_download:
            __download_file(url=url, dest_path=dest_path)

        if os.path.getsize(dest_path) != expected_size:
            raise Exception("Downloaded file size is not %d." % (expected_size,))

        print("Decompressing %s to %s..." % (dest_path, dest_dir,))
        __decompress_file(brotli_file=dest_path)

        os.unlink(dest_path)

        open(downloaded_marker_path, 'a').close()


def download_all_models():
    """Download and prepare all the required models."""

    pwd = os.path.dirname(os.path.realpath(__file__))
    dest_dir = pwd + '/models/'
    base_url = 'https://mediacloud-nytlabels-data.s3.amazonaws.com/predict-news-labels-keyedvectors',

    models = [
        # See word2vec_to_keyedvectors.py
        {
            'url': '%s/GoogleNews-vectors-negative300.keyedvectors.bin.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 68284073,
        },
        {
            'url': '%s/GoogleNews-vectors-negative300.keyedvectors.bin.vectors.npy.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 1316205343,
        },
        {
            'url': '%s/all_descriptors.hdf5.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 370734856,
        },
        {
            'url': '%s/descriptors_3000.hdf5.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 61285705,
        },
        {
            'url': '%s/descriptors_600.hdf5.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 21018967,
        },
        {
            'url': '%s/descriptors_with_taxonomies.hdf5.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 95996935,
        },
        {
            'url': '%s/just_taxonomies.hdf5.br' % base_url,
            'dest_dir': dest_dir,
            'expected_size': 51423506,
        },
    ]

    for model in models:
        download_model(url=model['url'], dest_dir=model['dest_dir'], expected_size=model['expected_size'])


if __name__ == '__main__':
    download_all_models()
