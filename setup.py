#! /usr/bin/env python

from distutils.core import setup

setup(name='mediacloud',
  version='2.0',
  description='MediaCloud API Client Library',
  author='Rahul Bhargava',
  author_email='rahulb@media.mit.edu',
  url='http://civic.mit.edu',
  packages={'mediacloud': 'mediacloud',
            'mediacloud.test': 'mediacloud/test'},
  package_data={'mediacloud.test':['fixtures/*.json']},
  requires=['pypubsub','requests','unicodecsv']
  )
