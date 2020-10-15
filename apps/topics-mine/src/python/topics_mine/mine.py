"""
topic spider implementation

this package implements the parent spider job, which runs the initial seed queries and then queues and
manages the children jobs to fetch and extract links, to fetch social media data, and so on.

the topic mining process is described in doc/topic_mining.markdown.

"""

from mediawords.util.log import create_logger
log = create_logger(__name__)

import mediawords.tm.alert
import mediawords.tm.fetchtopicposts
import mediawords.tm.stories
import mediawords.dbi.stories
import mediawords.dbi.stories.guessdate
import mediawords.job.broker
import mediawords.job.statefulbroker
import mediawords.solr
import mediawords.solr.query
import mediawords.util.sql

# total time to wait for fetching of social media metrics
MAX_SOCIAL_MEDIA_FETCH_TIME = (60 * 60 * 24)

# add new links in chunks of this size
ADD_NEW_LINKS_CHUNK_SIZE = 10_000

# extract story links in chunks of this size
EXTRACT_STORY_LINKS_CHUNK_SIZE = 1000

# query this many topic_links at a time to spider
SPIDER_LINKS_CHUNK_SIZE = 100_000

# die if the error rate for link fetch or link extract jobs is greater than this
MAX_JOB_ERROR_RATE = 0.02

# timeout when polling for jobs to finish
JOB_POLL_TIMEOUT = 300

# number of seconds to wait when polling for jobs to finish
JOB_POLL_WAIT = 5

# if more than this many seed urls are imported, dedup stories before as well as after spidering
MIN_SEED_IMPORT_FOR_PREDUP_STORIES = 50_000

# how many link extraction jobs per 1000 can we ignore if they hang
MAX_LINK_EXTRACTION_TIMEOUT = 10

# how long to wait to timeout link extraction
LINK_EXTRACTION_POLL_TIMEOUT = 60

# if mine_topic is run with the test_mode option, set this true and do not try to queue extractions
_test_mode = None

def update_topic_state(db, state_updater, message):
    """ update topics.state in the database"""

    log.info("update topic state: message")

    unless (state_updater) {
        # Shouldn't happen but let's just test it here
        ERROR "State updater is unset."
        return

    eval {
        state_updater.update_job_state_message(db, message)

    if $@:

        die "Error updating job state: $@"

# return true if the publish date of the story is within 7 days of the topic date range or if the
def story_within_topic_date_range(db, topic, story):
    """ story is undateable"""

    if not story['publish_date']:

        return 1

    story_date = substr(story['publish_date'], 0, 10)

    start_date = topic['start_date']
    start_date = mediawords.util.sql.increment_day(start_date, -7)
    start_date = substr(start_date, 0, 10)

    end_date = topic['end_date']
    end_date = mediawords.util.sql.increment_day(end_date, 7)
    end_date = substr(end_date, 0, 10)

    if (story_date ge start_date) and (story_date le end_date):

        return 1

    return mediawords.dbi.stories.guessdate.is_undateable(db, story)

# submit jobs to extract links from the given stories and then poll to wait for the stories to be processed within
def generate_topic_links(db, topic, stories):
    """ the jobs pool"""

    INFO "generate topic links: " . len(stories)

    topic_links = []

    if topic['platform'] ne 'web':

        log.info("skip link generation for non web topic")
        return

    stories_ids_table = db.get_temporary_ids_table([map { _['stories_id'] } stories])

    db.query(<<SQL, topic['topics_id'])
update topic_stories set link_mined = 'f'
        where
            stories_id in (select id from stories_ids_table) and
            topics_id = ? and
            link_mined = 't'
SQL

    queued_stories_ids = []
    for story in stories:

        if not story_within_topic_date_range(db, topic, story):
            next

        push(queued_stories_ids, story['stories_id'])

        mediawords.job.broker.new('mediawords.job.tm.extractstorylinks').add_to_queue(
            { 'stories_id': story['stories_id'], topics_id => topic['topics_id'] },   #
        )

        log.debug("queued link extraction for story story['title'] story['url'].")

    log.info("waiting for " . len( queued_stories_ids) . " link extraction jobs to finish" )

    queued_ids_table = db.get_temporary_ids_table(queued_stories_ids)

    # poll every JOB_POLL_WAIT seconds waiting for the jobs to complete.  die if the number of stories left to process
    # has not shrunk for EXTRACTION_POLL_TIMEOUT seconds. 
    prev_num_queued_stories = len(stories)
    last_change_time = time()
    while 1:

        queued_stories = db.query(<<SQL, topic['topics_id']).flat()
select stories_id from topic_stories
    where stories_id in (select id from queued_ids_table) and topics_id = ? and link_mined = 'f'
SQL

        num_queued_stories = len(queued_stories)

        if not num_queued_stories:

            last

        if num_queued_stories not = prev_num_queued_stories:

            last_change_time = time()
        if ( ( time() - last_change_time ) > LINK_EXTRACTION_POLL_TIMEOUT )

            ids_list = join(', ', queued_stories)
            if num_queued_stories > MAX_LINK_EXTRACTION_TIMEOUT:

                LOGDIE( "Timed out waiting for story link extraction (ids_list)." )

            db.query(<<SQL, topic['topics_id'])
update topic_stories set link_mine_error = 'time out' where stories_id in (ids_list) and topics_id = ?
SQL
            last

        log.info("num_queued_stories stories left in link extraction pool....")

        prev_num_queued_stories = num_queued_stories
        sleep(JOB_POLL_WAIT)

    db.query(<<SQL, topic['topics_id'])
update topic_stories set link_mined = 't'
    where stories_id in (select id from stories_ids_table) and topics_id = ? and link_mined = 'f'
SQL

    db.query("discard temp")

# die() with an appropriate error if topic_stories > topics.max_stories because this check is expensive and we don't
def die_if_max_stories_exceeded(db, topic):
    """ care if the topic goes over by a few thousand stories, we only actually run the check randmly 1/1000 of the time"""

    my (num_topic_stories) = db.query(<<SQL, topic['topics_id']).flat
select count(*) from topic_stories where topics_id = ?
SQL

    if num_topic_stories > topic['max_stories']:

        LOGDIE("topic has num_topic_stories stories, which exceeds topic max stories of topic['max_stories']")

def queue_topic_fetch_url(tfu, domain_timeout):
    """ add the topic_fetch_url to the fetch_link job queue.  try repeatedly on failure."""

    domain_timeout //= _test_mode ? 0 : undef

    mediawords.job.broker.new('mediawords.job.tm.fetchlink').add_to_queue(

            'topic_fetch_urls_id': tfu['topic_fetch_urls_id'],
            'domain_timeout': domain_timeout

    )

def create_and_queue_topic_fetch_urls(db, topic, fetch_links):
    """ create topic_fetch_urls rows correpsonding to the links and queue a FetchLink job for each.  return the tfu rows."""

    tfus = []
    for link in fetch_links:

        if (link['topic_links_id'] and not db.find_by_id( 'topic_links', link['topic_links_id']) )

            next

        tfu = db.create(
            'topic_fetch_urls',

                'topics_id': topic['topics_id'],
                'url': link['url'],
                'state': 'pending',
                'assume_match': mediawords.util.python.normalize_boolean_for_db(link['assume_match']),
                'topic_links_id': link['topic_links_id'],

        )
        push(tfus, tfu)

        queue_topic_fetch_url(tfu)

    return tfus

def _fetch_twitter_urls(db, topic, tfu_ids_list):

    twitter_tfu_ids = db.query(<<SQL).flat()
select topic_fetch_urls_id
    from topic_fetch_urls tfu
    where
        tfu.state = 'tweet pending' and
        tfu.topic_fetch_urls_id in (tfu_ids_list)
SQL

    if not len(twitter_tfu_ids) > 0:

        return

    tfu_ids_table = db.get_temporary_ids_table(twitter_tfu_ids)

    mediawords.job.broker.new('mediawords.job.tm.fetchtwitterurls').add_to_queue(
        { 'topic_fetch_urls_ids': twitter_tfu_ids }
    )

    log.info("waiting for fetch twitter urls job for " . len( twitter_tfu_ids) . " urls" )

    # poll every sleep_time seconds waiting for the jobs to complete.  die if the number of stories left to process
    # has not shrunk for large_timeout seconds.  warn but continue if the number of stories left to process
    # is only 5% of the total and short_timeout has passed (this is to make the topic not hang entirely because
    # of one link extractor job error).
    prev_num_queued_urls = len(twitter_tfu_ids)
    last_change_time = time()
    while 1:

        queued_tfus = db.query(<<SQL).hashes()
select tfu.*
    from topic_fetch_urls tfu
        join tfu_ids_table ids on (tfu.topic_fetch_urls_id = ids.id)
    where
        state in ('tweet pending')
SQL

        num_queued_urls = len(queued_tfus)

        if num_queued_urls == 0:

            last

        if num_queued_urls not = prev_num_queued_urls:
            last_change_time = time()
        if ( ( time() - last_change_time ) > JOB_POLL_TIMEOUT )

            LOGDIE("Timed out waiting for twitter fetching.\n" . Dumper( queued_tfus) )

        log.info("num_queued_urls twitter urls left to fetch ...")

        prev_num_queued_urls = num_queued_urls
        sleep(JOB_POLL_WAIT)

def show_pending_urls(pending_urls):
    """ list a sample of the pending urls for fetching"""

    num_pending_urls = len(pending_urls)

    num_printed_urls = List::Util::min(num_pending_urls, 3)

    my shuffled_ids = List::Util::shuffle(0 .. ( num_pending_urls - 1) )

    for id (shuffled_ids[ 0 .. in num_printed_urls - 1) ]:

        url = pending_urls->[id]
        log.info("pending url: url['url'] [url['state']: url['fetch_date']]")

# fetch the given links by creating topic_fetch_urls rows and sending them to the FetchLink queue
def fetch_links(db, topic, fetch_links):
    """ for processing.  wait for the queue to complete and returnt the resulting topic_fetch_urls."""

    log.info("fetch_links: queue links")
    tfus = create_and_queue_topic_fetch_urls(db, topic, fetch_links)
    num_queued_links = len(fetch_links)

    log.info("waiting for fetch link queue: num_queued_links queued")

    tfu_ids_list = join(',', map { int( _['topic_fetch_urls_id']) } tfus )

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
    while 1:

        pending_urls = db.query(<<SQL).hashes()
select *, coalesce(fetch_date::text, 'null') fetch_date
    from topic_fetch_urls
    where
        topic_fetch_urls_id in (tfu_ids_list) and
        state in ('pending', 'requeued')
SQL

        pending_url_ids = [map { _['topic_fetch_urls_id'] } pending_urls]

        num_pending_urls = len(pending_url_ids)

        log.info("waiting for fetch link queue: num_pending_urls links remaining ...")

        show_pending_urls(pending_urls)

        if num_pending_urls < 1:

            last

        # if we only have a handful of job left, requeue them all once with a 0 domain throttle
        if (not instant_requeued and ( num_pending_urls <= instant_queue_size) )

            instant_requeued = 1
            map { queue_topic_fetch_url(db.require_by_id( 'topic_fetch_urls', _), 0 ) } pending_url_ids
            sleep(JOB_POLL_WAIT)
            next

        time_since_change = time() - last_pending_change

        # for some reason, the fetch_link queue is occasionally losing a small number of jobs.
        if   (time_since_change > requeue_timeout:
            and ( requeues < max_requeues)
            and (num_pending_urls < max_requeue_jobs) )

            log.info("requeueing fetch_link num_pending_urls jobs ... [requeue requeues]")

            # requeue with a domain_timeout of 0 so that requeued urls can ignore throttling
            map { queue_topic_fetch_url(db.require_by_id( 'topic_fetch_urls', _), 0 ) } pending_url_ids
            ++requeues
            last_pending_change = time()

        if time_since_change > JOB_POLL_TIMEOUT:

            if full_requeues < max_full_requeues:

                map { queue_topic_fetch_url(db.require_by_id( 'topic_fetch_urls', _) ) } pending_url_ids
                ++full_requeues
                last_pending_change = time()

            else

                for id in pending_url_ids:

                    db.update_by_id('topic_fetch_urls', id, { 'state': 'error', message => 'timed out' })

                log.info("timed out " . len( pending_url_ids) . " urls" )

        if num_pending_urls < last_num_pending_urls:

            last_pending_change = time()

        last_num_pending_urls = num_pending_urls

        sleep(JOB_POLL_WAIT)

    _fetch_twitter_urls(db, topic, tfu_ids_list)

    log.info("fetch_links: update topic seed urls")
    db.query(<<SQL)
update topic_seed_urls tsu
    set stories_id = tfu.stories_id, processed = 't'
    from topic_fetch_urls tfu
    where
        tfu.url = tsu.url and
        tfu.stories_id is not null and
        tfu.topic_fetch_urls_id in (tfu_ids_list) and
        tfu.topics_id = tsu.topics_id
SQL

    completed_tfus = db.query(<<SQL).hashes()
select * from topic_fetch_urls where topic_fetch_urls_id in (tfu_ids_list)
SQL

    log.info("completed fetch link queue")

    return completed_tfus

# download any unmatched link in new_links, add it as a story, extract it, add any links to the topic_links list.
# each hash within new_links can either be a topic_links hash or simply a hash with a { url } field.  if
# the link is a topic_links hash, the topic_link will be updated in the database to point ref_stories_id
def add_new_links_chunk(db, topic, iteration, new_links):
    """ to the new link story.  For each link, set the { story } field to the story found or created for the link."""

    die_if_max_stories_exceeded(db, topic)

    log.info("add_new_links_chunk: fetch_links")
    topic_fetch_urls = fetch_links(db, topic, new_links)

    log.info("add_new_links_chunk: mark topic links spidered")
    link_ids = [grep { _ } map { _['topic_links_id'] } new_links]
    db.query(<<SQL, link_ids)
update topic_links set link_spidered = 't' where topic_links_id = any(?)
SQL

def save_metrics(db, topic, iteration, num_links, elapsed_time):
    """ save a row in the topic_spider_metrics table to track performance of spider"""

    topic_spider_metric = {
        'topics_id': topic['topics_id'],
        'iteration': iteration,
        'links_processed': num_links,
        'elapsed_time': elapsed_time

    db.create('topic_spider_metrics', topic_spider_metric)

def add_new_links(db, topic, iteration, new_links, state_updater):
    """ call add_new_links in chunks of ADD_NEW_LINKS_CHUNK_SIZE so we don't lose too much work when we restart the spider"""

    log.info("add new links")

    if not new_links:

        return

    # randomly shuffle the links because it is better for downloading (which has per medium throttling) and extraction
    # (which has per medium locking) to distribute urls from the same media source randomly among the list of links. the
    # link mining and solr seeding routines that feed most links to this function tend to naturally group links
    # from the same media source together.
    shuffled_links = [ List::Util::shuffle(new_links) ]

    spider_progress = get_spider_progress_description(db, topic, iteration, len( shuffled_links) )

    num_links = len(shuffled_links)
    for (i = 0  i < num_links  i += ADD_NEW_LINKS_CHUNK_SIZE)

        start_time = time

        update_topic_state(db, state_updater, "spider_progress iteration links: i / num_links")

        end = List::Util::min(i + ADD_NEW_LINKS_CHUNK_SIZE - 1, $#{ shuffled_links })
        add_new_links_chunk(db, topic, iteration, [shuffled_links[ i .. end ]])

        elapsed_time = time - start_time
        save_metrics(db, topic, iteration, end - i, elapsed_time)

    mine_topic_stories(db, topic)

# find any links for the topic of this iteration or less that have not already been spidered and call
def spider_new_links(db, topic, iteration, state_updater):
    """ add_new_links on them."""

    for (i = 0   i++)

        log.info("spider new links chunk: i")

        new_links = db.query(<<END, iteration, topic['topics_id'], SPIDER_LINKS_CHUNK_SIZE).hashes
select tl.* from topic_links tl, topic_stories ts
    where
        tl.link_spidered = 'f' and
        tl.stories_id = ts.stories_id and
        (ts.iteration <= \1 or ts.iteration = 1000) and
        ts.topics_id = \2 and
        tl.topics_id = \2

    limit \3
END

        if not new_links:

            last

        add_new_links(db, topic, iteration, new_links, state_updater)

def get_spider_progress_description(db, topic, iteration, total_links):
    """ get short text description of spidering progress"""

    log.info("get spider progress description")

    cid = topic['topics_id']

    my (total_stories) = db.query(<<SQL, cid).flat
select count(*) from topic_stories where topics_id = ?
SQL

    my (stories_last_iteration) = db.query(<<SQL, cid, iteration).flat
select count(*) from topic_stories where topics_id = ? and iteration = ? - 1
SQL

    my (queued_links) = db.query(<<SQL, cid).flat
select count(*) from topic_links where topics_id = ? and link_spidered = 'f'
SQL

    return "spidering iteration: iteration stories last iteration / total: " .
      "stories_last_iteration / total_stories links queued: queued_links iteration links: total_links"

def run_spider(db, topic, state_updater):
    """ run the spider over any new links, for num_iterations iterations"""

    log.info("run spider")

    # before we run the spider over links, we need to make sure links have been generated for all existing stories
    mine_topic_stories(db, topic)

    map { spider_new_links(db, topic, topic['max_iterations'], state_updater) } (1 .. topic['max_iterations'])

def mine_topic_stories(db, topic):
    """ mine for links any stories in topic_stories for this topic that have not already been mined"""

    log.info("mine topic stories")

    # skip for non-web topic, because the below query grows very large without ever mining links
    if topic['platform'] ne 'web':

        log.info("skip link generation for non-web topic")
        return

    # chunk the story extractions so that one big topic does not take over the entire queue
    i = 0
    while 1:

        i += EXTRACT_STORY_LINKS_CHUNK_SIZE
        log.info("mine topic stories: chunked i ...")
        stories = db.query(<<SQL, topic['topics_id'], EXTRACT_STORY_LINKS_CHUNK_SIZE).hashes
    select s.*, ts.link_mined, ts.redirect_url
        from snap.live_stories s
            join topic_stories ts on (s.stories_id = ts.stories_id and s.topics_id = ts.topics_id)
        where
            ts.link_mined = false and
            ts.topics_id = ?
        limit ?
SQL

        num_stories = len(stories)

        if num_stories == 0:

            last

        generate_topic_links(db, topic, stories)

        if num_stories < EXTRACT_STORY_LINKS_CHUNK_SIZE:

            last

# import all topic_seed_urls that have not already been processed
def import_seed_urls(db, topic, state_updater):
    """ return 1 if new stories were added to the topic and 0 if not"""

    log.info("import seed urls")

    topics_id = topic['topics_id']

    # take care of any seed urls with urls that we have already processed for this topic
    db.query(<<END, topics_id)
update topic_seed_urls a set stories_id = b.stories_id, processed = 't'
    from topic_seed_urls b
    where a.url = b.url and
        a.topics_id = ? and b.topics_id = a.topics_id and
        a.stories_id is null and b.stories_id is not null
END

    # randomly shuffle this query so that we don't block the extractor pool by throwing it all
    # stories from a single media_id at once
    seed_urls = db.query(<<END, topics_id).hashes
select * from topic_seed_urls where topics_id = ? and processed = 'f' order by random()
END

    if not seed_urls:

        return 0

    # process these in chunks in case we have to start over so that we don't have to redo the whole batch
    num_urls = len(seed_urls)
    for (i = 0  i < num_urls  i += ADD_NEW_LINKS_CHUNK_SIZE)

        start_time = time

        update_topic_state(db, state_updater, "importing seed urls: i / num_urls")

        end = List::Util::min(i + ADD_NEW_LINKS_CHUNK_SIZE - 1, $#{ seed_urls })

        # verify that the seed urls are still there and not processed, in case we have mucked with them while spidering
        urls_ids_list = join(',', map { int( _['topic_seed_urls_id']) } seed_urls[ i .. end] )
        seed_urls_chunk = db.query(<<SQL).hashes()
select * from topic_seed_urls where topic_seed_urls_id in (urls_ids_list) and not processed
SQL

        add_new_links_chunk(db, topic, 0, seed_urls_chunk)

        ids_list = join(',', map { int( _['topic_seed_urls_id']) } seed_urls_chunk )

        # update topic_seed_urls that were actually fetched
        db.query(<<SQL)
update topic_seed_urls tsu
    set stories_id = tfu.stories_id
    from topic_fetch_urls tfu
    where
        tsu.topics_id = tfu.topics_id and
        md5(tsu.url) = md5(tfu.url) and
        tsu.topic_seed_urls_id in (ids_list)
SQL

        # now update the topic_seed_urls that were matched
        db.query(<<SQL)
update topic_seed_urls tsu
    set processed = 't'
    where
        tsu.topic_seed_urls_id in (ids_list) and
        processed = 'f'
SQL

        elapsed_time = time - start_time
        save_metrics(db, topic, 1, end - i, elapsed_time)

    # cleanup any topic_seed_urls pointing to a merged story
    db.query(
        <<SQL,
        UPDATE topic_seed_urls AS tsu
        SET stories_id = tms.target_stories_id, processed = 't'
        FROM topic_merged_stories_map AS tms,
             topic_stories ts
        WHERE tsu.stories_id = tms.source_stories_id
          AND ts.stories_id = tms.target_stories_id
          AND tsu.topics_id = ts.topics_id
          AND ts.topics_id = \1
SQL
        topic['topics_id']
    )

    return len(seed_urls)

def insert_topic_seed_urls(db, topic_seed_urls):
    """ insert a list of topic seed urls"""

    INFO "inserting " . len(topic_seed_urls) . " topic seed urls ..."

    for tsu in topic_seed_urls:

        insert_tsu = None
        map { insert_tsu['_'] = tsu['_'] } qw/stories_id url topics_id assume_match/
        db.create('topic_seed_urls', insert_tsu)

# return true if the given month offset is within the dates that should be respidered.  always return true 
def _import_month_within_respider_date(topic, month_offset):
    """ if there are not respider dates"""

    start_date = topic['respider_start_date'] or ''
    end_date = topic['respider_end_date'] or ''

    if not topic['respider_stories'] and (start_date or end_date):

        return 1

    month_date = Time::Piece.strptime(topic['start_date'], "Y-m-d").add_months(month_offset)

    if end_date:

        end_date = Time::Piece.strptime(end_date, "Y-m-d").add_months(-1)
        if month_date > end_date:
            return 1

    if start_date:

        start_date = Time::Piece.strptime(start_date, "Y-m-d")
        if month_date < start_date:
            return 1

    return 0

# Call search_solr_for_stories_ids() above and then query PostgreSQL for the stories returned by Solr.
def __search_for_stories(db, params):
    """ Include stories.* and media_name as the returned fields."""

    stories_ids = mediawords.solr.search_solr_for_stories_ids(db, params)

    stories = [map { { 'stories_id': _ } } stories_ids]

    stories = mediawords.dbi.stories.attach_story_meta_data_to_stories(db, stories)

    stories = [grep { _['url'] } stories]

    return stories

def import_solr_seed_query_month(db, topic, month_offset):
    """ import a single month of the solr seed query.  we do this to avoid giant queries that timeout in solr."""

    if not topic['platform'] == 'web':

        return 0

    solr_query = mediawords.solr.query.get_full_solr_query_for_topic(db, topic, undef, undef, month_offset)

    # this should return undef once the month_offset gets too big
    if not solr_query:
        return undef

    if not _import_month_within_respider_date(topic, month_offset):
        return 1

    max_stories = topic['max_stories']

    # if solr maxes out on returned stories, it returns a few documents less than the rows= parameter, so we
    # assume that we hit the solr max if we are within 5% of the ma stories
    max_returned_stories = max_stories * 0.95

    INFO "import solr seed query month offset month_offset"
    solr_query['rows'] = max_stories

    stories = __search_for_stories(db, solr_query)

    if (len( stories) > max_returned_stories )

        die("solr_seed_query returned more than max_returned_stories stories")

    INFO "adding " . len(stories) . " stories to topic_seed_urls"

    topic_seed_urls = []
    for story in stories:

        push(
            topic_seed_urls,

                'topics_id': topic['topics_id'],
                'url': story['url'],
                'stories_id': story['stories_id'],
                'assume_match': 'f'

        )

    insert_topic_seed_urls(db, topic_seed_urls)

    return 1

# import stories intro topic_seed_urls from solr by running
# topic['solr_seed_query'] against solr.  if the solr query has
def import_solr_seed_query(db, topic):
    """ already been imported, do nothing."""

    log.info("import solr seed query")

    if topic['solr_seed_query_run']:

        return

    month_offset = 0
    while (import_solr_seed_query_month( db, topic, month_offset++) ) { }

    db.query("update topics set solr_seed_query_run = 't' where topics_id = ?", topic['topics_id'])

def all_facebook_data_fetched(db, topic):
    """ return true if there are no stories without facebook data"""

    null_facebook_story = db.query(<<SQL, topic['topics_id']).hash
select 1
    from topic_stories cs
        left join story_statistics ss on (cs.stories_id = ss.stories_id)
    where
        cs.topics_id = ? and
        ss.facebook_api_error is null and
        (
            ss.stories_id is null or
            ss.facebook_share_count is null or
            ss.facebook_comment_count is null or
            ss.facebook_api_collect_date is null
        )
    limit 1
SQL

    return not null_facebook_story

def __add_topic_stories_to_facebook_queue(db, topic):
    """ add all topic stories without facebook data to the queue"""

    topics_id = topic['topics_id']

    stories = db.query(<<END, topics_id).hashes
SELECT ss.*, cs.stories_id
    FROM topic_stories cs
        left join story_statistics ss on (cs.stories_id = ss.stories_id)
    WHERE cs.topics_id = ?
    ORDER BY cs.stories_id
END

    unless (scalar stories)

        log.debug("No stories found for topic 'topic['name']'")

    for ss in stories:

        stories_id = ss['stories_id']
        args = { 'stories_id': stories_id }

        if   ss['facebook_api_error']
            or not defined(ss['facebook_api_collect_date']:
            or not defined( ss['facebook_share_count'])
            or not defined(ss['facebook_comment_count']) )

            log.debug("Adding job for story stories_id")
            mediawords.job.broker.new('mediawords.job.facebook.fetchstorystats').add_to_queue(args)

def fetch_social_media_data(db, topic):
    """ send high priority jobs to fetch facebook data for all stories that don't yet have it"""

    log.info("fetch social media data")

    # test spider should be able to run with job broker, so we skip social media collection
    if _test_mode:
        return

    cid = topic['topics_id']

    __add_topic_stories_to_facebook_queue(db, topic)

    poll_wait = 30
    retries = int(MAX_SOCIAL_MEDIA_FETCH_TIME / poll_wait) + 1

    for i in 1 .. retries:

        if all_facebook_data_fetched(db, topic):
            return
        sleep poll_wait

    LOGCONFESS("Timed out waiting for social media data")

def check_job_error_rate(db, topic):
    """ die if the error rate for link extraction or link fetching is too high"""

    log.info("check job error rate")

    fetch_stats = db.query(<<SQL, topic['topics_id']).hashes()
select count(*) num, (state = 'python error') as error
    from topic_fetch_urls
        where topics_id = ?
        group by (state = 'python error')
SQL

    my (num_fetch_errors, num_fetch_successes) = (0, 0)
    for s in fetch_stats:

        if   (s['error']) { num_fetch_errors    += s['num'] }
        else                   { num_fetch_successes += s['num'] }

    fetch_error_rate = num_fetch_errors / (num_fetch_errors + num_fetch_successes + 1)

    log.info( "Fetch error rate: fetch_error_rate (num_fetch_errors / num_fetch_successes)" )

    if fetch_error_rate > MAX_JOB_ERROR_RATE:

        die("Fetch error rate of fetch_error_rate is greater than max of MAX_JOB_ERROR_RATE")

    link_stats = db.query(<<SQL, topic['topics_id']).hashes()
select count(*) num, ( length( link_mine_error) > 0 ) as error
    from topic_stories
        where topics_id = ?
        group by (length( link_mine_error) > 0 )
SQL

    my (num_link_errors, num_link_successes) = (0, 0)
    for s in link_stats:

        if   (s['error']) { num_link_errors    += s['num'] }
        else                   { num_link_successes += s['num'] }

    link_error_rate = num_link_errors / (num_link_errors + num_link_successes + 1)

    log.info( "Link error rate: link_error_rate (num_link_errors / num_link_successes)" )

    if link_error_rate > MAX_JOB_ERROR_RATE:

        die("link error rate of link_error_rate is greater than max of MAX_JOB_ERROR_RATE")

def import_urls_from_seed_queries(db, topic, state_updater):
    """ import urls from seed query """

    topic_seed_queries = db.query(
        "select * from topic_seed_queries where topics_id = ?", topic['topics_id'] ).hashes()

    num_queries = len(topic_seed_queries)

    if (( num_queries not = 1) and (topic['mode'] == 'url_sharing'))

        die("exactly one topic seed query required per url_sharing topic")

    if topic['mode'] == 'web':

        log.debug("import seed urls from solr")
        update_topic_state(db, state_updater, "importing solr seed query")
        import_solr_seed_query(db, topic)

    for tsq in topic_seed_queries:

        tsq_dump = tsq['topic_seed_queries_id']
        fetcher = mediawords.tm.fetchtopicposts.get_post_fetcher(tsq) 
        if not fetcher:
            die("unable to import seed urls for platform/source of seed query: tsq_dump")

        log.debug("import seed urls from fetch_topic_posts:\ntsq_dump")
        mediawords.tm.fetchtopicposts.fetch_topic_posts(db, tsq)

    db.query(<<SQL, topic['topics_id'])
insert into topic_seed_urls (url, topics_id, assume_match, source, topic_seed_queries_id, topic_post_urls_id)
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
            tsq.topics_id = ? 
        on conflict (topic_post_urls_id) do nothing
SQL

# if the query or dates have changed, set topic_stories.link_mined to false for the impacted stories so that
def set_stories_respidering(db, topic, snapshots_id):
    """ they will be respidered"""

    if not topic['respider_stories']:

        return

    respider_start_date = topic['respider_start_date']
    respider_end_date = topic['respider_end_date']

    if not respider_start_date and not respider_end_date:

        db.query("update topic_stories set link_mined = 'f' where topics_id = ?", topic['topics_id'])
        return

    if respider_start_date:

        db.query(<<SQL, respider_start_date, topic['start_date'], topic['topics_id'])
update topic_stories ts set link_mined = 'f'
    from stories s
    where
        ts.stories_id = s.stories_id and
        s.publish_date >= \2 and 
        s.publish_date <= \1 and
        ts.topics_id = \3
SQL
        if snapshots_id:

            db.update_by_id('snapshots', snapshots_id, { 'start_date': topic['start_date'] })
            db.query(<<SQL, snapshots_id, respider_start_date)
update timespans set archive_snapshots_id = snapshots_id, snapshots_id = null
    where snapshots_id = ? and start_date < ?
SQL

    if respider_end_date:

        db.query(<<SQL, respider_end_date, topic['end_date'], topic['topics_id'])
update topic_stories ts set link_mined = 'f'
    from stories s
    where
        ts.stories_id = s.stories_id and
        s.publish_date >= \1 and 
        s.publish_date <= \2 and
        ts.topics_id = \3
SQL

        if snapshots_id:

            db.update_by_id('snapshots', snapshots_id, { 'end_date': topic['end_date'] })
            db.query(<<SQL, snapshots_id, respider_end_date)
update timespans set archive_snapshots_id = snapshots_id, snapshots_id = null
    where snapshots_id = ? and end_date > ?
SQL

    db.update_by_id('topics', topic['topics_id'],
        { 'respider_stories': 'f', respider_start_date => undef, respider_end_date => undef })

# mine the given topic for links and to recursively discover new stories on the web.
# options:
#   import_only - only run import_seed_urls and import_solr_seed and exit
#   skip_post_processing - skip social media fetching and snapshotting
def do_mine_topic(db, topic, options, state_updater):
    """   snapshots_id - associate topic with the given existing snapshot"""

    map { options['_'] or= 0 } qw/import_only skip_post_processing test_mode/

    update_topic_state(db, state_updater, "importing seed urls")
    import_urls_from_seed_queries(db, topic, state_updater)

    update_topic_state(db, state_updater, "setting stories respidering...")
    set_stories_respidering(db, topic, options['snapshots_id'])

    # this may put entires into topic_seed_urls, so run it before import_seed_urls.
    # something is breaking trying to call this perl.  commenting out for time being since we only need
    # this when we very rarely change the foreign_rss_links field of a media source - hal
    # update_topic_state(db, state_updater, "merging foreign rss stories")
    # mediawords.tm.stories.merge_foreign_rss_stories(db, topic)

    update_topic_state(db, state_updater, "importing seed urls")
    if (import_seed_urls( db, topic, state_updater) > MIN_SEED_IMPORT_FOR_PREDUP_STORIES )

        # merge dup stories before as well as after spidering to avoid extra spidering work
        update_topic_state(db, state_updater, "merging duplicate stories")
        mediawords.tm.stories.find_and_merge_dup_stories(db, topic)

    unless (options['import_only'])

        update_topic_state(db, state_updater, "running spider")
        run_spider(db, topic, state_updater)

        check_job_error_rate(db, topic)

        # merge dup media and stories again to catch dups from spidering
        update_topic_state(db, state_updater, "merging duplicate stories")
        mediawords.tm.stories.find_and_merge_dup_stories(db, topic)

        update_topic_state(db, state_updater, "merging duplicate media stories")
        mediawords.tm.stories.merge_dup_media_stories(db, topic)

        if not options['skip_post_processing']:

            update_topic_state(db, state_updater, "fetching social media data")
            fetch_social_media_data(db, topic)

            update_topic_state(db, state_updater, "snapshotting")
            snapshot_args = { 'topics_id': topic['topics_id'], snapshots_id => options['snapshots_id'] }
            mediawords.job.statefulbroker.new('mediawords.job.tm.snapshottopic').add_to_queue(snapshot_args)

def mine_topic(db, topic, options, state_updater):
    """ wrap do_mine_topic in eval and handle errors and state"""

    # the topic spider can sit around for long periods doing solr queries, so we need to make sure the postgres
    # connection does not get timed out
    db.query("set idle_in_transaction_session_timeout = 0")

    prev_test_mode = _test_mode

    if options['test_mode']:

        _test_mode = 1

    if topic['state'] ne 'running':

        mediawords.tm.alert.send_topic_alert(db, topic, "started topic spidering")

    eval { do_mine_topic(db, topic, options, state_updater) }
    if $@:

        error = $@
        mediawords.tm.alert.send_topic_alert(db, topic, "aborted topic spidering due to error")
        LOGDIE(error)

    _test_mode = prev_test_mode

1
