"""Fetch web urls results from google."""

import csv
import datetime
import dateutil.parser
import io
import subprocess
import re

from mediawords.util.log import create_logger
from mediawords.util.parse_json import encode_json, decode_json
import mediawords.util.url

from topics_base.posts import get_mock_data, filter_posts_for_date_range
from topics_mine.posts import AbstractPostFetcher

log = create_logger(__name__)


class McPostsGenericDataException(Exception):
    """exception indicating an error in the data for generic posts."""
    pass


class GooglerWebPostFetcher(AbstractPostFetcher):

    def _get_mock_json(self, start_date: datetime, end_date: datetime):
        """return json in googler format derived from get_mock_data()."""
        mock_data = get_mock_data(start_date, end_date)

        json_data = []
        for d in mock_data:
            json_data.append({
                'abstract': d['content'],
                'url': 'http://foo.bar/' + d['post_id'],
                'title': d['content'],
                'metadata': dateutil.parser.parse(d['publish_date']).strftime('%b %e, %Y,')
            })

        return encode_json(json_data)

    def validate_mock_post(self, got_post: dict, mock_post: dict) -> None:
        """Use title + content for the content field."""
        got_urls = got_post['urls']

        assert len(got_urls) == 1

        got_url = got_urls[0]

        match = re.match(r'http://foo.bar/(.*)', str(got_url))
        assert match

        assert got_post['content'] == "%s %s %s" % (mock_post['content'], mock_post['content'], got_url)
        
    def fetch_posts_from_api(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Return posts from a csv that are within the given date range."""
        if self.mock_enabled:
            googler_json = self._get_mock_json(start_date, end_date)
        else:
            start_query = "after:" + start_date.strftime("%Y-%m-%d")
            end_query = "before:" + (end_date + datetime.timedelta(days=1)).strftime("%Y-%m-%d")

            full_query = "query %s %s" % (start_query, end_query)

            googler_json = subprocess.check_output(["googler", "--json", "-n 100", query])

        links = decode_json(googler_json)

        posts = []
        for link in links:
            publish_date = start_date.strftime('%Y-%m-%d')
            domain = mediawords.util.url.get_url_distinctive_domain(link['url'])

            posts.append(
                {
                    'post_id': link['url'],
                    'content': "%s %s %s" % (link['title'], link['abstract'], link['url']),
                    'author': domain,
                    'channel': domain,
                    'publish_date': publish_date,
                    'data': link
                })

        return posts
