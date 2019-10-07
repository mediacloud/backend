#!/usr/bin/env python3

import csv
import multiprocessing
import os
import sys

from mediawords.util.url import normalize_url, is_http_url


def __normalize_media_url(output_dir: str, media_id: str, url: str, queue: multiprocessing.Queue) -> None:
    if is_http_url(url):
        normalized_url = normalize_url(url)
        output_file = os.path.join(output_dir, media_id)
        queue.put((output_file, normalized_url,))


def __write_to_files(queue: multiprocessing.Queue) -> None:
    media_id_files = {}

    while 1:
        filename, normalized_url = queue.get()

        if filename == 'kill':
            break

        if filename not in media_id_files:
            media_id_files[filename] = open(filename, mode='w', buffering=100 * 1024)

        media_id_files[filename].write(normalized_url + "\n")
        # media_id_files[filename].flush()

    for media_id_file in media_id_files.values():
        media_id_file.close()


def normalize_urls(file_path: str, output_dir: str):
    assert os.path.isfile(file_path)
    assert os.path.isdir(output_dir)

    manager = multiprocessing.Manager()
    queue = manager.Queue()
    pool = multiprocessing.Pool(multiprocessing.cpu_count() + 2)
    watcher = pool.apply_async(__write_to_files, (queue,))

    jobs = []

    max_jobs = 1000 * 1000

    with open(file_path, mode='r') as stories_file:
        job_number = 0
        reader = csv.DictReader(stories_file)
        for row in reader:
            media_id = row['media_id']
            url = row['url']

            job = pool.apply_async(__normalize_media_url, (output_dir, media_id, url, queue))
            jobs.append(job)

            job_number += 1
            if job_number >= max_jobs:
                for job in jobs:
                    job.get()
                job_number = 0

    for job in jobs:
        job.get()

    queue.put(('kill', '',))

    pool.close()
    pool.join()


def main():
    file_path = sys.argv[1]
    output_dir = sys.argv[2]

    normalize_urls(file_path=file_path, output_dir=output_dir)


if __name__ == '__main__':
    main()
