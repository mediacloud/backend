#!/usr/bin/env python3

import argparse
import boto3
import os
from typing import List

from mediawords.util.log import create_logger

l = create_logger(__name__)


def delete_bitly_blobs(story_ids: List[int]):
    session = boto3.Session(profile_name='mediacloud')
    s3 = session.resource('s3')
    bucket = s3.Bucket('mediacloud-bitly-processing-results')

    chunk_size = 999  # up to 1000 objects to be deleted at once
    story_ids_chunks = [story_ids[x:x + chunk_size] for x in range(0, len(story_ids), chunk_size)]

    l.info('Deleting %d Bit.ly blobs, split into %d chunks...' % (len(story_ids), len(story_ids_chunks)))

    chunk_num = 1
    for chunk in story_ids_chunks:
        objects_to_delete = []

        l.info('Deleting chunk %d out of %d...' % (chunk_num, len(story_ids_chunks)))
        chunk_num += 1

        for stories_id in chunk:
            objects_to_delete.append({'Key': 'json_blobs/%d' % stories_id})

        bucket.delete_objects(
            Delete={
                'Objects': objects_to_delete,
            }
        )

    l.info('Done deleting %d Bit.ly blobs.' % len(story_ids))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Delete Bit.ly raw results from S3.',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-i', '--input_file', type=str, required=True, help='Input file with Bit.ly story IDs.')

    args = parser.parse_args()

    if not os.path.isfile(args.input_file):
        raise Exception('Input file "%s" does not exist.' % args.input_file)

    bitly_story_ids = []
    with open(args.input_file, 'r') as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line:
                line = int(line)
                bitly_story_ids.append(line)

    delete_bitly_blobs(story_ids=bitly_story_ids)
