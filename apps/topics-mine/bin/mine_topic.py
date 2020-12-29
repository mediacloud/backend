#!/usr/bin/env python3

import argparse

from mediawords.db import connect_to_db
from topics_mine.mine import mine_topic

def main():
    """run mine_topic with cli args."""
    parser = argparse.ArgumentParser(description="Run topics_mine job.")
    parser.add_argument("-t", "--topics_id", type=int, required=True)
    parser.add_argument("-s", "--snapshots_id", type=int, required=False)
    parser.add_argument("-r", "--resume_snapshot", type=bool, required=False)
    parser.add_argument("-i", "--import_only", type=bool, required=False)
    parser.add_argument("-p", "--skip_post_processing", type=bool, required=False)
    args = parser.parse_args()

    snapshots_id = args.snapshots_id
    if args.resume_snapshot:
        snapshots_id = db.query(
            "select snapshots_id from snapshots where topics_id = %(a)s order by snapshots_id desc limit 1",
            {'a': args.topics_id}).flat()[0]


    db = connect_to_db()

    topic = db.require_by_id('topics', args.topics_id)

    mine_topic(
        db=db,
        topic=topic,
        snapshots_id=snapshots_id,
        import_only=args.import_only,
        skip_post_processing=args.skip_post_processing)

main()
