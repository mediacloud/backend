#!/usr/bin/env python3

import time

from mediawords.db import connect_to_db

from crawler_ap.ap import get_new_stories, add_new_stories

AP_POLL_INTERVAL = 300


def main():
    while True:
        db = connect_to_db()
        new_stories = get_new_stories()
        add_new_stories(db=db, new_stories=new_stories)
        time.sleep(AP_POLL_INTERVAL)


if __name__ == '__main__':
    main()
