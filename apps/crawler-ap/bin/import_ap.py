#!/usr/bin/env python3

import glob
import sys

from mediawords.db import connect_to_db

from crawler_ap.ap import import_archive_file


def main():
    path = sys.argv[1]
    files = glob.glob(path + '/**/*.xml', recursive=True)

    db = connect_to_db()

    for i, f in enumerate(files):
        print('%s [%d/%d/' % (f, i, len(files)))
        import_archive_file(db, f)


if __name__ == '__main__':
    main()
