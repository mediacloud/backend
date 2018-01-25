#!/usr/bin/env python

import os
import pytest
import sys

from mediawords.tm.guess_date import guess_date, McGuessDateException

def main():
    if (len(sys.argv) < 2):
        sys.stderr.write('usage: ' + sys.argv[0] + ' <directory of html files>')
        exit()

    directory = os.fsencode(sys.argv[1]).decode("utf-8")

    for file in os.listdir(directory):
        filename = os.fsdecode(file)
        if filename.endswith(".txt"):
            fh = open(os.path.join(directory,filename))
            content = fh.read()
            print(filename + ": " + str(len(content)))
            date_guess = guess_date(
                url='http://dont.know.the.date/some/path.html',
                html=content
            )
            print(date_guess.date)

main()
