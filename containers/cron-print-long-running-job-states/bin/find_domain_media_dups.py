#!/usr/bin/env python3

"""
generate a csv report of all media with active feeds that would be duped into other media by the
domain_media switch.
"""

import sys

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.url import get_url_distinctive_domain

log = create_logger(__name__)


def print_long_running_job_states(db: DatabaseHandler, limit: int):
    media = db.query("""
        select m.*, mh.*
        from media m
            join media_health mh using ( media_id ) 
        where dup_media_id is null
        order by m.media_id asc limit %(a)s
    """, {'a': limit}).hashes()

    media_groups = {}

    num_media = len(media)
    for i, medium in enumerate(media):
        domain = get_url_distinctive_domain(medium['url'])
        log.warning("%s [%d/%d]" % (domain, i, num_media))

        if domain not in media_groups:
            media_groups[domain] = []

        media_groups[domain].append(medium)

        medium['medium_domain'] = domain
        medium['dup_domain_matches'] = True

        dup_media = db.query(
            "select m.*, mh.* from media m join media_health mh using ( media_id ) where dup_media_id = %(a)s",
            {'a': medium['media_id']}
        ).hashes()

        media_groups[domain].extend(dup_media)

        for dup_medium in dup_media:
            dup_domain = get_url_distinctive_domain(dup_medium['url'])
            medium['medium_domain'] = dup_domain
            medium['dup_domain_matches'] = domain == dup_domain

    db.query("drop table if exists media_dups")
    db.query(
        """
        create table media_dups (
            domain text,
            media_id int
            )
        """)

    db.begin()
    for i, domain in enumerate(media_groups.keys()):
        log.warning("domain %s [%d/%d]" % (domain, i, len(media_groups.keys())))
        media = media_groups[domain]
        if len(media) > 1:
            for m in media:
                db.query("""
                    insert into media_dups (domain, media_id) values (%(a)s, %(b)s)
                """, {'a': domain, 'b': m['media_id']})
    db.commit()


if __name__ == '__main__':
    limit_ = sys.argv[1] if len(sys.argv) > 1 else 10000000

    db_ = connect_to_db()

    print_long_running_job_states(db=db_, limit=limit_)
