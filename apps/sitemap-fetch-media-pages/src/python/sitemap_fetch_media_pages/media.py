from typing import Optional

from usp.tree import sitemap_tree_for_homepage
from usp.web_client.abstract_client import (
    AbstractWebClient,
    AbstractWebClientSuccessResponse,
    RETRYABLE_HTTP_STATUS_CODES,
    WebClientErrorResponse,
    AbstractWebClientResponse,
)

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import UserAgent, Response

log = create_logger(__name__)


class _SitemapWebClientResponse(AbstractWebClientSuccessResponse):
    __slots__ = [
        '__ua_response',
    ]

    def __init__(self, ua_response: Response):
        self.__ua_response = ua_response

    def status_code(self) -> int:
        return self.__ua_response.code()

    def status_message(self) -> str:
        return self.__ua_response.message()

    def header(self, case_insensitive_name: str) -> Optional[str]:
        return self.__ua_response.header(name=case_insensitive_name)

    def raw_data(self) -> bytes:
        return self.__ua_response.raw_data()


class _SitemapWebClient(AbstractWebClient):
    # Some webservers might be generating huge sitemaps on the fly, so this is why it's rather big.
    __HTTP_REQUEST_TIMEOUT = 60

    __slots__ = [
        '__ua',
    ]

    def __init__(self):
        self.__ua = UserAgent()
        self.__ua.set_timeout(self.__HTTP_REQUEST_TIMEOUT)

    def set_max_response_data_length(self, max_response_data_length: int) -> None:
        self.__ua.set_max_size(max_response_data_length)

    def get(self, url: str) -> AbstractWebClientResponse:
        ua_response = self.__ua.get(url)

        if ua_response.is_success():
            return _SitemapWebClientResponse(ua_response=ua_response)
        else:
            return WebClientErrorResponse(
                message=ua_response.status_line(),
                retryable=ua_response.code() in RETRYABLE_HTTP_STATUS_CODES,
            )


# FIXME add test for this function
def fetch_sitemap_pages_for_media_id(db: DatabaseHandler, media_id: int) -> None:
    """Fetch and store all pages (news stories or not) from media's sitemap tree."""
    media = db.find_by_id(table='media', object_id=media_id)
    if not media:
        raise Exception("Unable to find media with ID {}".format(media_id))

    media_url = media['url']

    log.info("Fetching sitemap pages for media ID {} ({})...".format(media_id, media_url))
    web_client = _SitemapWebClient()
    sitemaps = sitemap_tree_for_homepage(homepage_url=media_url, web_client=web_client)
    log.info("Fetched pages for media ID {} ({}).".format(media_id, media_url))

    log.info("Storing sitemap pages for media ID {} ({})...".format(media_id, media_url))

    insert_counter = 0
    for page in sitemaps.all_pages():
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
            log.info("Inserted {} URLs...".format(insert_counter))

    log.info("Done storing {} sitemap pages for media ID {} ({}).".format(insert_counter, media_id, media_url))
