"""Use the Crimson Hexagon API to lookup tweets relevant to a topic, then fetch each of those tweets from twitter."""

from abc import ABC, abstractmethod
import datetime
import re
import time
import tweepy
import typing

from mediawords.db import DatabaseHandler
import mediawords.util.json
from mediawords.util.web.user_agent import UserAgent

from mediawords.util.log import create_logger
log = create_logger(__name__)


class McFetchTopicTweetsException(Exception):
    """default exception."""

    pass


class McFetchTopicTweetsDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""

    pass


class McFetchTopicTweetsConfigException(Exception):
    """exception indicating an error in the mediawords.yml configuration."""

    pass


class McFetchTopicTweetDateFetchedException(Exception):
    """exception indicating the topic tweets for the given day have already been fetched."""

    pass


class AbstractCrimsonHexagon(ABC):
    """abstract class that fetches data from Crimson Hexagon."""

    @staticmethod
    @abstractmethod
    def fetch_posts(ch_monitor_id: int, day: datetime.datetime) -> dict:
        """
        Fetch the list of tweets from the ch api.

        Arguments:
        ch_monitor_id - crimson hexagon monitor id
        day - date for which to fetch posts

        Return:
        list of ch posts directly decoded from the ch api json response
        """
        pass


class CrimsonHexagon(AbstractCrimsonHexagon):
    """class that fech_posts() method that can list posts via the Crimson Hexagon api."""

    @staticmethod
    def fetch_posts(ch_monitor_id: int, day: datetime.datetime) -> dict:
        """Implement fetch_posts on ch api using the config data from mediawords.yml."""
        ua = UserAgent()
        ua.set_max_size(100 * 1024 * 1024)
        ua.set_timeout(90)
        ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

        config = mediawords.util.config.get_config()
        if 'crimson_hexagon' not in config or 'key' not in config['crimson_hexagon']:
            raise McFetchTopicTweetsConfigException("no key in mediawords.yml at //crimson_hexagon/key.")

        key = config['crimson_hexagon']['key']

        next_day = day + datetime.timedelta(days=1)

        day_arg = day.strftime('%Y-%m-%d')
        next_day_arg = next_day.strftime('%Y-%m-%d')

        url = ("https://api.crimsonhexagon.com/api/monitor/posts?auth=%s&id=%d&start=%s&end=%s&extendLimit=true" %
               (key, ch_monitor_id, day_arg, next_day_arg))

        log.debug("crimson hexagon url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McFetchTopicTweetsDataException("error fetching posts: " + response.decoded_content())

        decoded_content = response.decoded_content()

        data = dict(mediawords.util.json.decode_json(decoded_content))

        if 'status' not in data or not data['status'] == 'success':
            raise McFetchTopicTweetsDataException("Unknown response status: " + str(data))

        return data


class AbstractTwitter(ABC):
    """abstract class that fetches data from Twitter."""

    @staticmethod
    @abstractmethod
    def fetch_100_tweets(tweet_ids: list) -> list:
        """
        Fetch up to 100 tweets from the twitter api.

        Throws a McFetchTopicTweetsError if more than 100 ids are in tweet_ids.

        Arguments:
        tweet_ids - list of tweet status ids

        Return:
        list of tweet dicts as directly decoded from the json from the twitter api statuses_list api
        """
        pass


class Twitter(AbstractTwitter):
    """class that fech_posts() method that can list posts via the Crimson Hexagon api."""

    @staticmethod
    def fetch_100_tweets(tweet_ids: list) -> list:
        """Implement fetch_tweets on twitter api using config data from mediawords.yml."""
        config = mediawords.util.config.get_config()

        if len(tweet_ids) > 100:
            raise McFetchTopicTweetsException('tried to fetch more than 100 tweets')

        if 'twitter' not in config:
            raise McFetchTopicTweetsConfigException('missing twitter configuration in mediawords.yml')

        for field in 'consumer_key consumer_secret access_token access_token_secret'.split():
            if field not in config['twitter']:
                raise McFetchTopicTweetsConfigException('missing //twitter//' + field + ' value in mediawords.yml')

        auth = tweepy.OAuthHandler(config['twitter']['consumer_key'], config['twitter']['consumer_secret'])
        auth.set_access_token(config['twitter']['access_token'], config['twitter']['access_token_secret'])

        # the RawParser lets us directly decode from json to dict below
        api = tweepy.API(auth, parser=tweepy.parsers.RawParser())

        # catch all errors and do backoff retries.  don't just catch rate limit errors because we want to be
        # robust in the face of temporary network or service provider errors.
        tweets = None
        twitter_retries = 0
        while tweets is None and twitter_retries <= 10:
            last_exception = None
            try:
                tweets = api.statuses_lookup(tweet_ids, include_entities=True, trim_user=False)
            except tweepy.TweepError as e:
                sleep = 2 * (twitter_retries**2)
                log.info("twitter fetch error.  waiting " + str(sleep) + " seconds before retry ...")
                time.sleep(sleep)
                last_exception = e

            twitter_retries += 1

        if tweets is None:
            raise McFetchTopicTweetsDataException("unable to fetch tweets: " + str(last_exception))

        # it is hard to mock tweepy data directly, and the default tweepy objects are not json serializable,
        # so just return a direct dict decoding of the raw twitter payload
        return list(mediawords.util.json.decode_json(tweets))


def _add_tweets_to_ch_posts(twitter_class: typing.Type[AbstractTwitter], ch_posts: list) -> None:
    """
    Given a set of ch_posts, fetch data from twitter about each tweet and attach it under the ch['tweet'] field.

    Arguments:
    twitter_class - AbstractTwitter class
    ch_posts - list of up to 100 posts from crimson hexagon as returned by CrimsonHexagon.fetch_posts

    Return:
    None
    """
    # statuses_lookup below only works for up to 100 tweets
    assert len(ch_posts) <= 100

    log.debug("fetching tweets for " + str(len(ch_posts)) + " tweets")

    ch_post_lookup = {}
    for ch_post in ch_posts:
        try:
            tweet_id = int(re.search(r'/status/(\d+)', ch_post['url']).group(1))
        except AttributeError:
            raise McFetchTopicTweetsDataException("Unable to parse id from tweet url: " + ch_post['url'])

        ch_post['tweet_id'] = tweet_id
        ch_post_lookup[tweet_id] = ch_post

    tweet_ids = list(ch_post_lookup.keys())

    tweets = None
    twitter_retries = 0
    last_exception = None
    while (tweets is None and twitter_retries <= 10):
        last_exception = None
        try:
            tweets = twitter_class.fetch_100_tweets(tweet_ids)
        except tweepy.TweepError as e:
            sleep = 2 * (twitter_retries**2)
            log.debug("twitter fetch error.  waiting sleep seconds before retry ...")
            time.sleep(sleep)
            last_exception = e

        twitter_retries += 1

    if tweets is None:
        raise McFetchTopicTweetsDataException("unable to fetch tweets: " + str(last_exception))

    log.debug("fetched " + str(len(tweets)) + " tweets")

    for tweet in tweets:
        ch_post_lookup[tweet['id']]['tweet'] = tweet

    for ch_post in ch_posts:
        if 'tweet' not in ch_post:
            log.debug("no tweet fetched for url " + ch_post['url'])


def _store_tweet_and_urls(db: DatabaseHandler, topic_tweet_day: dict, ch_post: dict) -> None:
    """
    Store the tweet in topic_tweets and its urls in topic_tweet_urls, using the data in ch_post.

    Arguments:
    db - database handler
    topic - topic dict
    topic_tweet_day - topic_tweet_day dict
    ch_post - ch_post dict

    Return:
    None
    """
    data_json = mediawords.util.json.encode_json(ch_post)

    # null characters are not legal in json but for some reason get stuck in these tweets
    data_json = data_json.replace('\x00', '')

    topic_tweet = {
        'topic_tweet_days_id': topic_tweet_day['topic_tweet_days_id'],
        'data': data_json,
        'content': ch_post['tweet']['text'],
        'tweet_id': ch_post['tweet_id'],
        'publish_date': ch_post['tweet']['created_at'],
        'twitter_user': ch_post['tweet']['user']['screen_name']
    }

    topic_tweet = db.create('topic_tweets', topic_tweet)

    urls_inserted = {}  # type:typing.Dict[str, bool]
    for url_data in ch_post['tweet']['entities']['urls']:

        url = url_data['expanded_url']

        if url in urls_inserted:
            break

        urls_inserted[url] = True

        db.create(
            'topic_tweet_urls',
            {
                'topic_tweets_id': topic_tweet['topic_tweets_id'],
                'url': url[0:1024]
            })


def _fetch_tweets_for_day(
        db: DatabaseHandler,
        twitter_class: typing.Type[AbstractTwitter],
        topic: dict,
        topic_tweet_day: dict,
        max_tweets: typing.Optional[int]=None) -> None:
    """
    Fetch tweets for a single day.

    If tweets_fetched is false for the given topic_tweet_days row, fetch the tweets for the given day by querying
    the list of tweets from CH and then fetching each tweet from twitter.

    Arguments:
    db - db handle
    twitter_class - AbstractTwitter class
    topic - topic dict
    topic_tweet_day - topic_tweet_day dict
    max_tweets - max tweets to fetch for a single day

    Return:
    None
    """
    if topic_tweet_day['tweets_fetched']:
        return

    ch_posts_data = topic_tweet_day['ch_posts']

    ch_posts = ch_posts_data['posts']

    if (max_tweets is not None):
        ch_posts = ch_posts[0:max_tweets]

    log.debug("adding %d tweets for topic %s, day %s" % (len(ch_posts), topic['topics_id'], topic_tweet_day['day']))

    # we can only get 100 posts at a time from twitter
    for i in range(0, len(ch_posts), 100):
        _add_tweets_to_ch_posts(twitter_class, ch_posts[i:i + 100])

    db.begin()

    log.debug("inserting into topic_tweets ...")

    for ch_post in ch_posts:
        if 'tweet' in ch_post:
            _store_tweet_and_urls(db, topic_tweet_day, ch_post)

    num_deleted_tweets = len(list(filter(lambda x: 'tweet' not in x, ch_posts)))
    topic_tweet_day['num_ch_tweets'] -= num_deleted_tweets

    db.query(
        "update topic_tweet_days set tweets_fetched = true, num_ch_tweets = %(a)s where topic_tweet_days_id = %(b)s",
        {'a': topic_tweet_day['num_ch_tweets'], 'b': topic_tweet_day['topic_tweet_days_id']})

    db.commit()

    log.debug("done inserting into topic_tweets")


def _add_topic_tweet_single_day(
        db: DatabaseHandler,
        topic: dict,
        day: datetime.datetime,
        ch_class: typing.Type[AbstractCrimsonHexagon]) -> dict:
    """
    Add a row to topic_tweet_day if it does not already exist.  fetch data for new row from CH.

    Arguments:
    db - database handle
    topic - topic dict
    day - date to fetch eg '2017-12-30'
    ch_class - AbstractCrimsonHexagon class

    Return:
    None
    """
    # the perl-python layer was segfaulting until I added the str() around day below -hal
    topic_tweet_day = db.query(
        "select * from topic_tweet_days where topics_id = %(a)s and day = %(b)s",
        {'a': topic['topics_id'], 'b': str(day)}).hash()

    if topic_tweet_day is not None and topic_tweet_day['tweets_fetched']:
        raise McFetchTopicTweetDateFetchedException("tweets already fetched for day " + str(day))

    # if we have a ttd but had not finished fetching tweets, delete it and start over
    if topic_tweet_day is not None:
        db.delete_by_id('topic_tweet_days', topic_tweet_day['topic_tweet_days_id'])

    ch_posts = ch_class.fetch_posts(topic['ch_monitor_id'], day)

    tweet_count = ch_posts['totalPostsAvailable']

    num_ch_tweets = len(ch_posts['posts'])

    topic_tweet_day = db.create(
        'topic_tweet_days',
        {
            'topics_id': topic['topics_id'],
            'day': day,
            'tweet_count': tweet_count,
            'num_ch_tweets': num_ch_tweets,
            'tweets_fetched': False
        })

    topic_tweet_day['ch_posts'] = ch_posts

    return topic_tweet_day


def _add_topic_tweet_days(
        db: DatabaseHandler,
        topic: dict,
        twitter_class: typing.Type[AbstractTwitter],
        ch_class: typing.Type[AbstractCrimsonHexagon]) -> None:
    """
    For each day within the topic date range, find or create a topic_tweet_day row and fetch data for that row from CH.

    Arguments:
    db - database handle
    topic - topic dict
    twitter_class - AbstractTwitter class
    ch_class - AbstractCrimsonHexagon class

    Return:
    None
    """
    date = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')
    end_date = datetime.datetime.strptime(topic['end_date'], '%Y-%m-%d')
    while date <= end_date:
        try:
            topic_tweet_day = _add_topic_tweet_single_day(db, topic, date, ch_class)
            _fetch_tweets_for_day(db, twitter_class, topic, topic_tweet_day)
        except McFetchTopicTweetDateFetchedException:
            pass

        date = date + datetime.timedelta(days=1)


def fetch_topic_tweets(
        db: DatabaseHandler,
        topics_id: int,
        twitter_class: typing.Type[AbstractTwitter]=Twitter,
        ch_class: typing.Type[AbstractCrimsonHexagon]=CrimsonHexagon) -> None:
    """
    Fetch list of tweets within a Crimson Hexagon monitor based on the ch_monitor_id of the given topic.

    Crimson Hexagon returns up to 10k randomly sampled tweets per posts fetch, and each posts fetch can be restricted
    down to a single day.  This call fetches tweets from CH day by day, up to a total of 1 million tweets for a single
    topic for the whole date range combined.  The call normalizes the number of tweets returned for each day so that
    each day has the same percentage of all tweets found on that day.  So if there were 20,000 tweets found on the
    busiest day, each day will use at most 50% of the returned tweets for the day.

    One call to this function takes care of both fetching the list of all tweets from CH and fetching each of those
    tweets from twitter (CH does not provide the tweet content, only the url).  Each day's worth of tweets will be
    recorded in topic_tweet_days, and subsequent calls to the function will not refetch a given day for a given topic,
    but each call will fetch any days newly included in the date range of the topic given a topic dates change.

    If there is no ch_monitor_id for the topic, do nothing.

    Arguments:
    db - db handle
    topics_id - topic id
    twitter_class - optional implementation of AbstractTwitter class;
        default to one that fetches data from twitter with config from mediawords.yml
    ch_class - optional implementation of AbstractCrimsonHexagon class;
        default to one that fetches data from twitter with config from mediawords.yml

    Return:
    None
    """
    topic = db.require_by_id('topics', topics_id)
    ch_monitor_id = topic['ch_monitor_id']

    if ch_monitor_id is None:
        log.debug("returning after noop because topic topics_id has a null ch_monitor_id")
        return

    _add_topic_tweet_days(db, topic, twitter_class, ch_class)
