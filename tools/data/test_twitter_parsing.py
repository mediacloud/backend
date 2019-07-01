#!/usr/bin/env python

"""
generate a csv of stories that include 'twitter' anywhere in the content along with flags for whether each story
matches various strategies for matching twitter embeds
"""

import csv
import os
import sys

import re
import mediacloud

import mediawords.db
import mediawords.dbi.downloads
import mediawords.util.log

log = mediawords.util.log.create_logger(__name__)

def main():
    db = mediawords.db.connect_to_db()

    num_stories = 1000

    twitter_stories = []

    # stories = db.query("""
    #     with random_sample as (
    #         select * from stories tablesample system(0.001) )

    #     select rs.*, m.name media_name, m.url media_url 
    #         from random_sample rs
    #             join media m using ( media_id )
    #         where publish_date >= '2012-01-01' order by random() limit %(a)s
    # """, {'a': num_stories}).hashes()

    key = os.environ['MC_KEY']
    mc = mediacloud.api.MediaCloud(key)

    # q = "tweet and stories_id:776718764"
    q = "tweet"
    fq = "publish_year:[2012-01-01T00:00:00Z TO 2018-01-01T00:00:00Z]"
    stories = mc.storyList(solr_query=q, solr_filter=fq, rows=num_stories, sort='random')

    log.warning('%d total stories found' % len(stories))

    for story in stories:
        download = db.query(
            "select * from downloads where stories_id = %(a)s order by downloads_id limit 1", 
            {'a': story['stories_id']}).hash()

        content = ''
        try:
            content = mediawords.dbi.downloads.fetch_content(db, download)
            story['content'] = content
        except Exception:
            pass

        status = ''
        if "twitter.com" in content:
            twitter_stories.append(story) 
            status = '.'
        elif content == '':
            status = '-'
        else:
            status = 'x'

        print(status, end="", flush=True, file=sys.stderr)

    print("")
    log.warning('%d twitter stories found' % len(twitter_stories))


    for story in twitter_stories:
        tweet_dict = {}
        tweet_urls = re.findall(r'twitter.com[^\s\'\"\?]+status[^s\'\"\?]+', story['content'])
        for tweet_url in tweet_urls:
            tweet_url = tweet_url.replace('\u002F', '/')
            log.warning("twitter link: %s" % str(tweet_url))
            m = re.search(r'twitter.com/([^/]+)/status/(\d+)', tweet_url)
            if m:
                (user, tweet_id) = m.groups()
                log.warning("[%s] %s" % (str(tweet_id), user))
                tweet_dict[tweet_id] = user 
            else:
                log.warning("TWEET NOT PARSED")

        story['tweets'] = []
        for tweet_id in tweet_dict.keys():
            log.warning("tweet_id: %s" % tweet_id)
            story['tweets'].append({'user': tweet_dict[tweet_id], 'id': tweet_id})

    fieldnames = \
        'stories_id title url publish_date media_id media_name media_url tweets'.split()

    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames, extrasaction='ignore')

    writer.writeheader()
    for story in twitter_stories:
        writer.writerow(story)

        
main()
