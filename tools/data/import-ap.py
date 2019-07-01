#!/usr/bin/env python

import glob
import sys
import xmltodict

import mediawords.db
import mediawords.crawler.download.feed.ap as ap

def main():
    path = sys.argv[1]
    files = glob.glob(path + '/**/*.xml', recursive=True)

    db = mediawords.db.connect_to_db()

    for i, f in enumerate(files):
        print('%s [%d/%d/' % (f, i, len(files)))
        ap.import_archive_file(db, f)

main()
