"""
topic spider implementation

this package implements the parent spider job, which runs the initial seed queries and then queues and
manages the children jobs to fetch and extract links, to fetch social media data, and so on.

the topic mining process is described in doc/topic_mining.markdown.
"""

import datetime
from dateutil.relativedelta import relativedelta
import random
from time import sleep, time
from typing import Optional, Callable

from mediawords.db import DatabaseHandler
from mediawords.db.locks import get_session_lock, release_session_lock
import mediawords.dbi.stories
from mediawords.job import JobBroker, StatefulJobBroker, StateUpdater
import mediawords.solr
import mediawords.solr.query
import mediawords.util.sql
import topics_base.alert
import topics_base.stories
import topics_mine.fetch_topic_posts

from mediawords.util.log import create_logger
log = create_logger(__name__)

# lock_type to send to get_session_lock
LOCK_TYPE = 'MediaWords::Job::TM::MineTopic'

# total time to wait for fetching of social media metrics
MAX_SOCIAL_MEDIA_FETCH_TIME = (60 * 60 * 24)

# add new links in chunks of this size
ADD_NEW_LINKS_CHUNK_SIZE = 10000

# extract story links in chunks of this size
EXTRACT_STORY_LINKS_CHUNK_SIZE = 1000

# query this many topic_links at a time to spider
SPIDER_LINKS_CHUNK_SIZE = 100000

# raise McTopicMineError if the error rate for link fetch or link extract jobs is greater than this
MAX_JOB_ERROR_RATE = 0.02

# timeout when polling for jobs to finish
JOB_POLL_TIMEOUT = 600

# number of seconds to wait when polling for jobs to finish
JOB_POLL_WAIT = 5

# if more than this many seed urls are imported, dedup stories before as well as after spidering
MIN_SEED_IMPORT_FOR_PREDUP_STORIES = 50000

# how many link extraction jobs per 1000 can we ignore if they hang
MAX_LINK_EXTRACTION_TIMEOUT = 10

# how long to wait to timeout link extraction
LINK_EXTRACTION_POLL_TIMEOUT = 600

# domain timeout for link fetching
DOMAIN_TIMEOUT = None

class McTopicMineError(Exception):
    pass


def update_topic_state(db: DatabaseHandler, state_updater: Optional[StateUpdater], message: str) -> None:
    """ update topics.state in the database"""

    log.info("update topic state: message")

    if not state_updater:
        # Shouldn't happen but let's just test it here
        log.warning("State updater is unset.")
        return

    state_updater.update_job_state_message(db, message)


def story_within_topic_date_range(topic: dict, story:dict) -> bool:
    """return True if the publish date of the story is within 7 days of the topic date range or if it is undateable"""

    if not story['publish_date']:
        return True

    story_date = (story['publish_date'])[0:10]

    start_date = topic['start_date']
    start_date = mediawords.util.sql.increment_day(start_date, -7)
    start_date = start_date[0:10]

    end_date = topic['end_date']
    end_date = mediawords.util.sql.increment_day(end_date, 7)
    end_date = end_date[0:10]

    return story_date >= start_date and story_date <= end_date


def generate_topic_links(db: DatabaseHandler, topic: dict, stories: list):
    """submit jobs to extract links from the stories and then poll to wait for the stories to be processed"""
    log.info(f"generate topic links: {len(stories)}")

    if len(stories) < 1:
        return

    topic_links = []

    if topic['platform'] != 'web':
        log.info("skip link generation for non web topic")
        return

    stories_ids_table = db.get_temporary_ids_table([s['stories_id'] for s in stories])

    db.query(
        f"""
        update topic_stories set link_mined = 'f'
            where
                stories_id in (select id from {stories_ids_table}) and
                topics_id = %(a)s and
                link_mined = 't'
        """,
        {'a': topic['topics_id']})

    queued_stories_ids = []
    for story in stories:
        if not story_within_topic_date_range(topic, story):
            continue

        queued_stories_ids.append(story['stories_id'])

        JobBroker(queue_name='MediaWords::Job::TM::ExtractStoryLinks').add_to_queue(
                stories_id=story['stories_id'], 
                topics_id=topic['topics_id'])

        log.debug(f"queued link extraction for story {story['title']} {story['url']}.")

    log.info(f"waiting for {len(queued_stories_ids)} link extraction jobs to finish")

    queued_ids_table = db.get_temporary_ids_table(queued_stories_ids)

    # poll every JOB_POLL_WAIT seconds waiting for the jobs to complete.  raise McTopicMineError if the number
    # of stories left to process has not shrunk for EXTRACTION_POLL_TIMEOUT seconds.
    prev_num_queued_stories = len(stories)
    last_change_time = time()
    while True:
        queued_stories = db.query(
            f"""
            select stories_id from topic_stories
                where stories_id in (select id from {queued_ids_table}) and topics_id = %(a)s and link_mined = 'f'
            """,
            {'a': topic['topics_id']}).flat()

        num_queued_stories = len(queued_stories)

        if not num_queued_stories:
            break

        if num_queued_stories != prev_num_queued_stories:
            last_change_time = time()

        if (time() - last_change_time) > LINK_EXTRACTION_POLL_TIMEOUT:
            ids_list = ','.join(queued_stories)
            if num_queued_stories > MAX_LINK_EXTRACTION_TIMEOUT:
                raise McTopicMineError(f"Timed out waiting for story link extraction ({ids_list}).")

            db.query(
                """
                update topic_stories set link_mine_error = 'time out'
                    where stories_id = any(%(b)s)  and topics_id = %(a)s
                """,
                {'a': topic['topics_id'], 'b': queued_stories})

            break

        log.info(f"{num_queued_stories} stories left in link extraction pool....")

        prev_num_queued_stories = num_queued_stories
        sleep(JOB_POLL_WAIT)

    db.query(
        f"""
        update topic_stories set link_mined = 't'
            where stories_id in (select id from {stories_ids_table}) and topics_id = %(a)s and link_mined = 'f'
        """,
        {'a': topic['topics_id']})

    db.query(f"drop table {stories_ids_table}")


def die_if_max_stories_exceeded(db, topic):
    """
    raise an MCTopicMineMaxStoriesException topic_stories > topics.max_stories.
    """
    num_topic_stories = db.query(
        "select count(*) from topic_stories where topics_id = %(a)s",
        {'a': topic['topics_id']}).flat()[0]

    if num_topic_stories > topic['max_stories']:
        raise McTopicMineError(f"{num_topic_stories} stories > {topic['max_stories']}")


def queue_topic_fetch_url(tfu:dict, domainm_timeout:Optional[int] = None):
    """ add the topic_fetch_url to the fetch_link job queue.  try repeatedly on failure."""

    JobBroker(queue_name='MediaWords::Job::TM::FetchLink').add_to_queue(
            topic_fetch_urls_id=tfu['topic_fetch_urls_id'],
            domain_timeout=DOMAIN_TIMEOUT)


def create_and_queue_topic_fetch_urls(db:DatabaseHandler, topic:dict, fetch_links:list) -> list:
    """
    create topic_fetch_urls rows correpsonding to the links and queue a FetchLink job for each.

    return the tfu rows.
    """
    tfus = []
    for link in fetch_links:
        topic_links_id = link.get('topic_links_id', None)
        assume_match = link.get('assume_match', False)

        # if this link has an associated topics_link row but that row has been deleted, ignore it.
        # this can be used to delete spam urls from topic_links during the spidering process.
        if topic_links_id and not db.find_by_id('topic_links', topic_links_id):
            continue

        tfu = {
            'topics_id': topic['topics_id'],
            'url': link['url'],
            'state': 'pending',
            'assume_match': assume_match,
            'topic_links_id': topic_links_id}
        tfu = db.create('topic_fetch_urls', tfu)

        tfus.append(tfu)

        queue_topic_fetch_url(tfu)

    return tfus


def _fetch_twitter_urls(db: DatabaseHandler, topic: dict, tfu_ids: list) -> None:
    """
    Send topic_fetch_urls to fetch_twitter_urls queue and wait for the jobs to complete.
    """
    # we run into quota limitations sometimes and need a longer timeout
    twitter_poll_timeout = JOB_POLL_TIMEOUT * 5

    twitter_tfu_ids = db.query(
        """
        select topic_fetch_urls_id
            from topic_fetch_urls tfu
            where
                tfu.state = 'tweet pending' and
                tfu.topic_fetch_urls_id = any(%(a)s)
        """, {'a': tfu_ids}).flat()

    if not twitter_tfu_ids:
        return

    tfu_ids_table = db.get_temporary_ids_table(twitter_tfu_ids)

    JobBroker(queue_name='MediaWords::Job::TM::FetchTwitterUrls').add_to_queue(
        topic_fetch_urls_ids=twitter_tfu_ids)

    log.info(f"waiting for fetch twitter urls job for {len(twitter_tfu_ids)} urls")

    # poll every sleep_time seconds waiting for the jobs to complete.
    # raise McTopicMineError if the number of stories left to process
    # has not shrunk for large_timeout seconds.  warn but continue if the number of stories left to process
    # is only 5% of the total and short_timeout has passed (this is to make the topic not hang entirely because
    # of one link extractor job error).
    prev_num_queued_urls = len(twitter_tfu_ids)
    last_change_time = time()
    while True:
        queued_tfus = db.query(
            f"""
            select tfu.*
                from topic_fetch_urls tfu
                    join {tfu_ids_table} ids on (tfu.topic_fetch_urls_id = ids.id)
                where
                    state in ('tweet pending')
            """).hashes()

        num_queued_urls = len(queued_tfus)

        if num_queued_urls == 0:
            break

        if num_queued_urls != prev_num_queued_urls:
            last_change_time = time()

        if (time() - last_change_time) > twitter_poll_timeout:
            raise McTopicMineError(f"Timed out waiting for twitter fetching {queued_tfus}")

        log.info(f"{num_queued_urls} twitter urls left to fetch ...")

        prev_num_queued_urls = num_queued_urls
        sleep(JOB_POLL_WAIT)


def list_pending_urls(pending_urls: list) -> str:
    """list a sample of the pending urls for fetching"""
    num_pending_urls = len(pending_urls)

    num_printed_urls = min(num_pending_urls, 3)

    random.shuffle(pending_urls)
    urls = pending_urls[0:num_printed_urls]

    return "\n".join([f"pending url: {url['url']} [{url['state']}: {url['fetch_date']}]" for url in urls])


def fetch_links(db: DatabaseHandler, topic: dict, fetch_links: dict) -> None:
    """
    fetch the given links by creating topic_fetch_urls rows and sending them to the FetchLink queue
    for processing.  wait for the queue to complete and return the resulting topic_fetch_urls.
    """

    log.info("fetch_links: queue links")
    tfus = create_and_queue_topic_fetch_urls(db, topic, fetch_links)
    num_queued_links = len(fetch_links)

    log.info(f"waiting for fetch link queue: {num_queued_links} queued")

    tfu_ids = [tfu['topic_fetch_urls_id'] for tfu in tfus]

    requeues = 0
    max_requeues = 1
    max_requeue_jobs = 100
    requeue_timeout = 30
    instant_requeued = 0

    # once the pool is this small, just requeue everything with a 0 per site throttle
    instant_queue_size = 25

    # how many times to requeues everything if there is no change for JOB_POLL_TIMEOUT seconds
    full_requeues = 0
    max_full_requeues = 1

    last_pending_change = time()
    last_num_pending_urls = 0
    while True:
        pending_urls = db.query(
            """
            select *, coalesce(fetch_date::text, 'null') fetch_date
                from topic_fetch_urls
                where
                    topic_fetch_urls_id = any(%(a)s) and
                    state in ('pending', 'requeued')
            """,
            {'a': tfu_ids}).hashes()

        pending_url_ids = [u['topic_fetch_urls_id'] for u in pending_urls]

        num_pending_urls = len(pending_url_ids)

        log.info(f"waiting for fetch link queue: {num_pending_urls} links remaining ...")
        log.info(list_pending_urls(pending_urls))

        if num_pending_urls < 1:
            break

        # if we only have a handful of job left, requeue them all once with a 0 domain throttle
        if not instant_requeued and num_pending_urls <= instant_queue_size:
            instant_requeued = 1
            [queue_topic_fetch_url(db.require_by_id('topic_fetch_urls', id), 0) for id in pending_url_ids]
            sleep(JOB_POLL_WAIT)
            continue

        time_since_change = time() - last_pending_change

        # for some reason, the fetch_link queue is occasionally losing a small number of jobs.
        if (time_since_change > requeue_timeout and
                requeues < max_requeues and
                num_pending_urls < max_requeue_jobs):
            log.info(f"requeueing fetch_link {num_pending_urls} jobs ... [{requeue} requeues]")

            # requeue with a domain_timeout of 0 so that requeued urls can ignore throttling
            [queue_topic_fetch_url(db.require_by_id('topic_fetch_urls', id), 0) for id in pending_url_ids]
            requeues += 1
            last_pending_change = time()

        if time_since_change > JOB_POLL_TIMEOUT:
            if num_pending_urls > max_requeue_jobs:
                raise McTopicMineError("Timed out waiting for fetch link queue")
            elif full_requeues < max_full_requeues:
                [queue_topic_fetch_url(db.require_by_id('topic_fetch_urls', id)) for id in pending_url_ids]
                full_requeues += 1
                last_pending_change = time()
            else:
                for id in pending_url_ids:
                    db.update_by_id('topic_fetch_urls', id, {'state': 'python error', 'message': 'timed out'})

                log.info(f"timed out {len(pending_url_ids)} urls")

        if num_pending_urls < last_num_pending_urls:
            last_pending_change = time()

        last_num_pending_urls = num_pending_urls

        sleep(JOB_POLL_WAIT)

    _fetch_twitter_urls(db, topic, tfu_ids)

    log.info("fetch_links: update topic seed urls")
    db.query(
        """
        update topic_seed_urls tsu
            set stories_id = tfu.stories_id, processed = 't'
            from topic_fetch_urls tfu
            where
                tfu.url = tsu.url and
                tfu.stories_id is not null and
                tfu.topic_fetch_urls_id = any(%(a)s) and
                tfu.topics_id = tsu.topics_id
        """,
        {'a': tfu_ids})

    completed_tfus = db.query(
        "select * from topic_fetch_urls where topic_fetch_urls_id = any(%(a)s)",
        {'a':  tfu_ids}).hashes()

    log.info("completed fetch link queue")

    return completed_tfus


def add_new_links_chunk(db, topic, iteration, new_links):
    """
    download any unmatched link in new_links, add it as a story, extract it, add any links to the topic_links list.

    each hash within new_links can either be a topic_links hash or simply a hash with a {url} field.  if
    the link is a topic_links hash, the topic_link will be updated in the database to point ref_stories_id
    to the new link story.  For each link, set the {story} field to the story found or created for the link.
    """
    die_if_max_stories_exceeded(db, topic)

    log.info("add_new_links_chunk: fetch_links")
    topic_fetch_urls = fetch_links(db, topic, new_links)

    log.info("add_new_links_chunk: mark topic links spidered")
    link_ids = [l['topic_links_id'] for l in new_links if 'topic_links_id' in l]

    db.query(
        "update topic_links set link_spidered = 't' where topic_links_id = any(%(a)s)",
        {'a': link_ids})


def save_metrics(db, topic, iteration, num_links, elapsed_time):
    """save a row in the topic_spider_metrics table to track performance of spider"""

    topic_spider_metric = {
        'topics_id': topic['topics_id'],
        'iteration': iteration,
        'links_processed': num_links,
        'elapsed_time': elapsed_time
    }

    db.create('topic_spider_metrics', topic_spider_metric)


def add_new_links(db:DatabaseHandler, topic:dict, iteration:int, new_links:list, state_updater:Callable) -> None:
    """call add_new_links in chunks of ADD_NEW_LINKS_CHUNK_SIZE"""
    log.info("add new links")

    if not new_links:
        return

    spider_progress = get_spider_progress_description(db, topic, iteration, len(new_links))

    num_links = len(new_links)

    i = 0
    while i < num_links:
        start_time = time()

        update_topic_state(db, state_updater, f"spider_progress iteration links: {i} / {num_links}")

        chunk_links = new_links[i:i + ADD_NEW_LINKS_CHUNK_SIZE]
        add_new_links_chunk(db, topic, iteration, chunk_links)

        elapsed_time = time() - start_time
        save_metrics(db, topic, iteration, len(chunk_links), elapsed_time)

        i += ADD_NEW_LINKS_CHUNK_SIZE

    mine_topic_stories(db, topic)


def get_new_links(db: DatabaseHandler, iteration: int, topics_id: int) -> list:
    """query the database for new links from stories below the given iteration."""

    new_links = db.query(
        """
        select tl.*
            from
                topic_links tl
                join topic_stories ts using ( topics_id )
            where
                tl.link_spidered = 'f' and
                tl.stories_id = ts.stories_id and
                (ts.iteration <= %(a)s or ts.iteration = 1000) and
                ts.topics_id = %(b)s

            limit %(c)s
        """,
        {'a': iteration, 'b': topics_id, 'c': SPIDER_LINKS_CHUNK_SIZE}).hashes()

    return new_links


def spider_new_links(db, topic, iteration, state_updater):
    """call add_new_links on topic_links for which link_spidered is false."""

    while True:
        log.info("querying new links ...")

        db.query("drop table if exists _new_links")

        num_new_links = db.query(
            """
            create temporary table _new_links as 
                select tl.* 
                    from topic_links tl, topic_stories ts
                    where
                        tl.link_spidered = 'f' and
                        tl.stories_id = ts.stories_id and
                        (ts.iteration <= %(a)s or ts.iteration = 1000) and
                        ts.topics_id = %(b)s and
                        tl.topics_id = %(b)s 
                    order by random()
            """,
            {'a': iteration, 'b': topic['topics_id']}).rows()

        db.query("create index _new_links_tl on _new_links (topic_links_id)")

        if num_new_links < 1:
            break

        log.info(f"found {num_new_links} new links")

        while True:
            new_links = db.query("select * from _new_links limit %(a)s", {'a': SPIDER_LINKS_CHUNK_SIZE}).hashes()
            if not new_links:
                break

            tl_ids = [n['topic_links_id'] for n in new_links]
            db.query("delete from _new_links where topic_links_id = any(%(a)s)", {'a': tl_ids})
            add_new_links(db, topic, iteration, new_links, state_updater)

def get_spider_progress_description(db, topic, iteration, total_links):
    """get short text description of spidering progress"""

    log.info("get spider progress description")

    topics_id = topic['topics_id']

    total_stories = db.query(
        "select count(*) from topic_stories where topics_id = %(a)s",
        {'a': topics_id}).flat()[0]

    stories_last_iteration = db.query(
        "select count(*) from topic_stories where topics_id = %(a)s and iteration = %(b)s - 1",
        {'a': topics_id, 'b': iteration}).flat()[0]

    queued_links = db.query(
        "select count(*) from topic_links where topics_id = %(a)s and not link_spidered",
        {'a': topics_id}).flat()[0]

    return (
        f"spidering iteration: {iteration} stories last iteration / total: "
        f"{stories_last_iteration} / {total_stories} links queued: {queued_links} iteration links: {total_links}"
    )


def run_spider(db, topic, state_updater):
    """run the spider over any new links, for num_iterations iterations"""
    log.info("run spider")

    # before we run the spider over links, we need to make sure links have been generated for all existing stories
    mine_topic_stories(db, topic)

    iterations = topic['max_iterations']
    [spider_new_links(db, topic, iterations, state_updater) for i in range(iterations)]


def mine_topic_stories(db, topic):
    """ mine for links any stories in topic_stories for this topic that have not already been mined"""
    log.info("mine topic stories")

    # skip for non-web topic, because the below query grows very large without ever mining links
    if topic['platform'] != 'web':
        log.info("skip link generation for non-web topic")
        return

    # chunk the story extractions so that one big topic does not take over the entire queue
    i = 0
    while True:
        i += EXTRACT_STORY_LINKS_CHUNK_SIZE
        log.info("mine topic stories: chunked i ...")
        stories = db.query(
            """
            select s.*, ts.link_mined, ts.redirect_url
                from snap.live_stories s
                    join topic_stories ts on (s.stories_id = ts.stories_id and s.topics_id = ts.topics_id)
                where
                    ts.link_mined = false and
                    ts.topics_id = %(a)s
                limit %(b)s
            """, {'a': topic['topics_id'], 'b': EXTRACT_STORY_LINKS_CHUNK_SIZE}).hashes()

        num_stories = len(stories)

        generate_topic_links(db, topic, stories)

        if num_stories < EXTRACT_STORY_LINKS_CHUNK_SIZE:
            break


def import_seed_urls(db, topic, state_updater):
    """ import all topic_seed_urls that have not already been processed

    return 1 if new stories were added to the topic and 0 if not
    """
    log.info("import seed urls")

    topics_id = topic['topics_id']

    # take care of any seed urls with urls that we have already processed for this topic
    db.query(
        """
        update topic_seed_urls a set stories_id = b.stories_id, processed = 't'
            from topic_seed_urls b
            where a.url = b.url and
                a.topics_id = %(a)s and b.topics_id = a.topics_id and
                a.stories_id is null and b.stories_id is not null
        """,
        {'a': topics_id})

    # randomly shuffle this query so that we don't block the extractor pool by throwing it all
    # stories from a single media_id at once
    seed_urls = db.query(
        "select * from topic_seed_urls where topics_id = %(a)s and processed = 'f' order by random()",
        {'a': topics_id}).hashes()

    if not seed_urls:
        return 0

    # process these in chunks in case we have to start over so that we don't have to redo the whole batch
    num_urls = len(seed_urls)
    i = 0
    while i < num_urls:
        start_time = time()

        update_topic_state(db, state_updater, f"importing seed urls: {i} / {num_urls}")

        chunk_urls = seed_urls[i:i + ADD_NEW_LINKS_CHUNK_SIZE]

        # verify that the seed urls exist and not processed, in case we have mucked with them while spidering
        url_ids = [u['topic_seed_urls_id'] for u in chunk_urls]
        seed_urls_chunk = db.query(
            "select * from topic_seed_urls where topic_seed_urls_id = any(%(a)s) and not processed",
            {'a': url_ids}).hashes()

        add_new_links_chunk(db, topic, 0, seed_urls_chunk)

        url_ids = [u['topic_seed_urls_id'] for u in seed_urls_chunk]

        # update topic_seed_urls that were actually fetched
        db.query(
            """
            update topic_seed_urls tsu
                set stories_id = tfu.stories_id
                from topic_fetch_urls tfu
                where
                    tsu.topics_id = tfu.topics_id and
                    md5(tsu.url) = md5(tfu.url) and
                    tsu.topic_seed_urls_id = any(%(a)s)
            """,
            {'a': url_ids})

        # now update the topic_seed_urls that were matched
        db.query(
            """
            update topic_seed_urls tsu
                set processed = 't'
                where
                    tsu.topic_seed_urls_id = any(%(a)s) and
                    processed = 'f'
            """,
            {'a': url_ids})

        elapsed_time = time() - start_time
        save_metrics(db, topic, 1, len(chunk_urls), elapsed_time)

        i += ADD_NEW_LINKS_CHUNK_SIZE

    # cleanup any topic_seed_urls pointing to a merged story
    db.query(
        """
        UPDATE topic_seed_urls AS tsu
        SET stories_id = tms.target_stories_id, processed = 't'
        FROM topic_merged_stories_map AS tms,
             topic_stories ts
        WHERE tsu.stories_id = tms.source_stories_id
          AND ts.stories_id = tms.target_stories_id
          AND tsu.topics_id = ts.topics_id
          AND ts.topics_id = %(a)s
        """,
        {'a': topic['topics_id']})

    return len(seed_urls)


def insert_topic_seed_urls(db, topic_seed_urls):
    """ insert a list of topic seed urls"""
    log.info(f"inserting {len(topic_seed_urls)} topic seed urls ...")

    for tsu in topic_seed_urls:
        insert_tsu = {f: tsu[f] for f in ('stories_id', 'url', 'topics_id', 'assume_match')}
        db.create('topic_seed_urls', insert_tsu)


def _import_month_within_respider_date(topic, month_offset):
    """ return True if the given month offset is within the dates that should be respidered.

    always return True if there are no respider dates
    """

    start_date = topic['respider_start_date'] or ''
    end_date = topic['respider_end_date'] or ''

    if not (topic['respider_stories'] and (start_date or end_date)):
        return True

    month_date = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d') + relativedelta(months=month_offset)
    log.warning(month_date)

    if end_date:
        end_date = datetime.datetime.strptime(end_date, '%Y-%m-%d') + relativedelta(months=-1)
        log.warning(f"end_date: {end_date}")
        if month_date > end_date:
            return True

    if start_date:
        start_date = datetime.datetime.strptime(start_date, '%Y-%m-%d')
        log.warning(f"start_date: {start_date}")
        if month_date < start_date:
            return True

    return False


def _search_for_stories_urls(db, params):
    """Call search_solr_for_stories_ids() and then query postgres for the stories urls.

    Return dicts with stories_id and url fields."""

    stories_ids = mediawords.solr.search_solr_for_stories_ids(db, params)

    stories = db.query("select stories_id,url from stories where stories_id = any(%(a)s)", {'a': stories_ids}).hashes()

    return stories


def import_solr_seed_query_month(db, topic, month_offset):
    """ import a single month of the solr seed query.  we do this to avoid giant queries that timeout in solr.

    return True if the month_offset is valid for the topic."""
    if not topic['platform'] == 'web':
        return False

    solr_query = mediawords.solr.query.get_full_solr_query_for_topic(db=db, topic=topic, month_offset=month_offset)

    # this should return undef once the month_offset gets too big
    if not solr_query:
        return False

    if not _import_month_within_respider_date(topic, month_offset):
        return True

    max_stories = topic['max_stories']

    # if solr maxes out on returned stories, it returns a few documents less than the rows= parameter, so we
    # assume that we hit the solr max if we are within 5% of the max stories
    max_returned_stories = max_stories * 0.95

    log.info(f"import solr seed query month offset {month_offset}")
    solr_query['rows'] = max_stories

    stories = _search_for_stories_urls(db, solr_query)

    if len(stories) > max_returned_stories:
        raise McTopicMineError(f"solr_seed_query returned more than {max_returned_stories} stories")

    log.info(f"adding {len(stories)} stories to topic_seed_urls")

    topic_seed_urls = []
    for story in stories:
        tsu = {
            'topics_id': topic['topics_id'],
            'url': story['url'],
            'stories_id': story['stories_id'],
            'assume_match': 'f'}
        topic_seed_urls.append(tsu)

    insert_topic_seed_urls(db, topic_seed_urls)

    return True


def import_solr_seed_query(db, topic):
    """ import stories into topic_seed_urls from solr by running topic['solr_seed_query'] against solr.

    if the solr query has already been imported, do nothing."""

    log.info("import solr seed query")

    if topic['solr_seed_query_run']:
        return

    month_offset = 0
    while import_solr_seed_query_month(db, topic, month_offset):
        month_offset += 1
        pass

    db.query("update topics set solr_seed_query_run = 't' where topics_id = %(a)s", {'a': topic['topics_id']})


def all_facebook_data_fetched(db, topic):
    """ return True if there are no stories without facebook data"""

    null_facebook_story = db.query(
        """
        select 1
            from topic_stories cs
                left join story_statistics ss on (cs.stories_id = ss.stories_id)
            where
                cs.topics_id = %(a)s and
                ss.facebook_api_error is null and
                (
                    ss.stories_id is null or
                    ss.facebook_share_count is null or
                    ss.facebook_comment_count is null or
                    ss.facebook_api_collect_date is null
               )
            limit 1
        """,
        {'a': topic['topics_id']}).hash()

    return null_facebook_story is None


def _add_topic_stories_to_facebook_queue(db, topic):
    """ add all topic stories without facebook data to the queue"""
    topics_id = topic['topics_id']

    stories = db.query(
        """
        SELECT ss.*, cs.stories_id
            FROM topic_stories cs
                left join story_statistics ss on (cs.stories_id = ss.stories_id)
            WHERE cs.topics_id = %(a)s
            ORDER BY cs.stories_id
        """,
        {'a': topics_id}).hashes()

    if not stories:
        log.debug("No stories found for topic 'topic['name']'")

    for ss in stories:
        if (ss['facebook_api_error'] or
                ss['facebook_api_collect_date'] is None or
                ss['facebook_share_count'] is None or
                ss['facebook_comment_count'] is None):
            log.debug(f"Adding job for story {ss['stories_id']}")
            args = {'stories_id': ss['stories_id']}

            JobBroker(queue_name='MediaWords::Job::Facebook::FetchStoryStats').add_to_queue(
                stories_id=ss['stories_id'])


def fetch_social_media_data(db, topic):
    """ send jobs to fetch facebook data for all stories that don't yet have it"""

    log.info("fetch social media data")

    cid = topic['topics_id']

    _add_topic_stories_to_facebook_queue(db, topic)

    poll_wait = 30
    retries = int(MAX_SOCIAL_MEDIA_FETCH_TIME / poll_wait) + 1

    for i in range(retries):
        if all_facebook_data_fetched(db, topic):
            return
        sleep(poll_wait)

    raise McTopicMineError("Timed out waiting for social media data")


def check_job_error_rate(db, topic):
    """ raise an error if error rate for link extraction or link fetching is too high"""

    log.info("check job error rate")

    fetch_stats = db.query(
        """
        select count(*) num, (state = 'python error') as error
            from topic_fetch_urls
                where topics_id = %(a)s
                group by (state = 'python error')
        """,
        {'a': topic['topics_id']}).hashes()

    num_fetch_errors = sum([s['num'] for s in fetch_stats if s['error']])
    num_fetch_successes = sum([s['num'] for s in fetch_stats if not s['error']])

    fetch_error_rate = num_fetch_errors / (num_fetch_errors + num_fetch_successes + 1)

    log.info(f"Fetch error rate: {fetch_error_rate} ({num_fetch_errors} / {num_fetch_successes})")

    if fetch_error_rate > MAX_JOB_ERROR_RATE:
        raise McTopicMineError(f"Fetch error rate of {fetch_error_rate} is greater than {MAX_JOB_ERROR_RATE}")

    link_stats = db.query(
        """
        select count(*) num, (length( link_mine_error) > 0) as error
            from topic_stories
                where topics_id = %(a)s
                group by (length(link_mine_error) > 0)
        """,
        {'a': topic['topics_id']}).hashes()

    num_link_errors = sum([s['num'] for s in link_stats if s['error']])
    num_link_successes = sum([s['num'] for s in link_stats if not s['error']])

    link_error_rate = num_link_errors / (num_link_errors + num_link_successes + 1)

    log.info(f"Link error rate: {link_error_rate} ({num_link_errors} / {num_link_successes})")

    if link_error_rate > MAX_JOB_ERROR_RATE:
        raise McTopicMineError(f"link error rate of {link_error_rate} is greater than {MAX_JOB_ERROR_RATE}")


def import_urls_from_seed_queries(db, topic, state_updater):
    """ import urls from seed query """

    topic_seed_queries = db.query(
        "select * from topic_seed_queries where topics_id = %(a)s",
        {'a': topic['topics_id']}).hashes()

    log.debug("import seed urls from solr")
    update_topic_state(db, state_updater, "importing solr seed query")
    import_solr_seed_query(db, topic)

    for tsq in topic_seed_queries:
        tsq_dump = tsq['topic_seed_queries_id']
        fetcher = topics_mine.fetch_topic_posts.get_post_fetcher(tsq)
        if not fetcher:
            raise McTopicMineError(f"unable to import seed urls for platform/source of seed query: {tsq_dump}")

        log.debug(f"import seed urls from fetch_topic_posts:\n{tsq_dump}")
        topics_mine.fetch_topic_posts.fetch_topic_posts(db, tsq)

    db.query(
        """
        insert into topic_seed_urls
            (url, topics_id, assume_match, source, topic_seed_queries_id, topic_post_urls_id)
            select distinct
                    tpu.url,
                    tsq.topics_id,
                    false,
                    'topic_seed_queries',
                    tsq.topic_seed_queries_id,
                    tpu.topic_post_urls_id
                from
                    topic_post_urls tpu
                    join topic_posts tp using (topic_posts_id)
                    join topic_post_days tpd using (topic_post_days_id)
                    join topic_seed_queries tsq using (topic_seed_queries_id)
                where
                    tsq.topics_id = %(a)s
                on conflict (topic_post_urls_id) do nothing
        """,
        {'a': topic['topics_id']})


def set_stories_respidering(db, topic, snapshots_id):
    """ if the query or dates have changed, set topic_stories.link_mined to false so they will be respidered"""

    if not topic['respider_stories']:
        return

    respider_start_date = topic['respider_start_date']
    respider_end_date = topic['respider_end_date']

    if not respider_start_date and not respider_end_date:
        db.query("update topic_stories set link_mined = 'f' where topics_id = %(a)s", {'a': topic['topics_id']})
        return

    if respider_start_date:
        db.query(
            """
            update topic_stories ts set link_mined = 'f'
                from stories s
                where
                    ts.stories_id = s.stories_id and
                    s.publish_date >= %(b)s and
                    s.publish_date <= %(a)s and
                    ts.topics_id = %(c)s
            """,
            {'a': respider_start_date, 'b': topic['start_date'], 'c': topic['topics_id']})

        if snapshots_id:
            db.update_by_id('snapshots', snapshots_id, {'start_date': topic['start_date']})
            db.query(
                """
                update timespans set archive_snapshots_id = snapshots_id, snapshots_id = null
                where snapshots_id = %(a)s and start_date < %(b)s
                """,
                {'a': snapshots_id, 'b': respider_start_date})

    if respider_end_date:
        db.query(
            """
            update topic_stories ts set link_mined = 'f'
                from stories s
                where
                    ts.stories_id = s.stories_id and
                    s.publish_date >= %(a)s and
                    s.publish_date <= %(b)s and
                    ts.topics_id = %(c)s
            """,
            {'a': respider_end_date, 'b': topic['end_date'], 'c': topic['topics_id']})

        if snapshots_id:
            db.update_by_id('snapshots', snapshots_id, {'end_date': topic['end_date']})
            db.query(
                """
                update timespans set archive_snapshots_id = snapshots_id, snapshots_id = null
                    where snapshots_id = %(a)s and end_date > %(b)s
                """,
                {'a': snapshots_id, 'b': respider_end_date})

    db.update_by_id(
        'topics',
        topic['topics_id'],
        {'respider_stories': 'f', 'respider_start_date': None, 'respider_end_date': None})


def do_mine_topic(db, topic, options):
    """ mine the given topic for links and to recursively discover new stories on the web.

    options:
      import_only - only run import_seed_urls and import_solr_seed and exit
      skip_post_processing - skip social media fetching and snapshotting
      snapshots_id - associate topic with the given existing snapshot
      state_updater - object that implements mediawords.job.StateUpdater
    """
    [options.setdefault(f, None) for f in 'state_updater import_only skip_post_processing snapshots_id'.split()]

    state_updater = options['state_updater']

    update_topic_state(db, state_updater, "importing seed urls")
    import_urls_from_seed_queries(db, topic, state_updater)

    update_topic_state(db, state_updater, "setting stories respidering...")
    set_stories_respidering(db, topic, options['snapshots_id'])

    # this may put entires into topic_seed_urls, so run it before import_seed_urls.
    # something is breaking trying to call this perl.  commenting out for time being since we only need
    # this when we very rarely change the foreign_rss_links field of a media source - hal
    # update_topic_state(db, state_updater, "merging foreign rss stories")
    # topics_base.stories.merge_foreign_rss_stories(db, topic)

    update_topic_state(db, state_updater, "importing seed urls")
    if import_seed_urls(db, topic, state_updater) > MIN_SEED_IMPORT_FOR_PREDUP_STORIES:
        # merge dup stories before as well as after spidering to avoid extra spidering work
        update_topic_state(db, state_updater, "merging duplicate stories")
        topics_base.stories.find_and_merge_dup_stories(db, topic)

    if not options.get('import_only', False):
        update_topic_state(db, state_updater, "running spider")
        run_spider(db, topic, state_updater)

        check_job_error_rate(db, topic)

        # merge dup media and stories again to catch dups from spidering
        update_topic_state(db, state_updater, "merging duplicate stories")
        topics_base.stories.find_and_merge_dup_stories(db, topic)

        update_topic_state(db, state_updater, "merging duplicate media stories")
        topics_base.stories.merge_dup_media_stories(db, topic)

        if not options.get('skip_post_processing', False):
            update_topic_state(db, state_updater, "fetching social media data")
            fetch_social_media_data(db, topic)

            update_topic_state(db, state_updater, "snapshotting")
            snapshot_args = {'topics_id': topic['topics_id'], 'snapshots_id': options['snapshots_id']}
            StatefulJobBroker(queue_name='MediaWords::Job::TM::SnapshotTopic').add_to_queue(snapshot_args)


def mine_topic(db, topic, **options):
    """ wrap do_mine_topic in try and handle errors and state"""

    # the topic spider can sit around for long periods doing solr queries, so we need to make sure the postgres
    # connection does not get timed out
    db.query("set idle_in_transaction_session_timeout = 0")

    if topic['state'] != 'running':
        topics_base.alert.send_topic_alert(db, topic, "started topic spidering")

    get_session_lock(db=db, lock_type=LOCK_TYPE, lock_id=topic['topics_id'])

    try:
        do_mine_topic(db, topic, options)
    except Exception as e:
        topics_base.alert.send_topic_alert(db, topic, "aborted topic spidering due to error")
        raise e

    release_session_lock(db=db, lock_type=LOCK_TYPE, lock_id=topic['topics_id'])


def run_worker_job(topics_id: int, snapshots_id: Optional[int] = None) -> None:
    """run a topics-mine worker job."""
    if isinstance(snapshots_id, bytes):
        snapshots_id = decode_object_from_bytes_if_needed(snapshots_id)
    if snapshots_id is not None:
        snapshots_id = int(snapshots_id)

    if isinstance(topics_id, bytes):
        topics_id = decode_object_from_bytes_if_needed(topics_id)
    if topics_id is not None:
        topics_id = int(topics_id)

    if not bool(topics_id):
        raise McTopicMineException("topics_id must be set")

    db = connect_to_db()

    topic = db.require_by_id('topics', topics_id)

    mine_topic(db=db, topic=topic, snapshots_id=snapshots_id)
