#!/usr/bin/env python

import time

import mediawords.crawler.download.feed.ap
import mediawords.db

AP_POLL_INTERVAL = 300

def main():
    while True:
        db = mediawords.db.connect_to_db()
        mediawords.crawler.download.feed.ap.get_and_add_new_stories(db)
        time.sleep(AP_POLL_INTERVAL)

main()
