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

    twitter_tweet_match = bool(re.search(r'twitter-tweet[^/]+((?<=<)/p>[^/]+((?<=<)/p>[^/]+)?)?//'+
                                         r'twitter\.com/' + user + '/status/' + tweet_id,
                                         tweet_source))

    at_symbol_match = bool(re.search(r'@' + user + r'[^:]+://' + 
                                     r'twitter\.com/' + user + '/status/' + tweet_id,
                                     tweet_source))

    widget_link_match = bool(re.search(r'twitter\.com/' + user + '/status/' + tweet_id +
                                       r'[^>]*>[^/]+(/a)?[^/]*(/p)?[^/]*(/blockquote)?[^/]*(/p)?[^/]*' + 
                                       r'(/cdn-cdg/scripts/5c5dd728/cloudfare-static/email-decode\.min\.js)?' + 
                                       r'[^/]*//?platform\.twitter\.com/widgets\.js',
                                       tweet_source))

    return twitter_tweet_match or at_symbol_match or widget_link_match



def find_tweets_in_html(story_content: str) -> list:
    """ Finds any tweets in a string of html.

    Returns a list of dicts for each of the tweets found in the inputed string.

    """

    tweet_list = []

    tweet_urls = re.findall(r'twitter.com/[^\s\'\"\?]+/status/[^s\'\"\?]+',
                            story_content)

    for tweet_url in tweet_urls:
         tweet_url = tweet_url.replace('\u002F', '/')  # This is here twice on purpose: 
         tweet_url = tweet_url.replace('\\u002F', '/')  # some sites escape their backslashes for unicode characters
         log.debug("twitter link: %s" % str(tweet_url))

         m = re.search(r'twitter.com/([^/]+)/status/(\d+)',
                       tweet_url)
         if m:
            (user, tweet_id) = m.groups()
            log.debug("[%s] %s" % (str(tweet_id), user))


            e = _is_tweet_embedded(user, tweet_id, story_content)

            log.debug("User Handle: " + str(user))
            log.debug("Tweet ID: " + str(tweet_id))
            log.debug("Embedded: " + str(e))

            tweet_list.append({'user': user, 'id': tweet_id, 'embedded': e})

         else:
            log.debug("TWEET NOT PARSED")

    log.debug('Final twitter dictionary: ' + str(tweet_list))
    return tweet_list


