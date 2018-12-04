#!/usr/bin/env python

"""
print a count of job_states that have been running or queued for longer than a day
"""

import sys

import mediawords.db
import mediawords.util.log

log = mediawords.util.log.create_logger(__name__)

def main():
    db = mediawords.db.connect_to_db()

    counts = db.query("""
        select class, count(*) as count, min(last_updated::date) as min_date, max(last_updated::date) as max_date
            from ( 
                select *,   
                        rank() over ( partition by class, (args->>'media_id')::int order by last_updated desc ) 
                            as media_rank,
                        args->>'media_id' as media_id
                    from job_states ) q 
            where 
                media_rank = 1 and 
                state in( 'queued', 'running') and 
                last_updated < now() - interval '1 day' 
            group by class
            order by class
    """).hashes()

    if len(counts) > 0:
        print("Long Running Jobs:\n")

    for count in counts:
        print("%s: %d (%s - %s)" % (count['class'], count['count'], count['min_date'], count['max_date']))
        
main()
