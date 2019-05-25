from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from sitemap_fetch_media_pages.tree import sitemap_tree_for_homepage

log = create_logger(__name__)


# FIXME add test for this function
def fetch_sitemap_pages_for_media_id(db: DatabaseHandler, media_id: int) -> None:
    """Fetch and store all pages (news stories or not) from media's sitemap tree."""
    media = db.find_by_id(table='media', object_id=media_id)
    if not media:
        raise Exception("Unable to find media with ID {}".format(media_id))

    media_url = media['url']

    log.info("Fetching sitemap pages for media ID {} ({})...".format(media_id, media_url))
    sitemaps = sitemap_tree_for_homepage(homepage_url=media_url)
    pages = sitemaps.all_pages()
    log.info("Fetched {} pages for media ID {} ({}).".format(len(pages), media_id, media_url))

    log.info("Storing {} sitemap pages for media ID {} ({})...".format(len(pages), media_id, media_url))

    insert_counter = 0
    for page in pages:
        db.query("""
            INSERT INTO media_sitemap_pages (
                media_id, url, last_modified, change_frequency, priority,
                news_title, news_publish_date
            ) VALUES (
                %(media_id)s, %(url)s, %(last_modified)s, %(change_frequency)s, %(priority)s,
                %(news_title)s, %(news_publish_date)s
            )
            ON CONFLICT (url) DO NOTHING
        """, {
            'media_id': media_id,
            'url': page.url,
            'last_modified': page.last_modified,
            'change_frequency': page.change_frequency.value if page.change_frequency is not None else None,
            'priority': page.priority,
            'news_title': page.news_story.title if page.news_story is not None else None,
            'news_publish_date': page.news_story.publish_date if page.news_story is not None else None,
        })

        insert_counter += 1
        if insert_counter % 1000 == 0:
            log.info("Inserted {} / {} URLs...".format(insert_counter, len(pages)))

    log.info("Done storing {} sitemap pages for media ID {} ({}).".format(len(pages), media_id, media_url))
