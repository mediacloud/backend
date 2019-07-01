#!/usr/bin/env python

import mediawords.crawler.provider
import mediawords.db

def main():
    db = mediawords.db.connect_to_db()
    mediawords.crawler.provider.run_provider(db)


main()
