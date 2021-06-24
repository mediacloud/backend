"""Dealing with url domains within topics."""

import re

from mediawords.db.handler import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.url import get_url_distinctive_domain

log = create_logger(__name__)

# max number of self links from a single domain
MAX_SELF_LINKS = 200

# regex for urls that should always be skipped if the domain is linking to itself
SKIP_SELF_LINK_RE = r'\/(?:tag|category|author|search|congress.gov|nih.gov|wikinews.org|house.gov)'


def increment_domain_links(db: DatabaseHandler, topic_link: dict) -> None:
    """Given a topic link, increment the self_links count is necessary n the corresponding topic_domains row.

    Increment self_links if the domain of the story at topic_links.stories_id is the same as the domain of
    topic_links.url or topic_links.redirect_url.
    """
    story = db.require_by_id('stories', topic_link['stories_id'])
    story_domain = get_url_distinctive_domain(story['url'])

    url_domain = get_url_distinctive_domain(topic_link['url'])

    redirect_url = topic_link.get('redirect_url', topic_link['url'])
    redirect_url_domain = get_url_distinctive_domain(redirect_url)

    if story_domain not in (url_domain, redirect_url_domain):
        return

    topic_domain = db.query(
        """
            INSERT INTO topic_domains (topics_id, domain, self_links)
            VALUES (%(topics_id)s, %(domain)s, 1)
            ON CONFLICT (topics_id, md5(domain)) DO NOTHING
            RETURNING *
        """,
        {
            'topics_id': topic_link['topics_id'],
            'domain': redirect_url_domain
        }
    ).hash()

    # do this update separately instead of as an upsert because the upsert was occasionally deadlocking
    if not topic_domain:
        db.query(
            """
            UPDATE topic_domains set
                self_links = topic_domains.self_links + 1
            WHERE
                topics_id = %(topics_id)s AND
                domain = %(domain)s
            """,
            {
                'topics_id': topic_link['topics_id'],
                'domain': redirect_url_domain
            }
        )


def skip_self_linked_domain_url(db: DatabaseHandler, topics_id: int, source_url: str, ref_url: str) -> bool:
    """Return true if the url should be skipped because it is a self linked domain within the topic.

    Return true if the domain of the ref_url is the same as the domain of the story_url and one of the following
    is true:
    * topic.domains.self_links value for the domain is greater than MAX_SELF_LINKS or
    * ref_url matches SKIP_SELF_LINK_RE.
    """
    source_domain = get_url_distinctive_domain(source_url)
    ref_domain = get_url_distinctive_domain(ref_url)

    if source_domain != ref_domain:
        return False

    if re.search(SKIP_SELF_LINK_RE, ref_url, flags=re.I):
        return True

    topic_domain = db.query(
        """
        SELECT *
        FROM topic_domains
        WHERE
            topics_id = %(a)s AND
            md5(domain) = md5(%(b)s)
        """,
        {'a': topics_id, 'b': ref_domain}
    ).hash()

    if topic_domain and topic_domain['self_links'] >= MAX_SELF_LINKS:
        return True

    return False


def skip_self_linked_domain(db: DatabaseHandler, topic_fetch_url: dict) -> bool:
    """Given a topic_fetch_url, return true if the url should be skipped because it is a self linked domain.

    Return skip_self_linked_domain_url() for the topic, source url and ref url of the given topic_fetch_url.

    Always return false if topic_fetch_url['topic_links_id'] is None or not in the dict.
    """
    if 'topic_links_id' not in topic_fetch_url or topic_fetch_url['topic_links_id'] is None:
        return False

    topic_link = db.query("""
        SELECT *
        FROM topic_links
        WHERE
            topics_id = %(topics_id)s AND
            topic_links_id = %(topic_links_id)s
    """, {
        'topics_id': topic_fetch_url['topics_id'],
        'topic_links_id': topic_fetch_url['topic_links_id'],
    }).hash()
    if not topic_link:
        raise Exception(f"Topic link ID {topic_fetch_url['topic_links_id']} was not found.")

    story = db.require_by_id('stories', topic_link['stories_id'])

    url = topic_link.get('redirect_url', topic_link['url'])

    return skip_self_linked_domain_url(db, topic_fetch_url['topics_id'], story['url'], url)
