#!/usr/bin/env python3

""" Requeue all topics that have been stuck in a running state for more than a day."""

import mediawords.db
from mediawords.job import JobBroker

from mediawords.util.log import create_logger

log = create_logger(__name__)

def main():
    db = mediawords.db.connect_to_db()

    hung_topics = db.query(
        """
        with 

        topic_jobs as ( select *, ( args->>'topics_id' )::int topics_id from job_states where class like '%Topic%' ),

        ranked_jobs as ( select *, rank() over ( partition by topics_id order by last_updated desc ) from topic_jobs )

        select 
                j.topics_id, j.state, j.class, j.last_updated, j.args->>'snapshots_id' snapshots_id
            from ranked_jobs j
            where 
                last_updated < now() - '1 day'::interval and 
                rank = 1 and 
                j.state not in ( 'completed', 'error' ) 
            order by last_updated desc
            limit 1
        """).hashes()

    log.info("hung_topics: %d" % len(hung_topics))

    for topic in hung_topics:
        log.info(f"queueing topic {topic}")
        topics_id = topic['topics_id']
        snapshots_id = topic['snapshots_id']
        JobBroker(queue_name=topic['class']).add_to_queue(topics_id=topics_id, snapshots_id=snapshots_id)

main()
