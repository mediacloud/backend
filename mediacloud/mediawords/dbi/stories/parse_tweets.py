#!/usr/bin/env python

"""
detects tweets in a body of text. 
stores the user handle of the poster, tweet id, 
and whether or not that tweet had been embedded.
"""

import csv
import os
import sys

import re
import mediacloud.api

import mediawords.db
import mediawords.dbi.downloads
import mediawords.util.log

log = mediawords.util.log.create_logger(__name__)




def _is_tweet_embedded(user: str, tweet_id: str, tweet_source: str) -> bool:
    """ Search whether or not a tweet that has been found is also embedded.

    user = the twitter handle attatched to the tweet
    tweet_id = the id of the tweet
    tweet_source = The body of text in which the tweet was originally found

    Returns a boolean for whether or not a tweet is embedded.

    """

    return bool(re.search(

    r'twitter-tweet[^/]+((?<=<)/p>[^/]+((?<=<)/p>[^/]+)?)?//' +
    'twitter\.com/' + user + '/status/' + tweet_id,

                     tweet_source)) or bool(re.search(

r'@' + user + r'[^:]+://' +
'twitter\.com/' + user + '/status/' + tweet_id,

                     tweet_source)) or bool(re.search(

'twitter.com/' + user + '/status/' + tweet_id +
r'[^>]*>[^/]+(/a)?[^/]*(/p)?[^/]*(/blockquote)?[^/]*(/p)?\
[^/]*(/cdn-cdg/scripts/5c5dd728/cloudfare-static/email-decode\.min\.js)?\
[^/]*//?platform\.twitter\.com/widgets\.js',

                     tweet_source))



def find_tweets_in_html(story_content: str) -> list:
    """ Finds any tweets in a string of html.

Returns a list of dicts for each of the tweets found in the inputed string.

    """

    tweet_list = []

    tweet_urls = re.findall(r'twitter.com/[^\s\'\"\?]+/status/[^s\'\"\?]+',
                            story_content)

    for tweet_url in tweet_urls:
         tweet_url = tweet_url.replace('\u002F', '/')
         tweet_url = tweet_url.replace('\\u002F', '/')
         log.debug("twitter link: %s" % str(tweet_url))

         m = re.search(r'twitter.com/([^/]+)/status/(\d+)',
                       tweet_url)
         if m:
            (user, tweet_id) = m.groups()
            log.debug("[%s] %s" % (str(tweet_id), user))


            e = _find_if_tweet_is_embedded(user, tweet_id, story_content)


            log.debug("Embedded: " + str(e))
            tweet_list.append({'user': user, 'id': tweet_id, 'embedded': e})

         else:
            log.debug("TWEET NOT PARSED")

    log.debug(tweet_list)
    return tweet_list

log.warning(find_tweets_in_html(r'dvanced Pikelet Threat 👩🏻‍💻🥞🦄✨ (@pikelet) &lt;a href=\\\"https://twitter.com/pikelet/status/1024205453788557312?ref_src=twsrc%5Etfw\\\">July 31, 2018&lt;/a>&lt;/blockquote>\\n&lt;script async src=\\\"https://platform.twitter.com/widgets.js\\\''))



