import random
import socket
import time

import lorem

import mediawords.db
import mediawords.test.hash_server
import mediawords.util.sql
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.web.user_agent.request.request import Request

import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

BASE_PORT = 8890

NUM_SITES = 5
NUM_PAGES_PER_SITE = 10
NUM_LINKS_PER_PAGE = 2

TOPIC_PATTERN = 'FOOBARBAZ'

def get_html_link(page):
    return page['url']

def lorem_sentences(n: int) -> str:
    return ' '.join([lorem.sentence() for i in range(n)])

def generate_content_for_site(site):
    body = lorem_sentences(5)

    return f"""
        <html>
        <head>
            <title>site['title']</title>
        </head>
        <body>
            <p>
            body
            </p>
        </body>
        </html>
        """

def randindex(n):
    """generate a random int >=  0 and < n."""
    return random.randint(0, n - 1)

def generate_content_for_page(site, page):
    num_links = len(page['links'])
    num_paragraphs = int(randindex(10) + 3) + num_links

    paragraphs = []

    for i in range(num_paragraphs):
        text = lorem_sentences(5)
        if i < num_links:
            html_link = get_html_link(page['links'][i])
            text += f" {html_link}"

        paragraphs.append(text)

    if randindex(2) < 1:
        paragraphs.append(lorem.sentence() + f" {TOPIC_PATTERN}")
        page['matches_topic'] = 1

    dead_link_text = lorem_sentences(5)
    dead_link_text += f" <a href='{page['url']}/dead'>dead link</a>"

    paragraphs.append(dead_link_text)

    body = "\n\n".join([f"<p>\n{p}\n</p>" for p in paragraphs])

    return f"""
        <html>
        <head>
            <title>{page['title']}</title>
        </head>
        <body>
            {body}
        </body>
        </html>
    """

def generate_content_for_sites(sites):
    for site in sites:
        site['content'] = generate_content_for_site(site)

        for p in site['pages']:
            p['content'] = generate_content_for_page(site, p)

def get_test_sites():
    """ generate test set of sites"""
    sites = []
    pages = []

    # base_port = BASE_PORT + int(rand( 200) )
    base_port = BASE_PORT

    for site_id in range(NUM_SITES):
        port = base_port + site_id
        # other containers will access this host to we have to set the actual hostname instead of just localhost
        host = socket.gethostname()

        site = {
            'port': port,
            'id': site_id,
            'url': f"http://{host}:{port}/",
            'title': f"site {site_id}",
            'pages': []
        }

        num_pages = int(randindex(NUM_PAGES_PER_SITE)) + 1
        for page_id in range(num_pages):
            date = mediawords.util.sql.get_sql_date_from_epoch(time.time() - (randindex(365) * 86400))

            path = f"page-{page_id}"

            page = {
                'id': page_id,
                'path': f"/{path}",
                'url': f"{site['url']}{path}",
                'title': f"page {page_id}",
                'pubish_date': date,
                'links': [],
                'matches_topic': False
            }

            pages.append(page)
            site['pages'].append(page)

        sites.append(site)

    for page in pages:
        num_links = int(randindex(NUM_LINKS_PER_PAGE))
        for link_id in range(num_links):
            linked_page_id = int(randindex(len(pages)))
            linked_page = pages[linked_page_id]

            if not mediawords.util.url.urls_are_equal(page['url'], linked_page['url']):
                page['links'].append(linked_page)

    generate_content_for_sites(sites)

    return sites

def add_site_media(db, sites):
    """add a medium for each site so that the spider can find the medium that corresponds to each url"""
    for s in sites:
        s['medium'] = db.create('media', {'url': s['url'], 'name': s['title']})

def start_hash_servers(sites):
    hash_servers = []

    for site in sites:
        site_hash = {}
        site_hash['/'] = site['content']

        for p in site['pages']:
            site_hash[p['path']] = p['content']

        hs = mediawords.test.hash_server.HashServer(port=site['port'], pages=site_hash)

        log.debug(f"starting hash server {site['id']}")

        hs.start()

        hash_servers.append(hs)

    # wait for the hash servers to start
    time.sleep(1)

    return hash_servers

def validate_page(label, url, expected_content):

    log.debug(f"test page: {label} {url}")

    ua = UserAgent()
    request = Request('get', url)
    response = ua.request(request)

    assert response.is_success(), f"request success: {label} {url}"

    got_content = response.decoded_content()

    log.debug("got content")

    assert got_content == expected_content

def validate_pages(sites):
    for site in sites:
        log.debug(f"testing pages for site {site['id']}")
        validate_page(f"site {site['id']}", site['url'], site['content'])

        [validate_page(f"page {site['id']} p{['id']}", p['url'], p['content']) for p in site['pages']]

def seed_unlinked_urls(db, topic, sites):
    all_pages = []
    [all_pages.extend(s['pages']) for s in sites]

    # do not seed urls that are linked directly from a page that is a topic match.
    # this forces the test to succesfully discover those pages through spidering.
    non_seeded_url_lookup = {}
    for page in all_pages:
        if page['matches_topic']:
            for l in page['links']:
                non_seeded_url_lookup[l['url']] = 1

    seed_pages = []
    for page in all_pages:
        if non_seeded_url_lookup.get(page['url'], False):
            log.debug(f"non seeded url: {page['url']}")
        else:
            log.debug(f"seed url: {page['url']}")
            seed_pages.append(page)

    [db.create('topic_seed_urls', {'topics_id': topic['topics_id'], 'url': p['url']}) for p in seed_pages]

def create_topic(db, sites):
    now = mediawords.util.sql.sql_now()
    start_date = mediawords.util.sql.increment_day(now, -30)
    end_date = mediawords.util.sql.increment_day(now, 30)

    topic = {
        'name': 'test topic',
        'description': 'test topic',
        'pattern': TOPIC_PATTERN,
        'solr_seed_query': 'stories_id:0',
        'solr_seed_query_run': 't',
        'start_date': start_date,
        'end_date': end_date,
        'job_queue': 'mc',
        'max_stories': 100_000,
        'platform': 'web'
    }
    topic = db.create('topics', topic)

    seed_unlinked_urls(db, topic, sites)

    # avoid race condition in TM::Mine
    db.create('tag_sets', {'name': 'extractor_version'})

    return topic

def validate_topic_stories(db, topic, sites):
    topic_stories = db.query(
        """
        select cs.*, s.*
            from topic_stories cs
                join stories s on (s.stories_id = cs.stories_id)
            where cs.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    all_pages = []
    [all_pages.extend(s['pages']) for s in sites]

    log.info(f"ALL PAGES: {len(all_pages)}")

    topic_pages = [p for p in all_pages if p['matches_topic']]

    log.info(f"TOPIC PAGES: {len(topic_pages)}")

    topic_pages_lookup = {s['url']: s for s in topic_stories}

    log.info(f"TOPIC PAGES LOOKUP: {len(topic_pages_lookup)}")

    for topic_story in topic_stories:
        assert topic_pages_lookup.get(topic_story['url'], False)
        del topic_pages_lookup[topic_story['url']]

    assert len(topic_pages_lookup) == 0

    # Wait for pending URLs to disappear
    WAIT_PENDING_SECONDS = 10
    pending_count = 0
    pending_retry = 0
    while pending_retry <= WAIT_PENDING_SECONDS:
        pending_count = db.query("select count(*) from topic_fetch_urls where state ='pending'").flat()[0]
        if pending_count > 0:
            log.warning("Still pending_count URLs are pending, will retry shortly")
            time.sleep(1)
        else:
            log.info("No more pending URLs, continuing")
            break

        pending_retry += 1

    assert pending_count == 0, f"After waiting {WAIT_PENDING_SECONDS} some URLs are still in 'pending' state"

    dead_link_count = db.query( "select count(*) from topic_fetch_urls where state ='request failed'").flat()[0]
    dead_pages_count = db.query("select count(*) from topic_fetch_urls where url like '%dead%'").flat()[0]

    if dead_link_count != dead_pages_count:
        fetch_states = db.query("select count(*), state from topic_fetch_urls group by state" ).hashes()
        log.info(f"fetch states: {fetch_states}")

        fetch_errors = db.query("select * from topic_fetch_urls where state = 'python error'").hashes()
        log.info(f"fetch errors: {fetch_errors}")

    assert dead_link_count == dead_pages_count, "dead link count"

def validate_topic_links(db, topic, sites):
    cid = topic['topics_id']

    topic_links = db.query("select * from topic_links").hashes()

    log.info(f"TOPIC LINKS: {len(topic_links)}")

    all_pages = []
    [all_pages.extend(s['pages']) for s in sites]

    for page in all_pages:
        if not page['matches_topic']:
            continue

        for link in page['links']:
            if not link['matches_topic']:
                continue

            topic_links = db.query(
                """
                select *
                    from topic_links cl
                        join stories s on (cl.stories_id = s.stories_id)
                    where
                        s.url = %(a)s and
                        cl.url = %(b)s and
                        cl.topics_id = %(c)s 
                """,
                {'a': page['url'], 'b': link['url'], 'c': cid}).hashes()

            assert len(topic_links) == 1, f"number of topic_links for {page['url']} -> {link['url']}"

    topic_spider_metric = db.query(
        "select sum(links_processed) links_processed from topic_spider_metrics where topics_id = %(a)s",
        {'a': cid}).hash()

    assert topic_spider_metric,"topic spider metrics exist"
    assert topic_spider_metric['links_processed'] > len(topic_links), "metrics links_processed greater than topic_links"

def validate_for_errors(db):
    """ test that no errors exist in the topics or snapshots tables"""
    error_topics = db.query("select * from topics where state = 'error'").hashes()

    assert len( error_topics) == 0, f"topic errors: {error_topics}"

    error_snapshots = db.query("select * from snapshots where state = 'error'").hashes()

    assert len( error_snapshots) == 0, f"snapshot errors:{error_snapshots}"

def validate_spider_results(db, topic, sites):
    validate_topic_stories(db, topic, sites)
    validate_topic_links(db, topic, sites)
    validate_for_errors(db)

def get_site_structure(sites):
    meta_sites = []
    for site in sites:
        meta_site = {'url': site['url'], 'pages': []}
        for page in site['pages']:
            meta_page = {'url': page['url'], 'matches_topic': page['matches_topic'], 'links': []}
            [meta_page['links'].append(l['url']) for l in page['links']]

            if page['matches_topic'] and meta_page['matches_topic']:
                meta_page['content'] = page['content']

            meta_site['pages'].append(meta_page)

        meta_sites.append(meta_site)

    return meta_sites

def test_mine():
    # we pseudo-randomly generate test data, but we want repeatable tests
    random.seed(3)

    db = mediawords.db.connect_to_db()

    mediawords.util.mail.enable_test_mode()

    sites = get_test_sites()

    log.debug(f"SITE STRUCTURE {get_site_structure(sites)}")

    add_site_media(db, sites)

    hash_servers = start_hash_servers(sites)

    validate_pages(sites)

    topic = create_topic(db, sites)

    topics_mine.mine.DOMAIN_TIMEOUT = 0

    topics_mine.mine.mine_topic(
        db=db,
        topic=topic,
        skip_post_processing=True)

    validate_spider_results(db, topic, sites)

    [hs.stop for hs in hash_servers]
