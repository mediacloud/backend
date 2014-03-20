#! /usr/bin/env python

from distutils.core import setup

setup(name='mediacloud',
  version='1.6',
  description='MediaCloud API Client Library',
  author='Rahul Bhargava',
  author_email='rahulb@media.mit.edu',
  url='http://civic.mit.edu',
  packages={'mediacloud': 'mediacloud',
            'mediacloud.test': 'mediacloud/test'},
  package_data={'mediacloud':['data/*.csv'],
                'mediacloud.test':['fixtures/*.json']},
  requires=['pypubsub','requests','unicodecsv']
  )
