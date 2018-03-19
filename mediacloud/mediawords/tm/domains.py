"""Dealing with url domains within topics."""

import re

from mediawords.db.handler import DatabaseHandler
import mediawords.util.log

logger = mediawords.util.log.create_logger(__name__)

# max number of self links from a single domain
MAX_SELF_LINKS = 1000

# regex for urls that should always be skipped if the domain is linking to itself
SKIP_SELF_LINK_RE = r'/(?:tag|category|author|search)'


def increment_domain_links(db: DatabaseHandler, topic_link: dict) -> None:
    """Given a topic link, increment the self_links and all_links counts in the corresponding topic_domains row.

    Increment self_links if the domain if the story at topic_links.stories_id is the same as the domain of
    topic_links.url or topic_links.redirect_url.  Always increment all_links.
    """
    story = db.require_by_id('stories', topic_link['stories_id'])
    story_domain = mediawords.util.url.get_url_distinctive_domain(story['url'])

    url_domain = mediawords.util.url.get_url_distinctive_domain(topic_link['url'])

    redirect_url = topic_link.get('redirect_url', topic_link['url'])
    redirect_url_domain = mediawords.util.url.get_url_distinctive_domain(redirect_url)

    self_link = 1 if story_domain in (url_domain, redirect_url_domain) else 0

    db.query(
        """
        insert into topic_domains (topics_id, domain, self_links, all_links)
            values(%(topics_id)s, %(domain)s, %(self_link)s, 1)
            on conflict (topics_id, md5(domain))
                do update set self_links = self_links + %(self_link)s, all_links = all_links + 1
        """,
        {'topics_id': topic_link['topics_id'], 'domain': redirect_url_domain, 'self_link': self_link})


def skip_self_linked_domain(db: DatabaseHandler, topic_fetch_url: dict) -> bool:
    """Given a topic_fetch_url, return true if the url should be skipped because it is a self linked domain.

    Return true if the domain of the linked url is the same as the domain of the linking story and one of the following
    is true:
    * topic.domains.self_links value for the domain is greater than MAX_SELF_LINKS or
    * the linked url matches SKIP_SELF_LINK_RE.

    Always return false if topic_fetch_url['topic_links_id'] is None.
    """
    if topic_fetch_url['topic_links_id'] is None:
        return False

    topic_link = db.require_by_id('topic_links', topic_fetch_url['topic_links_id'])

    story = db.require_by_id('stories', topic_link['stories_id'])
    story_domain = mediawords.util.url.get_url_distinctive_domain(story['url'])

    url_domain = mediawords.util.url.get_url_distinctive_domain(topic_link['url'])

    redirect_url = topic_link.get('redirect_url', topic_link['url'])
    redirect_url_domain = mediawords.util.url.get_url_distinctive_domain(redirect_url)

    link_domain = redirect_url_domain or url_domain

    if story_domain not in (url_domain, redirect_url_domain):
        return False

    if re.search(SKIP_SELF_LINK_RE, link_domain, flags=re.I):
        return True

    topic_domain = db.query(
        "select * from topic_domains where topics_id = %(a)s and md5(domain) = md5(%(b)s)",
        {'a': topic_fetch_url['topics_id'], 'b': link_domain}).hash

    if topic_domain and topic_domain['self_links'] > MAX_SELF_LINKS:
        return True

    return False
