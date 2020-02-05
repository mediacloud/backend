from collections import defaultdict
import datetime
import dateutil.parser
import json
import os
import requests
import string
import time
import typing

from jinja2 import Template
import requests_mock

from topics_base.posts import get_mock_data
from topics_mine.posts import AbstractPostFetcher

from mediawords.util.log import create_logger
log = create_logger(__name__)


class McPushshiftError(Exception):
    '''Base error class'''
    pass


class McPushshiftSubmissionFetchError(McPushshiftError):
    '''Pushshift Submission Fetch exception error.'''
    pass

#{'query': {'function_score': {'random_score': {'seed': 1580848451258}, 'query': {'bool': {'must': [{'simple_query_string': {'query': '123', 'fields': ['title', 'selftext'], 'default_operator': 'and'}}, {'range': {'created_utc': {'gte': 1546318800.0}}}, {'range': {'created_utc': {'lt': 1554868800.0}}}]}}}}}


def _mock_pushshift(request, context) -> str:
    """Mock response from pushshift based on posts.get_mock_data."""
    filters = request.json()['query']['function_score']['query']['bool']['must']

    start_date = None
    end_date = None
    for filter in filters:
        if not 'range' in filter:
            continue

        created_utc = filter['range']['created_utc']

        if 'gte' in created_utc:
            start_date = datetime.datetime.fromtimestamp(created_utc['gte'])
        elif 'lt' in created_utc:
            end_date = datetime.datetime.fromtimestamp(created_utc['lt'])

    assert((end_date is not None) and (start_date is not None))

    base_dir = os.path.dirname(os.path.realpath(__file__))
    response_template_file = base_dir + "/pushshift_response.json.jinja"

    posts = get_mock_data(start_date, end_date)

    for post in posts:
        post['publish_epoch'] = dateutil.parser.parse(post['publish_date']).timestamp()

    with open(response_template_file) as f:
        template = Template(f.read())
        response_json = template.render(posts=posts)

    log.warning(response_json)

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}

    return response_json


class PushshiftRedditPostFetcher(AbstractPostFetcher):

    @staticmethod
    def _convert_epoch_to_iso8601(epoch: int) -> str:
        '''Convert epoch to UTC ISO 8601 format'''
        return datetime.datetime.utcfromtimestamp(epoch).strftime("%Y-%m-%d %H:%M:%S")

    @staticmethod
    def _base36encode(number: int) -> str:
        '''Convert base 10 integer to base 36 Reddit style representation'''
        alphabet = string.digits + string.ascii_lowercase

        if not isinstance(number, int):
            raise TypeError('number must be an integer')

        base36 = ''
        sign = ''

        if number < 0:
            sign = '-'
            number = -number

        if 0 <= number < len(alphabet):
            return sign + alphabet[number]

        while number != 0:
            number, i = divmod(number, len(alphabet))
            base36 = alphabet[i] + base36

        return sign + base36

    @staticmethod
    def _make_pushshift_api_request(es_query: dict) -> dict:
        '''Pushshift API method to request data from Pushshift API'''

        headers = {'user-agent': 'mediacloud',
                'content-type': 'application/json'}
        url = 'https://mediacloud.pushshift.io/rs/_search'
        r = requests.get(url, headers=headers, data=json.dumps(es_query))

        if r.status_code == 200:
            data = r.json()
            shard_info = data['_shards']

            # Make sure all shards returned data
            if (shard_info['total'] != shard_info['successful']) or shard_info['failed'] > 0:
                log.warning("Total shards: {}, successful shards: {}, failed shards: {}".format(shard_info['total'],
                    shard_info['successful'],
                    shard_info['failed']))

            return data['hits']['hits']
        else:
            raise McPushshiftSubmissionFetchError(r.content)

    @staticmethod
    def _pushshift_query_builder(query: str = None,
            start_date: datetime = None,
            end_date: datetime = None,
            sort_field: str = None,
            size: int = 100,
            randomize: bool = True,
            sort_dir: str = "desc") -> list:

        '''Pushshift Elasticsearch query builder'''

        q = defaultdict(dict)
        q['size'] = size

        # Add Random sampling component if requested
        if randomize:
            q['query']['function_score'] = {}
            q['query']['function_score']['random_score'] = {}
            q['query']['function_score']['random_score']['seed'] = int(time.time() * 1000)
            q['query']['function_score']['query'] = defaultdict(dict)
            q['query']['function_score']['query']['bool']['must'] = filters = []
        else:
            q['query']['bool'] = {}
            q['query']['bool']['must'] = filters = []

        if sort_field is not None:
            q['sort'] = {sort_field: sort_dir}

        sqs = defaultdict(dict)
        sqs['simple_query_string']['query'] = query
        sqs['simple_query_string']['fields'] = ["title", "selftext"]
        sqs['simple_query_string']['default_operator'] = "and"
        filters.append(sqs)

        if start_date is not None:
            filters.append({'range': {'created_utc': {'gte': start_date.timestamp()}}})

        if end_date is not None:
            filters.append({'range': {'created_utc': {'lt': end_date.timestamp()}}})

        return q

    @staticmethod
    def _build_response(rows: list) -> list:
        '''Build a response list from the elasticsearch data'''

        results = []

        for row in rows:
            obj = {}
            #obj['post_id'] = PushshiftRedditPostFetcher._base36encode(int(row['_id']))
            obj['post_id'] = int(row['_id'])
            obj['author'] = row['_source']['author']

            # Build content field using title and selftext (if it exists)
            content = row['_source']['title']
            if 'selftext' in row['_source'] and row['_source']['selftext'] is not None:
                content = "{} {}".format(content, row['_source']['selftext'])
            obj['content'] = content

            obj['channel'] = row['_source']['subreddit']
            obj['publish_date'] = PushshiftRedditPostFetcher._convert_epoch_to_iso8601(row['_source']['created_utc'])
            base36_subreddit_id = PushshiftRedditPostFetcher._base36encode(int(row['_source']['subreddit_id']))
            row['_source']['subreddit_id'] = "t5_{}".format(base36_subreddit_id)
            obj['data'] = row['_source']
            obj['data']['id'] = obj['post_id']
            obj['data']['name'] = "t3_{}".format(obj['post_id'])
            results.append(obj)

        return results

    def setup_mock_data(self, mocker: requests_mock.Mocker) -> None:
        """Setup mock handler for pushshift requests."""
        url = 'https://mediacloud.pushshift.io/rs/_search'
        mocker.get(url, text=_mock_pushshift)

    def validate_mock_post(self, got_post: dict, expected_post: dict) -> None:
        """Use title + content for the content field."""
        for field in ('post_id', 'author', 'channel'):
            log.warning("%s: %s <-> %s" % (field, got_post[field], expected_post[field]))
            assert got_post[field] == expected_post[field], "field %s does not match" % field

        assert got_post['content'] == "Title %s" % expected_post['content']

    def fetch_posts_from_api(
            self,
            query: str,
            start_date: datetime,
            end_date: datetime,
            sample: typing.Optional[int] = None) -> list:
        """Fetch submissions from Pushshift using POST calls to the Elasticsearch backend

            Parameters:

                query       - String form of a boolean query
                start_date  - The start date of the query in the format YYYY-MM-DD (inclusive to 00:00:00 UTC)
                end_date    - The end date of the query in the format YYYY-MM-DD (incluse to 23:59:59 UTC)
                sample      - Randomize the sample and return at maximum this many objects

            Returns:

                List of dictionaries with the following fields

                post_id         - String containing the platform specific unique id for the post
                content         - String containing the text content of the post
                publish_date    - The date that the post was published (UTC) in string format YYYY-MM-DD HH:MM:SS (ISO 8601)
                author          - String containing the author of the post
                channel         - String containing the subreddit of the post
                data            - Dictionary containing the full raw data returned by the original API (api.reddit.com)

        """

        es_query = self._pushshift_query_builder(query, start_date, end_date, size=sample)
        log.debug("pushshift reddit query: %s" % es_query)
        es_results = self._make_pushshift_api_request(es_query)
        results = self._build_response(es_results)

        return results

