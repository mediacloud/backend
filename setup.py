#! /usr/bin/env python

from distutils.core import setup

setup(name='mediacloud',
  version='0.2',
  description='MediaCloud API Client Library',
  author='Rahul Bhargava',
  author_email='rahulb@media.mit.edu',
  url='http://civic.mit.edu',
  packages=['mediacloud',
            'mediacloud.readability',
            'mediacloud.test'],
  package_data={'mediacloud':['mediacloud/data/*.csv'],
                'mediacloud.readability':['mediacloud/files/*.pickle','mediacloud/files/*.txt'],
                'mediacloud.test':['mediacloud/fixtures/*.json']},
  requires=['pypubsub','nltk','couchdb','pymongo','tldextract','requests']
  )
