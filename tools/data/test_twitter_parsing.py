#!/usr/bin/env python

"""
generate a csv of stories that include 'twitter' anywhere in the content along with flags for whether each story
matches various strategies for matching twitter embeds
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



def find_tweets_in_story(story):
    tweet_dict = {}

    tweet_urls = re.findall(r'twitter.com/[^\s\'\"\?]+/status/[^s\'\"\?]+', 
                            story['content'])

    for tweet_url in tweet_urls:
         tweet_url = tweet_url.replace('\u002F', '/')
         tweet_url = tweet_url.replace('\\u002F', '/')
         log.warning("twitter link: %s" % str(tweet_url))
         m = re.search(r'twitter.com/([^/]+)/status/(\d+)', tweet_url)
         if m:
            (user, tweet_id) = m.groups()
            log.warning("[%s] %s" % (str(tweet_id), user))
            tweet_dict[tweet_id] = user 
         else:
            log.warning("TWEET NOT PARSED")

    return tweet_dict     



def find_status_of_twitter_stories(story, larger_story_list):
    story['content'] = story['raw_first_download_file']
    status = ''

    if "twitter.com" in story['content']:
        larger_story_list.append(story) 
        status = '.'
    elif story['content'] == '':
        status = '-'
    else:
        status = 'x'

    print(status, end="", flush=True, file=sys.stderr)



def write_story_list_data(story_list): 
    fieldnames = \
        'stories_id title url publish_date media_id media_name media_url tweets'.split()

    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames, extrasaction='ignore')
    writer.writeheader()
    for story in story_list:
        writer.writerow(story)



def main():
    num_stories = 100
    twitter_stories = []
    key = os.environ['MC_KEY']
    mc = mediacloud.api.AdminMediaCloud(key)

    # q = "tweet and stories_id:572029569"
    q = "tweet"
    fq = "publish_year:[2012-01-01T00:00:00Z TO 2019-01-01T00:00:00Z]"
    stories = mc.storyList(solr_query=q, solr_filter=fq, rows=num_stories, sort='random', raw_1st_download=True)
    log.warning('%d total stories found' % len(stories))


    for story in stories:
        find_status_of_twitter_stories(story, twitter_stories)
    print("")
    log.warning('%d twitter stories found' % len(twitter_stories))


    for story in twitter_stories:
        tweet_dict = find_tweets_in_story(story)

        story['tweets'] = []
        for tweet_id in tweet_dict.keys():
            log.warning("tweet_id: %s" % tweet_id)
            story['tweets'].append({'user': tweet_dict[tweet_id], 'id': tweet_id})

    write_story_list_data(twitter_stories)


main()


