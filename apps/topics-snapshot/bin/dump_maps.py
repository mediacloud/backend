#!/usr/bin/env python3

"""Dump all maps with the snapshot in a directory strucre:

topics_id
    focal_set
        focus
            period
                start_date
                    map
"""

import os
import sys

import mediawords.db

from mediawords.util.log import create_logger

log = create_logger(__name__)

def main():
    if len(sys.argv) < 2:
        raise Error("usage: dump_topic_maps.py <snapshots_id>");

    snapshots_id = sys.argv[1]

    db = mediawords.db.connect_to_db()

    snapshot = db.require_by_id('snapshots', snapshots_id)

    timespan_maps = db.query(
        """
        select 
                t.*,
                tm.*,
                f.name focus_name, fs.name focal_set_name
            from timespans t
                join timespan_maps tm using ( timespans_id )
                left join foci f using ( foci_id )
                left join focal_sets fs using ( focal_sets_id )
            where t.snapshots_id = %(a)s
        """,
        {'a': snapshots_id}
    ).hashes()

    for tm in timespan_maps:
        filename = "%s.%s" % (tm['options'].get('color_by', 'default'), tm['format'])
        directory = '%d/%s/%s/%s/%s' % ( 
            snapshot['topics_id'],
            tm['focal_set_name'],
            tm['focus_name'],
            tm['period'],
            tm['start_date'][0:10],
        )

        os.makedirs(directory, exist_ok=True)

        full_path = "%s/%s" % (directory, filename)

        log.warning("writing %s..." % full_path)

        f = open(full_path, 'wb')

        f.write(tm['content'])


main()

