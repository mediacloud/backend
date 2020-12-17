#!/usr/bin/env python3

""" 
Look for topics that are in an error or queued state that have not been updated in the last day.  For topics 
in an error state, ask the user whether to requeue, ignore, or cancel.  For all other topics, requeue the topic.
"""

import mediawords.db
from mediawords.job import StatefulJobBroker

from mediawords.util.log import create_logger

log = create_logger(__name__)


def queue_job(topic: dict, snapshots_id: int) -> None:
    """queue a mine or snapshot job."""
    StatefulJobBroker(queue_name=topic['class']).add_to_queue(topics_id=topic['topics_id'], snapshots_id=snapshots_id)

def main():
    db = mediawords.db.connect_to_db()

    waiting_topics = db.query(
        """
        with 

        topic_jobs as ( 
            select *, ( args->>'topics_id' )::int topics_id 
                from job_states 
                where 
                    class like '%Topic%' and 
                    coalesce( message, '' ) not like '%is already running%'
        ),

        ranked_jobs as ( select *, rank() over ( partition by topics_id order by last_updated desc ) from topic_jobs )

        select 
                t.name, j.topics_id, j.state, j.class, j.last_updated, j.job_states_id,
                coalesce( j.message, '' ) as  message, 
                j.args->>'snapshots_id' snapshots_id,
                now() n, rank r
            from ranked_jobs j
                join topics t on ( t.topics_id = ( j.args->>'topics_id' )::int )
            where 
                last_updated < now() - '1 day'::interval and 
                rank = 1 and 
                j.state not in ( 'completed' ) and
                coalesce( j.message, '' ) not like 'canceled%' and
                coalesce( j.message, '' ) not like '%exceeds topic max stories%' and
                coalesce( j.message, '' ) not like '%eed_query returned more than%' and
                last_updated > now() - interval '180 days'
                
            order by topics_id desc
        """).hashes()

    log.info("waiting topics: %d" % len(waiting_topics))

    hung_topics = filter(lambda x: x['state'] != 'error', waiting_topics)

    for topic in hung_topics:
        print(f"queueing topic: {topic['topics_id']}: {topic['name']} - {topic['state']} {topic['last_updated']}")
        topics_id = topic['topics_id']
        snapshots_id = topic['snapshots_id']
        queue_job(topic, snapshots_id)

    errored_topics = filter(lambda x: x['state'] == 'error', waiting_topics)

    for topic in errored_topics:
        topics_id = topic['topics_id']
        snapshots_id = topic['snapshots_id']

        print(f"{topics_id}: {topic['name']} - {topic['state']} {topic['last_updated']}")
        print(topic['snapshots_id'])
        print(f"\t{topic['message'][0:100]}")
        print(f"\thttps://topics.mediacloud.org/#/topics/{topics_id}/summary\n")

        while True:
            action = input('(r)equeue, (d)elete fetch errors, (c)ancel, (i)gnore, or (f)ull message? ')
            if action == 'r':
                # requeue a spider job for the topic
                print('requeueing...')
                queue_job(topic, snapshots_id)
                break
            elif action == 'd':
                # delete all topic_fetch_url python errors -- do this if we know the cause of the errors
                # and want the topic to succeed any way rather than triggering a 'fetch error rate ... is greater' err
                print('deleting topic_fetch_url errors...')
                db.query(
                    "delete from topic_fetch_urls where topics_id = %(a)s and state = 'python error'",
                    {'a': topics_id})
            elif action == 'c':
                # prepend the 'canceled: ' string to the start of the error message so that topic job will be
                # ignored by future runs of this script
                print('canceling...')
                db.update_by_id('job_states', topic['job_states_id'], {'message': f'canceled: {topic["message"]}'})
                break
            elif action == 'i':
                # ignore this topic for this run only
                print('ignoring...')
                break
            elif action == 'f':
                jobs = db.query(
                    """
                    select * 
                        from job_states 
                        where class like '%Topic%' and args->>'topics_id' = %(a)s::text 
                        order by job_states_id
                    """,
                    {'a': topics_id}).hashes()
                [print(f"{job['last_updated']} {job['class']}\n{job['message']}\n****") for job in jobs]
                # print out the whole error message and then reprompt for an action
                #print(topic['message'])

main()
